// Disposable SQL fixture only. No production connections or credentials.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const native=!!process.env.SKO_APPLE_ENROLLMENT_NATIVE_URL;
const Runtime=native?(await import('./native_apple_enrollment_native_runtime.mjs')).NativeRuntime:
 (await import(process.env.SKO_APPLE_ENROLLMENT_PGLITE)).PGlite;
const a='00000000-0000-0000-0000-000000000001',b='00000000-0000-0000-0000-000000000002',c='00000000-0000-0000-0000-000000000003';
async function fixture(fn){const db=new Runtime();try{
 await db.exec(`do $$declare r text;begin foreach r in array array['anon','authenticated','service_role','supabase_auth_admin'] loop
  if not exists(select 1 from pg_roles where rolname=r) then execute format('create role %I',r);end if;end loop;end$$;
  create schema auth;create table auth.users(id uuid primary key,raw_user_meta_data jsonb default '{}'::jsonb,deleted_at timestamptz);
  create table auth.identities(id uuid primary key default gen_random_uuid(),user_id uuid references auth.users on delete cascade,
   provider text not null,provider_id text not null,identity_data jsonb not null,unique(provider,provider_id));`);
 await db.exec(readFileSync(new URL('./owner-policy.sql.review-only',import.meta.url),'utf8'));
 await db.exec(readFileSync(new URL('./google-protection.sql.review-only',import.meta.url),'utf8'));
 const q=async(s,p=[])=>(await db.query(s,p)).rows;
 await db.query('insert into auth.users(id) values($1),($2),($3)',[a,b,c]);
 const identity=async(uid,provider,subject)=>db.query('insert into auth.identities(user_id,provider,provider_id,identity_data) values($1,$2,$3,jsonb_build_object(\'sub\',$3::text))',[uid,provider,subject]);
 const enable=async()=>q('select apple_google_protection.enable_reviewed() r');
 const state=async()=> (await q(`select jsonb_build_object('users',(select jsonb_agg(to_jsonb(u) order by id)from auth.users u),
  'identities',(select coalesce(jsonb_agg(to_jsonb(i) order by id),'[]')from auth.identities i),
  'permits',(select coalesce(jsonb_agg(to_jsonb(p) order by apple_subject),'[]')from apple_owner_policy.subject_permits p),
  'owners',(select coalesce(jsonb_agg(to_jsonb(o) order by provider_id),'[]')from apple_google_protection.google_subject_owners o),
  'protected',(select coalesce(jsonb_agg(to_jsonb(p) order by user_id),'[]')from apple_owner_policy.protected_users p))s`))[0].s;
 await fn({db,q,identity,enable,state});
}finally{await db.close();}}
test('installation is OFF and bookkeeping is inaccessible to clients or service-role',()=>fixture(async f=>{
 await f.identity(a,'google','google-a');await f.identity(a,'apple','apple-off');
 assert.equal((await f.q('select count(*)::int n from apple_owner_policy.protected_users'))[0].n,0);
 for(const role of ['anon','authenticated','service_role']){
  const x=(await f.q("select has_schema_privilege($1,'apple_google_protection','USAGE') u,has_function_privilege($1,'apple_google_protection.enable_reviewed()','EXECUTE') x",[role]))[0];assert.equal(x.u,false);assert.equal(x.x,false);
 }
}));
test('activation protects every existing actual Google UID without trusting user metadata',()=>fixture(async f=>{
 await f.identity(a,'google','google-a');await f.identity(b,'google','google-b');
 await f.db.query('update auth.users set raw_user_meta_data=$1 where id=$2',[JSON.stringify({provider:'google',providers:['google']}),c]);
 const before=(await f.state()).users;const activated=(await f.enable())[0].r;
 assert.deepEqual(activated,{enabled:true,google_identities_protected:2});
 assert.deepEqual((await f.q('select user_id from apple_owner_policy.protected_users order by user_id')).map(x=>x.user_id),[a,b]);
 assert.deepEqual((await f.state()).users,before);await assert.rejects(f.enable(),/inactive state/);
}));
test('new and returning Google registrations persist protection while ordinary email/password identities are unchanged',()=>fixture(async f=>{
 await f.enable();await f.identity(a,'google','google-a');await f.identity(b,'google','google-b');await f.identity(a,'email','email-a');
 await f.db.query("update auth.identities set identity_data=identity_data||'{\"name\":\"updated\"}' where provider='google'");
 assert.equal((await f.q('select count(*)::int n from apple_google_protection.google_subject_owners'))[0].n,2);
 assert.equal((await f.q('select count(*)::int n from apple_owner_policy.protected_users'))[0].n,2);
}));
test('unregistered Apple direct writes, updates and forged user metadata cannot bypass Google ownership',()=>fixture(async f=>{
 await f.identity(a,'google','google-a');await f.enable();
 await f.db.query('update auth.users set raw_user_meta_data=$1 where id=$2',[JSON.stringify({protected:false,provider:'none',providers:[]}),a]);
 const before=await f.state();await assert.rejects(f.identity(a,'apple','unregistered'),/verification unavailable/);assert.deepEqual(await f.state(),before);
 await f.identity(b,'apple','unrelated');const previous=await f.state();await assert.rejects(f.db.query("update auth.identities set user_id=$1 where provider='apple'",[a]),/verification unavailable/);assert.deepEqual(await f.state(),previous);
}));
test('same-UID permits admit Apple while a reserved subject cannot move to another UID',()=>fixture(async f=>{
 await f.identity(a,'google','google-a');await f.enable();
 await f.db.query('insert into apple_owner_policy.subject_permits values($1,$2)',['permitted',a]);await f.identity(a,'apple','permitted');
 const before=await f.state();await assert.rejects(f.db.query("update auth.identities set user_id=$1 where provider='apple'",[b]),/verification unavailable/);assert.deepEqual(await f.state(),before);
 await f.db.query("delete from auth.identities where provider='apple'");await assert.rejects(f.identity(b,'apple','permitted'),/verification unavailable/);
}));
test('Google cannot auto-merge into an unapproved Apple-first UID',()=>fixture(async f=>{
 await f.identity(a,'apple','apple-first');await f.enable();const before=await f.state();
 await assert.rejects(f.identity(a,'google','new-google'),/verification unavailable/);assert.deepEqual(await f.state(),before);
}));
test('activation stops on an existing unpermitted Google/Apple mixture instead of fabricating enrollment',()=>fixture(async f=>{
 await f.identity(a,'google','google-a');await f.identity(a,'apple','unknown-existing');const before=await f.state();
 await assert.rejects(f.enable(),/reviewed same-UID enrollment/);assert.deepEqual(await f.state(),before);
 assert.equal((await f.q('select count(*)::int n from apple_google_protection.rollout'))[0].n,0);
}));
test('unlink/delete retains Google UID and subject tombstones and rejects silent new-UID recreation',()=>fixture(async f=>{
 await f.identity(a,'google','google-a');await f.enable();await f.db.query('delete from auth.users where id=$1',[a]);
 assert.equal((await f.q('select user_id from apple_google_protection.google_subject_owners'))[0].user_id,a);
 assert.equal((await f.q('select user_id from apple_owner_policy.protected_users'))[0].user_id,a);
 const before=await f.state();await assert.rejects(f.identity(b,'google','google-a'),/verification unavailable/);assert.deepEqual(await f.state(),before);
}));
test('Google subject/UID reassignment cannot change a previously recorded owner',()=>fixture(async f=>{
 await f.identity(a,'google','google-a');await f.enable();const before=await f.state();
 await assert.rejects(f.db.query("update auth.identities set user_id=$1 where provider='google'",[b]),/verification unavailable/);assert.deepEqual(await f.state(),before);
}));
test('later Auth transaction failure rolls new Google identity and protection back together',()=>fixture(async f=>{
 await f.enable();const before=await f.state();await f.db.exec('begin');await f.identity(a,'google','google-a');
 await assert.rejects(f.db.exec("select no_such_synthetic_auth_function()"));await f.db.exec('rollback');assert.deepEqual(await f.state(),before);
}));
test('later token-hook rollout drift does not disable the activated identity-write guard',()=>fixture(async f=>{
 await f.identity(a,'google','google-a');await f.enable();await f.db.exec('update apple_owner_policy.rollout set enabled=false');
 const before=await f.state();await assert.rejects(f.identity(a,'apple','unknown'),/verification unavailable/);assert.deepEqual(await f.state(),before);
}));
test('official soft-delete metadata clearing and exact subject obfuscation retain original ownership',()=>fixture(async f=>{
 await f.identity(a,'google','google-a');await f.enable();
 await f.db.query('insert into apple_owner_policy.subject_permits values($1,$2)',['permitted',a]);await f.identity(a,'apple','permitted');
 await f.db.query('update auth.users set deleted_at=clock_timestamp() where id=$1',[a]);
 await f.db.query("update auth.identities set identity_data='{}'::jsonb where user_id=$1",[a]);
 for(const i of await f.q('select id,provider,provider_id from auth.identities where user_id=$1',[a])){
  const obfuscated=createHash('sha256').update(a+i.provider+':'+i.provider_id).digest('base64url');
  await f.db.query('update auth.identities set provider_id=$1 where id=$2',[obfuscated,i.id]);
 }
 assert.deepEqual((await f.q('select provider_id,user_id from apple_google_protection.google_subject_owners')),[{provider_id:'google-a',user_id:a}]);
 assert.equal((await f.q('select expected_user_id from apple_owner_policy.subject_permits'))[0].expected_user_id,a);
 await assert.rejects(f.identity(b,'google','google-a'),/verification unavailable/);await assert.rejects(f.identity(b,'apple','permitted'),/verification unavailable/);
}));
test('user metadata deleted_at cannot authorize soft-delete cleanup or remove protection',()=>fixture(async f=>{
 await f.identity(a,'google','google-a');await f.enable();
 await f.db.query('update auth.users set raw_user_meta_data=$1 where id=$2',[JSON.stringify({deleted_at:'2026-10-26T00:00:00Z',protected:false}),a]);
 const before=await f.state();await assert.rejects(f.db.query("update auth.identities set identity_data='{}'::jsonb where user_id=$1",[a]),/verification unavailable/);assert.deepEqual(await f.state(),before);
}));
test('already soft-deleted obfuscated identities are not mistaken for live Google subjects during seed',()=>fixture(async f=>{
 await f.identity(a,'google','old-google');await f.identity(b,'google','live-google');
 await f.db.query('update auth.users set deleted_at=clock_timestamp() where id=$1',[a]);
 await f.db.query("update auth.identities set identity_data='{}'::jsonb,provider_id='previously-obfuscated' where user_id=$1",[a]);
 const result=(await f.enable())[0].r;assert.equal(result.google_identities_protected,1);
 assert.deepEqual((await f.q('select provider_id,user_id from apple_google_protection.google_subject_owners')),[{provider_id:'live-google',user_id:b}]);
}));
test('Native Google/Apple same-UID race never commits an unapproved mixed identity',{skip:!native},()=>fixture(async f=>{
 await f.enable();const peer=await f.db.peer();
 const q='insert into auth.identities(user_id,provider,provider_id,identity_data) values($1,$2,$3,jsonb_build_object(\'sub\',$3::text))';
 const result=await Promise.allSettled([f.db.query(q,[a,'google','racing-google']),peer.query(q,[a,'apple','racing-apple'])]);
 assert.equal(result.filter(r=>r.status==='fulfilled').length,1);assert.equal(result.filter(r=>r.status==='rejected').length,1);
 assert.equal((await f.q('select count(*)::int n from auth.identities where user_id=$1',[a]))[0].n,1);
}));
