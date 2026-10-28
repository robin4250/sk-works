// Isolated PGlite SQL only; no production connection or Auth credentials.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const native=!!process.env.SKO_APPLE_ENROLLMENT_NATIVE_URL;
const Runtime=native?(await import('./native_apple_enrollment_native_runtime.mjs')).NativeRuntime:
 (await import(process.env.SKO_APPLE_ENROLLMENT_PGLITE)).PGlite;
const uid='00000000-0000-0000-0000-000000000001',sid='00000000-0000-0000-0000-000000000002';
const other='00000000-0000-0000-0000-000000000003',company='00000000-0000-0000-0000-000000000010';
const subject='verified-subject',token='a'.repeat(64);
async function fixture(fn){
 const db=new Runtime();
 try{
  await db.exec(`do $$declare r text;begin foreach r in array array['anon','authenticated','service_role','supabase_auth_admin'] loop
   if not exists(select 1 from pg_roles where rolname=r) then execute format('create role %I',r);end if;end loop;end$$;
   create schema auth;create schema private;
   create function auth.jwt() returns jsonb language sql stable as $$select coalesce(current_setting('test.claims',true),'{}')::jsonb$$;
   create table auth.users(id uuid primary key,encrypted_password text,email text,phone text,raw_user_meta_data jsonb default '{}'::jsonb,is_anonymous boolean default false,deleted_at timestamptz,banned_until timestamptz);
   create table auth.sessions(id uuid primary key,user_id uuid references auth.users,not_after timestamptz,created_at timestamptz not null default clock_timestamp());
   create table auth.identities(id uuid primary key,user_id uuid references auth.users,provider text,provider_id text,identity_data jsonb,unique(provider,provider_id));
   create table public.company_members(user_id uuid,company_id uuid,role text,unique(user_id,company_id));
   create table private.account_deletion_access_restrictions(user_id uuid primary key);`);
  await db.exec(readFileSync(new URL('./owner-policy.sql.review-only',import.meta.url),'utf8'));
  await db.exec(readFileSync(new URL('./native-enrollment.sql.review-only',import.meta.url),'utf8'));
  await db.query('insert into auth.users(id,encrypted_password) values($1,$2),($3,$4)',[uid,'synthetic-password-hash',other,'other-synthetic-hash']);
  await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[sid,uid]);
  await db.query('insert into public.company_members values($1,$2,$3)',[uid,company,'owner']);
  await db.query("insert into auth.identities values($1,$2,'google','original-google','{\"sub\":\"original-google\"}')",['00000000-0000-0000-0000-000000000011',uid]);
  await db.query("select set_config('test.claims','{\"role\":\"service_role\"}',false)");
  const sql=async(q,p=[]) => (await db.query(q,p)).rows;
  const enable=async()=>db.exec('insert into apple_owner_policy.rollout values(true,true);insert into apple_native_enrollment_private.rollout values(true,true,true,true);');
  const context=async()=> (await sql('select public.read_apple_native_enrollment_context($1,$2) r',[uid,sid]))[0].r;
  const snapshot=async()=>{const c=await context();delete c.account_allowed;delete c.primary_password_configured;return c;};
  const reserve=async(patch={})=>{
   const snap=await snapshot(),raw=JSON.stringify(snap),now=(await sql('select floor(extract(epoch from clock_timestamp()))::bigint n'))[0].n;
   const p={actor:uid,sid,subject,token,hash:createHash('sha256').update(raw).digest('hex'),raw,at:Number(now),...patch};
   return (await sql('select public.reserve_apple_native_subject($1,$2,$3,$4,$5,$6,$7) r',[p.actor,p.sid,p.subject,p.token,p.hash,p.raw,p.at]))[0].r;
  };
  const link=async(s=subject,u=uid)=>db.query("insert into auth.identities values(gen_random_uuid(),$1,'apple',$2,jsonb_build_object('sub',$2::text))",[u,s]);
  const complete=async(r,patch={})=>{
   const row=(await sql('select * from apple_native_enrollment_private.requests where request_id=$1',[r.request_id]))[0];
   const p={request:r.request_id,actor:uid,sid,subject,token,hash:row.snapshot_sha256,...patch};
   return (await sql('select public.complete_apple_native_subject($1,$2,$3,$4,$5,$6) r',[p.request,p.actor,p.sid,p.subject,p.token,p.hash]))[0].r;
  };
  await fn({db,sql,enable,context,snapshot,reserve,link,complete});
 }finally{await db.close();}
}
test('OFF gates and SQL ACL deny anonymous/authenticated/direct service table access',()=>fixture(async f=>{
 assert.equal(await f.context(),null);
 await f.db.exec('insert into apple_owner_policy.rollout values(true,true);insert into apple_native_enrollment_private.rollout values(true,true,true,false)');
 assert.equal(await f.context(),null);
 for(const role of ['anon','authenticated','service_role']){
  const row=(await f.sql("select has_function_privilege($1,'public.reserve_apple_native_subject(uuid,uuid,text,text,text,text,bigint)','EXECUTE') ok,has_schema_privilege($1,'apple_native_enrollment_private','USAGE') access",[role]))[0];
  assert.equal(row.ok,role==='service_role');assert.equal(row.access,false);
 }
 await f.db.exec('set role authenticated');await assert.rejects(f.context(),/permission denied/);
}));
test('a valid atomic reservation creates a same-UID hook permit and stores exact hashed snapshot once',()=>fixture(async f=>{
 await f.enable();const before=await f.context(),r=await f.reserve();
 assert.equal(r.actor_id,uid);assert.equal(r.session_id,sid);assert.equal(r.status,'reserved');
 assert.equal((await f.sql('select expected_user_id u from apple_owner_policy.subject_permits'))[0].u,uid);
 const stored=(await f.sql('select snapshot from apple_native_enrollment_private.requests'))[0].snapshot;
 assert.equal((await f.sql("select expires_at<=verified_at+interval '120 seconds' bounded from apple_native_enrollment_private.requests"))[0].bounded,true);
 delete before.account_allowed;delete before.primary_password_configured;assert.deepEqual(stored,before);
 assert.equal(await f.reserve(),null);assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.events'))[0].n,1);
}));
test('credential, SID, account, membership and Google barriers deny context',()=>fixture(async f=>{
 await f.enable();
 for(const change of ["update auth.users set encrypted_password='' where id='"+uid+"'","update auth.users set is_anonymous=true where id='"+uid+"'","update auth.users set banned_until=now()+interval '1 hour' where id='"+uid+"'","insert into private.account_deletion_access_restrictions values('"+uid+"')","delete from auth.sessions","delete from public.company_members","delete from auth.identities"]){
  await f.db.exec('begin');await f.db.exec(change);assert.equal(await f.context(),null);await f.db.exec('rollback');
 }
}));
test('forged snapshot/hash, stale primary verification or another SID cannot reserve',()=>fixture(async f=>{
 await f.enable();
 for(const patch of [{hash:'b'.repeat(64)},{at:1},{at:9999999999},{sid:other},{raw:'{}',hash:createHash('sha256').update('{}').digest('hex')}])assert.equal(await f.reserve(patch),null);
 assert.equal((await f.sql('select count(*)::int n from apple_owner_policy.subject_permits'))[0].n,0);
}));
test('a foreign pre-existing subject or permit cannot be reassigned',()=>fixture(async f=>{
 await f.enable();await f.link(subject,other);assert.equal(await f.reserve(),null);
 await f.db.query("delete from auth.identities where provider='apple'");await f.db.query('insert into apple_owner_policy.protected_users values($1)',[other]);
 await f.db.query('insert into apple_owner_policy.subject_permits values($1,$2)',[subject,other]);assert.equal(await f.reserve(),null);
 assert.equal((await f.sql('select expected_user_id u from apple_owner_policy.subject_permits'))[0].u,other);
}));
test('completion requires an actual same-UID subject and preserves original session/Google/company',()=>fixture(async f=>{
 await f.enable();const original=await f.context(),r=await f.reserve();assert.equal(await f.complete(r),null);
 await f.link();const result=await f.complete(r);assert.deepEqual(result,{linked:true,request_id:r.request_id,actor_id:uid});
 const after=await f.context();assert.deepEqual(after,{...original,apple_subjects:[subject]});assert.equal(await f.complete(r),null);
 assert.deepEqual((await f.sql('select event from apple_native_enrollment_private.events order by id')).map(r=>r.event),['reserved','completed']);
}));
test('all completion bindings, expiry and role/Google/password changes deny success',()=>fixture(async f=>{
 await f.enable();const r=await f.reserve();await f.link();
 for(const patch of [{actor:other},{sid:other},{subject:'other-subject'},{token:'b'.repeat(64)},{hash:'c'.repeat(64)}])assert.equal(await f.complete(r,patch),null);
 for(const change of ["update apple_native_enrollment_private.requests set expires_at=now()-interval '1 second'","update auth.users set encrypted_password='changed' where id='"+uid+"'","update public.company_members set role='member'","update auth.users set email='changed@example.test' where id='"+uid+"'","update auth.users set raw_user_meta_data='{\"name\":\"changed\"}' where id='"+uid+"'","update auth.identities set provider_id='changed' where provider='google'","delete from auth.sessions"]){
  await f.db.exec('begin');await f.db.exec(change);assert.equal(await f.complete(r),null);await f.db.exec('rollback');
 }
 assert.equal((await f.sql('select status from apple_native_enrollment_private.requests'))[0].status,'reserved');
}));
test('hold retains subject and replay protection instead of pretending to unlink unknown Auth outcomes',()=>fixture(async f=>{
 await f.enable();const r=await f.reserve();await f.link();
 assert.equal((await f.sql('select public.hold_apple_native_subject($1,$2,$3) r',[r.request_id,other,sid]))[0].r,false);
 assert.equal((await f.sql('select public.hold_apple_native_subject($1,$2,$3) r',[r.request_id,uid,sid]))[0].r,true);
 assert.equal(await f.complete(r),null);assert.equal((await f.sql('select count(*)::int n from apple_owner_policy.subject_permits'))[0].n,1);
 assert.equal((await f.sql("select count(*)::int n from auth.identities where provider='apple'"))[0].n,1);
}));
test('audit write failure rolls back the permit, protection and reservation transaction',()=>fixture(async f=>{
 await f.enable();await f.db.exec("create function apple_native_enrollment_private.fail_event() returns trigger language plpgsql as $$begin raise exception 'synthetic audit failure';end$$;create trigger fail_event before insert on apple_native_enrollment_private.events for each row execute function apple_native_enrollment_private.fail_event();");
 await assert.rejects(f.reserve(),/synthetic audit failure/);
 for(const table of ['apple_owner_policy.subject_permits','apple_owner_policy.protected_users','apple_native_enrollment_private.requests'])assert.equal((await f.sql('select count(*)::int n from '+table))[0].n,0);
}));
test('actual service database role can call only the owner-definer RPC boundary',()=>fixture(async f=>{
 await f.enable();await f.db.exec('set role service_role');assert.equal((await f.context()).actor_id,uid);
 const r=await f.reserve();assert.equal(r.status,'reserved');
 await assert.rejects(f.sql('select * from apple_native_enrollment_private.requests'),/permission denied/);
 await f.db.exec('reset role');assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.requests'))[0].n,1);
}));
test('an actor cannot reserve a second subject and completed token hashes remain consumed',()=>fixture(async f=>{
 await f.enable();const r=await f.reserve();assert.equal(await f.reserve({subject:'second-subject',token:'b'.repeat(64)}),null);
 await f.link();assert.equal((await f.complete(r)).linked,true);
 await f.db.exec("delete from auth.identities where provider='apple'");
 assert.equal(await f.reserve({subject:'second-subject'}),null);
 assert.equal((await f.sql('select count(*)::int n from apple_owner_policy.subject_permits'))[0].n,1);
}));
test('completion audit failure rolls back success but never deletes its permit or linked identity',()=>fixture(async f=>{
 await f.enable();const r=await f.reserve();await f.link();
 await f.db.exec("create function apple_native_enrollment_private.fail_completion_event() returns trigger language plpgsql as $$begin if new.event='completed' then raise exception 'synthetic completion audit failure';end if;return new;end$$;create trigger fail_completion_event before insert on apple_native_enrollment_private.events for each row execute function apple_native_enrollment_private.fail_completion_event();");
 await assert.rejects(f.complete(r),/synthetic completion audit failure/);
 assert.equal((await f.sql('select status from apple_native_enrollment_private.requests'))[0].status,'reserved');
 assert.equal((await f.sql('select count(*)::int n from apple_owner_policy.subject_permits'))[0].n,1);
 assert.equal((await f.sql("select count(*)::int n from auth.identities where provider='apple'"))[0].n,1);
}));
test('Native two-connection same-subject reservation admits exactly one complete transaction',{skip:!native},()=>fixture(async f=>{
 await f.enable();const snap=await f.snapshot(),raw=JSON.stringify(snap),hash=createHash('sha256').update(raw).digest('hex');
 const at=Number((await f.sql('select floor(extract(epoch from clock_timestamp()))::bigint n'))[0].n);
 const peer=await f.db.peer();await peer.query("select set_config('test.claims','{\"role\":\"service_role\"}',false)");
 const sql='select public.reserve_apple_native_subject($1,$2,$3,$4,$5,$6,$7) r',params=[uid,sid,subject,token,hash,raw,at];
 const result=await Promise.all([f.db.query(sql,params),peer.query(sql,params)]);
 assert.equal(result.filter(r=>r.rows[0].r?.status==='reserved').length,1);
 assert.equal(result.filter(r=>r.rows[0].r===null).length,1);
 for(const table of ['apple_owner_policy.subject_permits','apple_native_enrollment_private.requests','apple_native_enrollment_private.events'])assert.equal((await f.sql('select count(*)::int n from '+table))[0].n,1);
}));

test('Native concurrent different accounts cannot claim the same Apple subject',{skip:!native},()=>fixture(async f=>{
 await f.enable();
 const otherSid='00000000-0000-0000-0000-000000000004',otherCompany='00000000-0000-0000-0000-000000000020';
 await f.db.query('insert into auth.sessions(id,user_id) values($1,$2)',[otherSid,other]);
 await f.db.query('insert into public.company_members values($1,$2,$3)',[other,otherCompany,'owner']);
 await f.db.query("insert into auth.identities values($1,$2,'google','other-google',jsonb_build_object('sub','other-google'))",['00000000-0000-0000-0000-000000000012',other]);
 const before=(await f.sql("select jsonb_agg(to_jsonb(c) order by user_id) data from public.company_members c"))[0].data;
 const params=async(actor,session,hashToken)=>{
  const c=(await f.sql('select public.read_apple_native_enrollment_context($1,$2) r',[actor,session]))[0].r;
  assert.ok(c);delete c.account_allowed;delete c.primary_password_configured;
  const raw=JSON.stringify(c), hash=createHash('sha256').update(raw).digest('hex');
  const at=Number((await f.sql('select floor(extract(epoch from clock_timestamp()))::bigint n'))[0].n);
  return [actor,session,subject,hashToken,hash,raw,at];
 };
 const a=await params(uid,sid,token),b=await params(other,otherSid,'b'.repeat(64));
 const peer=await f.db.peer();await peer.query("select set_config('test.claims',$1,false)",[JSON.stringify({role:'service_role'})]);
 const q='select public.reserve_apple_native_subject($1,$2,$3,$4,$5,$6,$7) r';
 const results=await Promise.all([f.db.query(q,a),peer.query(q,b)]);
 const winners=results.map(r=>r.rows[0].r).filter(Boolean);
 assert.equal(winners.length,1);assert.ok([uid,other].includes(winners[0].actor_id));
 const permits=await f.sql('select expected_user_id from apple_owner_policy.subject_permits where apple_subject=$1',[subject]);
 assert.equal(permits.length,1);assert.equal(permits[0].expected_user_id,winners[0].actor_id);
 assert.deepEqual((await f.sql('select jsonb_agg(to_jsonb(c) order by user_id) data from public.company_members c'))[0].data,before);
 assert.equal((await f.sql("select count(*)::int n from auth.identities where provider='google'"))[0].n,2);
 assert.equal((await f.sql("select count(*)::int n from auth.identities where provider='apple'"))[0].n,0);
}));

const successorSid='00000000-0000-0000-0000-000000000090';
async function successorFixture(run){return fixture(async f=>{
 await f.enable();await f.db.exec(readFileSync(new URL('./native-enrollment-successor.sql.review-only',import.meta.url),'utf8'));
 const reservation=await f.reserve();
 const row=(await f.sql('select * from apple_native_enrollment_private.requests where request_id=$1',[reservation.request_id]))[0];
 await f.db.exec('update apple_native_enrollment_private.successor_rollout set enabled=true');
 await f.sql('select apple_native_enrollment_private.claim_successor_attempt($1,$2,$3)',[reservation.request_id,uid,sid]);
 await f.db.exec('update apple_native_enrollment_private.successor_rollout set enabled=false');
 await f.link();await f.db.query('insert into auth.sessions(id,user_id) values($1,$2)',[successorSid,uid]);
 const finish=async(patch={})=>{
  const p={request:reservation.request_id,actor:uid,original:sid,successor:successorSid,subject,token,hash:row.snapshot_sha256,...patch};
  return (await f.sql('select apple_native_enrollment_private.complete_with_successor($1,$2,$3,$4,$5,$6,$7) r',[p.request,p.actor,p.original,p.successor,p.subject,p.token,p.hash]))[0].r;
 };
 await run({...f,reservation,finish});
});}
test('successor completion stays OFF and is not executable by service or clients',()=>successorFixture(async f=>{
 assert.equal(await f.finish(),null);
 for(const role of ['anon','authenticated','service_role']){
  assert.equal((await f.sql("select has_function_privilege($1,'apple_native_enrollment_private.complete_with_successor(uuid,uuid,uuid,uuid,text,text,text)','EXECUTE') ok",[role]))[0].ok,false);
 }
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.successor_receipts'))[0].n,0);
}));
test('same-UID fresh successor completes once without requiring original refresh or rewriting its SID',()=>successorFixture(async f=>{
 await f.db.exec('update apple_native_enrollment_private.successor_rollout set enabled=true');
 await f.db.query('delete from auth.sessions where id=$1',[sid]);
 const result=await f.finish();assert.equal(result.linked,true);assert.equal(result.actor_id,uid);assert.equal(result.session_id,successorSid);
 const row=(await f.sql('select * from apple_native_enrollment_private.successor_receipts'))[0];
 assert.equal(row.original_session_id,sid);assert.equal(row.successor_session_id,successorSid);
 assert.equal((await f.sql('select session_id from apple_native_enrollment_private.requests'))[0].session_id,sid);
 assert.equal(await f.finish(),null);
 assert.equal((await f.sql("select count(*)::int n from auth.identities where user_id=$1 and provider='google'",[uid]))[0].n,1);
 assert.equal((await f.sql('select company_id from public.company_members where user_id=$1',[uid]))[0].company_id,company);
}));
test('successor rejects substitution, stale identity/account evidence and expiry before any receipt',()=>successorFixture(async f=>{
 await f.db.exec('update apple_native_enrollment_private.successor_rollout set enabled=true');
 for(const patch of [{actor:other},{original:other},{successor:sid},{successor:other},{subject:'other-subject'},{token:'b'.repeat(64)},{hash:'c'.repeat(64)}])assert.equal(await f.finish(patch),null);
 await f.db.exec('begin');
 for(const sql of [
  "update auth.sessions set created_at=clock_timestamp()-interval '1 hour' where id='"+successorSid+"'",
  "update auth.sessions set created_at=clock_timestamp()+interval '1 hour' where id='"+successorSid+"'",
  "update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='"+successorSid+"'",
  "update auth.users set encrypted_password='changed' where id='"+uid+"'",
  "update auth.users set raw_user_meta_data='{\"changed\":true}' where id='"+uid+"'",
  "update public.company_members set role='worker' where user_id='"+uid+"'",
  "delete from auth.identities where provider='google'",
  "delete from apple_owner_policy.subject_permits",
  "update apple_native_enrollment_private.requests set expires_at=clock_timestamp()-interval '1 second'",
 ]){
  await f.db.exec('savepoint rejected_successor');await f.db.exec(sql);assert.equal(await f.finish(),null,sql);
  assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.successor_receipts'))[0].n,0);
  await f.db.exec('rollback to rejected_successor;release rejected_successor');
 }
 await f.db.exec('commit');
 assert.equal((await f.finish()).linked,true);
}));

test('durable successor claim is OFF, exact-bound and cannot be consumed twice',()=>fixture(async f=>{
 await f.enable();await f.db.exec(readFileSync(new URL('./native-enrollment-successor.sql.review-only',import.meta.url),'utf8'));
 const r=await f.reserve();const claim=(actor=uid,session=sid)=>f.sql('select apple_native_enrollment_private.claim_successor_attempt($1,$2,$3) r',[r.request_id,actor,session]).then(x=>x[0].r);
 assert.equal(await claim(),null);
 await f.db.exec('update apple_native_enrollment_private.successor_rollout set enabled=true');
 assert.equal(await claim(other),null);assert.equal(await claim(uid,other),null);
 assert.equal((await claim()).request_id,r.request_id);assert.equal(await claim(),null);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.successor_attempts'))[0].n,1);
 for(const role of ['anon','authenticated','service_role'])assert.equal((await f.sql("select has_function_privilege($1,'apple_native_enrollment_private.claim_successor_attempt(uuid,uuid,uuid)','EXECUTE') ok",[role]))[0].ok,false);
}));
test('successor completion without a durable pre-link claim is denied',()=>successorFixture(async f=>{
 await f.db.exec('update apple_native_enrollment_private.successor_rollout set enabled=true');
 await f.db.exec('delete from apple_native_enrollment_private.successor_attempts');
 assert.equal(await f.finish(),null);
}));

test('Native concurrent successor claim admits only one durable attempt',{skip:!native},()=>fixture(async f=>{
 await f.enable();await f.db.exec(readFileSync(new URL('./native-enrollment-successor.sql.review-only',import.meta.url),'utf8'));
 await f.db.exec('update apple_native_enrollment_private.successor_rollout set enabled=true');const r=await f.reserve();
 const a=await f.db.peer(),b=await f.db.peer();
 for(const c of [a,b])await c.query("select set_config('test.claims','{\"role\":\"service_role\"}',false)");
 const q='select apple_native_enrollment_private.claim_successor_attempt($1,$2,$3) r';
 const results=await Promise.all([a.query(q,[r.request_id,uid,sid]),b.query(q,[r.request_id,uid,sid])]);
 assert.equal(results.filter(x=>x.rows[0].r!==null).length,1);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.successor_attempts'))[0].n,1);
}));

const passwordSid='00000000-0000-0000-0000-000000000091';
async function passwordSuccessorFixture(run){return fixture(async f=>{
 await f.enable();
 await f.db.exec(readFileSync(new URL('./native-enrollment-successor.sql.review-only',import.meta.url),'utf8'));
 await f.db.exec(`create table auth.mfa_amr_claims(session_id uuid,authentication_method text,created_at timestamptz default clock_timestamp(),unique(session_id,authentication_method));`);
 await f.db.exec(readFileSync(new URL('./native-enrollment-password-successor.sql.review-only',import.meta.url),'utf8'));
 const begin=()=>f.sql('select apple_native_enrollment_private.begin_password_successor($1,$2,$3,$4) r',[uid,sid,subject,token]).then(r=>r[0].r);
 const issuePassword=async()=>{await f.db.query('insert into auth.sessions(id,user_id) values($1,$2)',[passwordSid,uid]);
  await f.db.query("insert into auth.mfa_amr_claims(session_id,authentication_method) values($1,'password')",[passwordSid]);};
 const reserve=(intent,patch={})=>{const p={id:intent.intent_id,actor:uid,original:sid,password:passwordSid,...patch};return f.sql('select apple_native_enrollment_private.reserve_password_successor($1,$2,$3,$4) r',[p.id,p.actor,p.original,p.password]).then(r=>r[0].r);};
 await run({...f,begin,issuePassword,reserve});
});}
test('PW successor reservation is OFF, internal only and snapshots original before authentication',()=>passwordSuccessorFixture(async f=>{
 assert.equal(await f.begin(),null);
 await f.db.exec('update apple_native_enrollment_private.successor_rollout set enabled=true');
 const intent=await f.begin();assert.equal(intent.actor_id,uid);assert.equal(intent.original_session_id,sid);
 assert.equal(await f.begin(),null);
 assert.equal((await f.sql('select count(*)::int n from apple_owner_policy.subject_permits'))[0].n,0);
 for(const role of ['anon','authenticated','service_role']){
  assert.equal((await f.sql("select has_function_privilege($1,'apple_native_enrollment_private.begin_password_successor(uuid,uuid,text,text)','EXECUTE') ok",[role]))[0].ok,false);
  assert.equal((await f.sql("select has_function_privilege($1,'apple_native_enrollment_private.reserve_password_successor(uuid,uuid,uuid,uuid)','EXECUTE') ok",[role]))[0].ok,false);
 }
}));
test('PW successor atomically reserves same snapshot and traces original SID even after original session deletion',()=>passwordSuccessorFixture(async f=>{
 await f.db.exec('update apple_native_enrollment_private.successor_rollout set enabled=true');
 const intent=await f.begin();await f.issuePassword();
 await f.db.query('delete from auth.sessions where id=$1',[sid]);
 const r=await f.reserve(intent);assert.equal(r.actor_id,uid);assert.equal(r.session_id,passwordSid);assert.equal(r.original_session_id,sid);
 const saved=(await f.sql('select * from apple_native_enrollment_private.password_successor_intents'))[0];
 assert.equal(saved.request_id,r.request_id);assert.equal(saved.original_session_id,sid);assert.equal(saved.password_session_id,passwordSid);
 const request=(await f.sql('select snapshot from apple_native_enrollment_private.requests'))[0].snapshot;
 assert.equal(request.session_id,passwordSid);assert.equal(request.google_identities[0].provider_id,'original-google');assert.equal(request.memberships[0].company_id,company);
 assert.equal(await f.reserve(intent),null);
 await f.sql('select apple_native_enrollment_private.claim_successor_attempt($1,$2,$3)',[r.request_id,uid,passwordSid]);
 await f.link();await f.db.query('insert into auth.sessions(id,user_id) values($1,$2)',[successorSid,uid]);
 const hash=(await f.sql('select snapshot_sha256 from apple_native_enrollment_private.requests'))[0].snapshot_sha256;
 const completed=(await f.sql('select apple_native_enrollment_private.complete_with_successor($1,$2,$3,$4,$5,$6,$7) r',[r.request_id,uid,passwordSid,successorSid,subject,token,hash]))[0].r;
 assert.equal(completed.linked,true);assert.equal(completed.actor_id,uid);assert.equal(completed.session_id,successorSid);
 assert.equal((await f.sql('select original_session_id from apple_native_enrollment_private.password_successor_intents'))[0].original_session_id,sid);
}));
test('PW successor rejects foreign/old/non-password sessions and changed company/Google/password/profile before reserving',()=>passwordSuccessorFixture(async f=>{
 await f.db.exec('update apple_native_enrollment_private.successor_rollout set enabled=true');
 const intent=await f.begin();await f.issuePassword();
 for(const patch of [{actor:other},{original:other},{password:sid},{password:other}])assert.equal(await f.reserve(intent,patch),null);
 for(const change of [
  "delete from auth.mfa_amr_claims",
  "update auth.mfa_amr_claims set authentication_method='oauth'",
  "update auth.sessions set created_at=clock_timestamp()-interval '1 hour' where id='"+passwordSid+"'",
  "update auth.mfa_amr_claims set created_at=clock_timestamp()-interval '1 hour'",
  "update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='"+passwordSid+"'",
  "update public.company_members set role='member'",
  "update auth.identities set provider_id='changed' where provider='google'",
  "update auth.users set encrypted_password='changed' where id='"+uid+"'",
  "update auth.users set email='changed@example.invalid' where id='"+uid+"'",
  "update apple_native_enrollment_private.password_successor_intents set expires_at=clock_timestamp()-interval '1 second'"
 ]){await f.db.exec('begin');await f.db.exec(change);assert.equal(await f.reserve(intent),null,change);
  assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.requests'))[0].n,0);
  await f.db.exec('rollback');}
 assert.equal((await f.sql('select count(*)::int n from apple_owner_policy.subject_permits'))[0].n,0);
}));
test('PW reservation audit failure rolls back permit and transfer without erasing original trace',()=>passwordSuccessorFixture(async f=>{
 await f.db.exec('update apple_native_enrollment_private.successor_rollout set enabled=true');
 const intent=await f.begin();await f.issuePassword();
 await f.db.exec("create function public.reject_pw_audit() returns trigger language plpgsql as $$begin raise exception 'fixture-audit-failure';end$$;create trigger reject_pw_audit before insert on apple_native_enrollment_private.events for each row execute function public.reject_pw_audit()");
 await assert.rejects(f.reserve(intent),/fixture-audit-failure/);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.requests'))[0].n,0);
 assert.equal((await f.sql('select count(*)::int n from apple_owner_policy.subject_permits'))[0].n,0);
 const trace=(await f.sql('select original_session_id,request_id from apple_native_enrollment_private.password_successor_intents'))[0];
 assert.equal(trace.original_session_id,sid);assert.equal(trace.request_id,null);
}));
test('Native PW successor reservation admits one request and trace under concurrent calls',{skip:!native},()=>passwordSuccessorFixture(async f=>{
 await f.db.exec('update apple_native_enrollment_private.successor_rollout set enabled=true');
 const intent=await f.begin();await f.issuePassword();const a=await f.db.peer(),b=await f.db.peer();
 for(const peer of [a,b])await peer.query("select set_config('test.claims','{\"role\":\"service_role\"}',false)");
 const sql='select apple_native_enrollment_private.reserve_password_successor($1,$2,$3,$4) r',args=[intent.intent_id,uid,sid,passwordSid];
 const results=await Promise.all([a.query(sql,args),b.query(sql,args)]);
 assert.equal(results.filter(x=>x.rows[0].r!==null).length,1);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.requests'))[0].n,1);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.password_successor_intents where request_id is not null'))[0].n,1);
}));

