// Synthetic root-maintenance boundary only. Never connects to hosted Auth.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import {createHash,randomUUID}from'node:crypto';
const native=!!process.env.SKO_APPLE_ENROLLMENT_NATIVE_URL;
const Runtime=native?(await import('./native_apple_enrollment_native_runtime.mjs')).NativeRuntime:(await import(process.env.SKO_APPLE_ENROLLMENT_PGLITE||'../../../apple-enrollment-sql-runtime/node_modules/@electric-sql/pglite/dist/index.js')).PGlite;
const uid='11111111-1111-4111-8111-111111111111',sid='22222222-2222-4222-8222-222222222222',company='33333333-3333-4333-8333-333333333333';
const hash=s=>createHash('sha256').update(s).digest('hex');
async function fixture(fn){const db=new Runtime();let seq=0;
 try{await db.exec(`do $$declare r text;begin foreach r in array array['anon','authenticated','service_role','supabase_auth_admin']loop if not exists(select 1 from pg_roles where rolname=r)then execute format('create role %I',r);end if;end loop;end$$;
 create schema auth;create schema private;create function auth.jwt()returns jsonb language sql stable as $$select jsonb_build_object('role',concat('service','_role'))$$;
 create table auth.users(id uuid primary key,encrypted_password text,email text,phone text,raw_user_meta_data jsonb,is_anonymous boolean,deleted_at timestamptz,banned_until timestamptz);
 create table auth.sessions(id uuid primary key,user_id uuid references auth.users,not_after timestamptz);
 create table auth.identities(id uuid primary key,user_id uuid references auth.users,provider text,provider_id text,identity_data jsonb);
 create table public.company_members(user_id uuid,company_id uuid,role text);
 create table private.account_deletion_access_restrictions(user_id uuid primary key);`);
 for(const n of ['owner-policy.sql.review-only','google-protection.sql.review-only','native-enrollment.sql.review-only','registered-apple-login.sql.review-only','native-enrollment-recovery.sql.review-only'])await db.exec(fs.readFileSync(new URL(n,import.meta.url),'utf8'));
 await db.query('insert into auth.users(id,encrypted_password,raw_user_meta_data)values($1,$2,$3)',[uid,'synthetic-credential-version','{}']);
 await db.query('insert into auth.sessions(id,user_id)values($1,$2)',[sid,uid]);await db.query('insert into company_members values($1,$2,$3)',[uid,company,'owner']);
 await db.query("insert into auth.identities values(gen_random_uuid(),$1,'google','original-google',jsonb_build_object('sub','original-google'))",[uid]);
 await db.exec('select apple_google_protection.enable_reviewed();insert into apple_native_enrollment_private.rollout values(true,true,true,true);');
 const q=async(s,p=[])=>(await db.query(s,p)).rows;
 const reserve=async()=>{const c=(await q('select public.read_apple_native_enrollment_context($1,$2)c',[uid,sid]))[0].c;delete c.account_allowed;delete c.primary_password_configured;const raw=JSON.stringify(c),token=hash('synthetic-token-'+(++seq));
  return(await q("select public.reserve_apple_native_subject($1,$2,'apple-subject',$3,$4,$5,floor(extract(epoch from clock_timestamp()))::bigint)r",[uid,sid,token,hash(raw),raw]))[0].r;};
 const hold=async r=>q('select public.hold_apple_native_subject($1,$2,$3)',[r.request_id,uid,sid]);
 const reconcile=async(r,command=randomUUID(),session=sid,reason='隔離環境で保存不明の連携状態を照合')=>(await q('select apple_native_enrollment_private.reconcile_request($1,$2,$3,$4)r',[command,r.request_id,session,reason]))[0].r;
 const state=async r=>(await q('select * from apple_native_enrollment_private.requests where request_id=$1',[r.request_id]))[0];
 const identities=async()=>(await q("select jsonb_agg(to_jsonb(i)order by id)j from auth.identities i"))[0].j;
 await fn({db,q,reserve,hold,reconcile,state,identities});
 }finally{await db.close();}}
test('root maintenance API stays inaccessible to anonymous, app and service roles',()=>fixture(async f=>{
 for(const role of ['anon','authenticated','service_role']){
  const p=(await f.q("select has_function_privilege($1,'apple_native_enrollment_private.reconcile_request(uuid,uuid,uuid,text)','EXECUTE')e,has_schema_privilege($1,'apple_native_enrollment_private','USAGE')s",[role]))[0];assert.equal(p.e,false);assert.equal(p.s,false);
  await f.db.exec('set role '+role);await assert.rejects(f.reconcile({request_id:randomUUID()}),/permission denied/);await f.db.exec('reset role');
 }
}));
test('committed-but-held link reconciles same UID only; command retry is idempotent and audit immutable',()=>fixture(async f=>{
 const r=await f.reserve();assert.ok(r);await f.db.query("insert into auth.identities values(gen_random_uuid(),$1,'apple','apple-subject',jsonb_build_object('sub','apple-subject'))",[uid]);await f.hold(r);
 const before=await f.identities(),command=randomUUID(),done=await f.reconcile(r,command);assert.equal(done.status,'completed');assert.equal(done.actor_id,uid);assert.deepEqual(await f.identities(),before);
 assert.deepEqual(await f.reconcile(r,command),done);assert.equal((await f.q('select count(*)::int n from apple_native_enrollment_private.recovery_events'))[0].n,1);
 await assert.rejects(f.reconcile(r,command,sid,'異なる内容で同じ操作番号を使用'),/command_reused/);
 await assert.rejects(f.db.exec('delete from apple_native_enrollment_private.recovery_events'),/append_only/);await assert.rejects(f.db.exec('truncate apple_native_enrollment_private.recovery_events'),/append_only/);
}));
test('uncommitted held link can be released only under active global guard; late write and token reuse fail',()=>fixture(async f=>{
 const r=await f.reserve();await f.hold(r);const before=await f.identities();const done=await f.reconcile(r);assert.equal(done.status,'cancelled');assert.deepEqual(await f.identities(),before);
 assert.equal((await f.q('select count(*)::int n from apple_owner_policy.subject_permits'))[0].n,0);
 await assert.rejects(f.db.query("insert into auth.identities values(gen_random_uuid(),$1,'apple','apple-subject',jsonb_build_object('sub','apple-subject'))",[uid]),/identity verification/);
 assert.equal((await f.state(r)).token_sha256,r.token_sha256);
 const fresh=await f.reserve();assert.ok(fresh);assert.notEqual(fresh.request_id,r.request_id);
 assert.equal((await f.q('select user_id from apple_google_protection.google_subject_owners'))[0].user_id,uid);
}));
test('OFF policy, deleted account, other SID and changed company context retain HOLD and permit',()=>fixture(async f=>{
 const r=await f.reserve();await f.hold(r);
 for(const sql of ['update apple_google_protection.rollout set enabled=false',"update auth.users set deleted_at=now()", "update public.company_members set role='member'"]){
  await f.db.exec('begin');await f.db.exec(sql);const result=await f.reconcile(r);assert.equal(result.reconciled,false);assert.equal((await f.state(r)).status,'held');assert.equal((await f.q('select count(*)::int n from apple_owner_policy.subject_permits'))[0].n,1);await f.db.exec('rollback');
 }
 assert.equal((await f.reconcile(r,randomUUID(),randomUUID())).reconciled,false);assert.equal((await f.state(r)).status,'held');
}));
test('explicit retention redacts only old finished snapshots and preserves HOLD, identities and replay/ownership tombstones',()=>fixture(async f=>{
 const r=await f.reserve();await f.hold(r);await f.reconcile(r);await f.q("update apple_native_enrollment_private.requests set resolved_at=now()-interval '31 days'where request_id=$1",[r.request_id]);
 const before=await f.state(r),ids=await f.identities();const held=randomUUID();await f.q("insert into apple_native_enrollment_private.requests(request_id,actor_id,session_id,subject,token_sha256,snapshot_sha256,snapshot,verified_at,expires_at,status,created_at)values($1,$2,$3,'unresolved',$4,$4,'{\"private_context\":true}',now()-interval '40 days',now()-interval '40 days','held',now()-interval '40 days')",[held,uid,sid,hash('unresolved')]);
 await assert.rejects(f.q('select apple_native_enrollment_private.redact_finished_snapshots($1,10,$2)',[randomUUID(),'保持方針未設定の拒否検証']),/not_configured/);
 const policy=randomUUID(),configured=(await f.q('select apple_native_enrollment_private.configure_retention($1,30,$2)r',[policy,'合成データの保持方針を三十日に設定']))[0].r;assert.equal(configured.snapshot_days,30);
 const command=randomUUID(),redacted=(await f.q('select apple_native_enrollment_private.redact_finished_snapshots($1,10,$2)r',[command,'保持期間を経過した確定済み照合情報を最小化']))[0].r;assert.equal(redacted.redacted_snapshots,1);
 const after=await f.state(r);assert.equal(after.snapshot.redacted,true);assert.equal(after.snapshot_sha256,before.snapshot_sha256);assert.equal(after.token_sha256,before.token_sha256);assert.equal(after.actor_id,before.actor_id);assert.equal(after.subject,before.subject);
 assert.deepEqual((await f.state({request_id:held})).snapshot,{private_context:true});assert.deepEqual(await f.identities(),ids);
 assert.deepEqual((await f.q('select apple_native_enrollment_private.redact_finished_snapshots($1,10,$2)r',[command,'保持期間を経過した確定済み照合情報を最小化']))[0].r,redacted);
}));

test('null maintenance limits fail before unbounded redaction or audit writes',()=>fixture(async f=>{
 for(const [sql,args] of [
  ['select apple_native_enrollment_private.configure_retention($1,$2,$3)',[randomUUID(),null,'境界値の拒否を確認']],
  ['select apple_native_enrollment_private.configure_retention($1,$2,$3)',[randomUUID(),30,null]],
  ['select apple_native_enrollment_private.redact_finished_snapshots($1,$2,$3)',[randomUUID(),null,'境界値の拒否を確認']],
  ['select apple_native_enrollment_private.redact_finished_snapshots($1,$2,$3)',[randomUUID(),10,null]],
 ])await assert.rejects(f.q(sql,args),/retention_arguments/);
 assert.equal((await f.q('select count(*)::int n from apple_native_enrollment_private.recovery_events'))[0].n,0);
 assert.equal((await f.q('select count(*)::int n from apple_native_enrollment_private.retention_policy'))[0].n,0);
}));
test('Native concurrent same-command reconciliation returns one durable outcome',{skip:!native},()=>fixture(async f=>{
 const r=await f.reserve();await f.hold(r);const command=randomUUID(),a=await f.db.peer(),b=await f.db.peer();
 const sql='select apple_native_enrollment_private.reconcile_request($1,$2,$3,$4) r',args=[command,r.request_id,sid,'並行復旧の同じ操作番号を確認'];
 const results=await Promise.all([a.query(sql,args),b.query(sql,args)]);
 assert.deepEqual(results[0].rows[0].r,results[1].rows[0].r);assert.equal(results[0].rows[0].r.status,'cancelled');
 assert.equal((await f.q('select count(*)::int n from apple_native_enrollment_private.recovery_events where command_id=$1',[command]))[0].n,1);
}));
test('Native in-flight identity commit is drained before held-request reconciliation',{skip:!native},()=>fixture(async f=>{
 const r=await f.reserve();await f.hold(r);const writer=await f.db.peer(),observer=await f.db.peer();
 await writer.query('begin');await writer.query("insert into auth.identities values(gen_random_uuid(),$1,'apple','apple-subject',jsonb_build_object('sub','apple-subject'))",[uid]);
 const pid=(await f.db.query('select pg_backend_pid() pid')).rows[0].pid;
 const outcome=f.reconcile(r).then(value=>({value}),error=>({error}));
 try{
  let locked=false;for(let i=0;i<100;i++){const row=(await observer.query('select wait_event_type from pg_stat_activity where pid=$1',[pid])).rows[0];if(row?.wait_event_type==='Lock'){locked=true;break;}await new Promise(resolve=>setTimeout(resolve,20));}
  assert.equal(locked,true,'recovery must drain the actual identity writer');await writer.query('commit');
  const result=await outcome;if(result.error)throw result.error;assert.equal(result.value.status,'completed');
  assert.equal((await f.q("select count(*)::int n from auth.identities where user_id=$1 and provider='apple'and provider_id='apple-subject'",[uid]))[0].n,1);
 }catch(error){await writer.query('rollback');await outcome;throw error;}
}));
