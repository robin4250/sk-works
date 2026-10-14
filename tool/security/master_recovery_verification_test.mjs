// Isolated PostgreSQL-WASM tests. No production access, real identities or codes.
// Usage: node tool/security/master_recovery_verification_test.mjs [pglite module]
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const native=Boolean(process.env.SKO_RECOVERY_FIXTURE_URL);
let db,Client;
if(native){
  ({Client}=await import(process.argv[2] ?? 'pg'));
  const client=new Client({connectionString:process.env.SKO_RECOVERY_FIXTURE_URL});await client.connect();
  db={exec:sql=>client.query(sql),query:(sql,args)=>client.query(sql,args),close:()=>client.end()};
}else{
  const {PGlite}=await import(process.argv[2] ?? '@electric-sql/pglite');db=new PGlite();
}
const root=new URL('../../',import.meta.url);
const original=readFileSync(new URL('supabase/migrations/20260930112000_add_master_recovery_dual_code_rpc.sql',root),'utf8');
const start=original.indexOf('create or replace function public.verify_master_recovery_code(');
const end=original.indexOf('create or replace function public.consume_master_recovery_challenge(',start);
const fixed=readFileSync(new URL('supabase/migrations/20261014061919_persist_master_recovery_verification_failures.sql',root),'utf8');
const actor='11111111-1111-4111-8111-111111111111', challenge='22222222-2222-4222-8222-222222222222',other='33333333-3333-4333-8333-333333333333';
await db.exec(`create schema private; create schema auth; create schema extensions;
create role anon; create role authenticated; create role service_role;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
create table private.master_admins(user_id uuid primary key, enabled boolean not null);
insert into private.master_admins values('${actor}',true),('${other}',true);
create function public.is_current_user_master_admin() returns boolean language sql stable security definer set search_path='public','private','pg_temp' as $$select exists(select 1 from private.master_admins ma where ma.user_id=auth.uid() and ma.enabled)$$;
-- STRICT mirrors pgcrypto NULL behavior; crypto itself is not under test.
${native?'create extension pgcrypto with schema extensions;':"create function extensions.crypt(code text,salt text) returns text language sql strict as $$select 'fixture:'||code$$;"}
create table private.master_recovery_challenges(id uuid primary key,master_user_id uuid not null,primary_code_hash text not null,secondary_code_hash text not null,primary_verified_at timestamptz,secondary_verified_at timestamptz,created_at timestamptz not null default now(),expires_at timestamptz not null,used_at timestamptz,failed_attempts integer not null default 0,locked_at timestamptz);
create table private.master_admin_audit_log(id bigint generated always as identity primary key,actor_user_id uuid,action text not null,target_user_id uuid,details jsonb not null default '{}',created_at timestamptz not null default now());
alter table private.master_recovery_challenges enable row level security;
alter table private.master_admin_audit_log enable row level security;`);
await db.exec(original.slice(start,end));
await db.exec(`revoke all on function public.verify_master_recovery_code(uuid,text,text) from public,anon; grant execute on function public.verify_master_recovery_code(uuid,text,text) to authenticated,service_role;`);
const hash=code=>native?`extensions.crypt('${code}',extensions.gen_salt('bf',4))`:`'fixture:${code}'`;
const reset=async()=>db.exec(`reset role; set test.actor='${actor}'; truncate private.master_recovery_challenges,private.master_admin_audit_log; insert into private.master_recovery_challenges(id,master_user_id,primary_code_hash,secondary_code_hash,expires_at) values('${challenge}','${actor}',${hash('123456')},${hash('654321')},now()+interval '15 minutes'); set role authenticated;`);
const call=async(channel,code,id=challenge)=>(await db.query('select public.verify_master_recovery_code($1::uuid,$2::text,$3::text) result',[id,channel,code])).rows[0].result;
const state=async()=>{await db.exec('reset role');const row=(await db.query(`select failed_attempts,locked_at is not null locked,primary_verified_at is not null primary_verified,secondary_verified_at is not null secondary_verified,(select count(*)::int from private.master_admin_audit_log where action='master_recovery_code_failed') failed_audits from private.master_recovery_challenges`)).rows[0];await db.exec('set role authenticated');return row;};
const rejects=(work,message)=>assert.rejects(work,e=>e.message.includes(message));
await reset();for(let i=0;i<9;i++)await rejects(call('primary','000000'),'invalid recovery code');
let s=await state();assert.equal(s.failed_attempts,0);assert.equal(s.failed_audits,0);assert.equal(s.locked,false);
assert.equal((await call('primary','123456')).primary_verified,true);
await reset();assert.equal((await call('primary',null)).primary_verified,true);assert.equal((await call('secondary',null)).complete,true);
console.log('PASS original RPC: failure rollback and NULL bypass reproduced');
await db.exec('reset role');const aclBefore=(await db.query(`select proacl::text acl from pg_proc where oid='public.verify_master_recovery_code(uuid,text,text)'::regprocedure`)).rows[0].acl;
await db.exec(fixed);const aclAfter=(await db.query(`select proacl::text acl from pg_proc where oid='public.verify_master_recovery_code(uuid,text,text)'::regprocedure`)).rows[0].acl;assert.equal(aclAfter,aclBefore);
await reset();await db.exec('set role anon');await rejects(call('primary','123456'),'permission denied');
await db.exec("reset role;set test.actor='';set role authenticated");await rejects(call('primary','123456'),'master admin permission required');
await db.exec(`reset role;set test.actor='44444444-4444-4444-8444-444444444444';set role authenticated`);await rejects(call('primary','123456'),'master admin permission required');
await db.exec(`reset role;set test.actor='${other}';set role authenticated`);await rejects(call('primary','123456'),'recovery challenge not found');
await reset();await rejects(call('primary',null),'invalid recovery code');await rejects(call(null,'123456'),'invalid recovery channel');await rejects(call('other','123456'),'invalid recovery channel');await rejects(call('primary','abc'),'invalid recovery code');assert.equal((await state()).primary_verified,false);
await reset();for(let i=0;i<8;i++){const denied=await call(i%2?'secondary':'primary','000000');assert.deepEqual(denied,{primary_verified:false,secondary_verified:false,complete:false,error:'invalid recovery code'});s=await state();assert.equal(s.failed_attempts,i+1);assert.equal(s.failed_audits,i+1);assert.equal(s.locked,i===7);}
await rejects(call('primary','123456'),'recovery challenge locked');await rejects(call('primary','000000'),'recovery challenge locked');assert.equal((await state()).failed_attempts,8);
await reset();assert.deepEqual(await call('primary','123456'),{primary_verified:true,secondary_verified:false,complete:false});assert.equal((await call('secondary','000000')).complete,false);assert.equal((await call('secondary','654321')).complete,true);assert.equal((await call('primary','123456')).complete,true);
for(const [change,message] of [["used_at=now()",'already used'],["expires_at=now()-interval '1 second'",'expired'],['locked_at=now()','locked']]){await reset();await db.exec(`reset role;update private.master_recovery_challenges set ${change};set role authenticated`);await rejects(call('primary','123456'),message);assert.equal((await state()).primary_verified,false);}
await reset();const burst=await Promise.allSettled(Array.from({length:12},()=>call('primary','000000')));assert.equal(burst.filter(x=>x.status==='fulfilled').length,8);assert.equal(burst.filter(x=>x.status==='rejected'&&x.reason.message.includes('locked')).length,4);assert.equal((await state()).failed_attempts,8);
// PGlite serializes queued calls. This verifies a burst, not independent sessions/row-lock races.
console.log('PASS fixed RPC: ACL preservation, anon/auth/master/ownership, NULL/format, audit and eight-attempt lock, shared-channel budget, success/replay/expiry, queued burst');
if(native){
  const sessions=await Promise.all(Array.from({length:12},async()=>{const c=new Client({connectionString:process.env.SKO_RECOVERY_FIXTURE_URL});await c.connect();await c.query(`set test.actor='${actor}';set role authenticated`);return c;}));
  try{
    await reset();
    const calls=await Promise.allSettled(sessions.map(c=>c.query('select public.verify_master_recovery_code($1::uuid,$2::text,$3::text) result',[challenge,'primary','000000'])));
    assert.equal(calls.filter(x=>x.status==='fulfilled'&&x.value.rows[0].result.error==='invalid recovery code').length,8);
    assert.equal(calls.filter(x=>x.status==='rejected'&&x.reason.message.includes('locked')).length,4);
    s=await state();assert.equal(s.failed_attempts,8);assert.equal(s.failed_audits,8);assert.equal(s.locked,true);
    await reset();for(let i=0;i<7;i++)await call('primary','000000');
    const mixed=await Promise.allSettled([sessions[0].query('select public.verify_master_recovery_code($1::uuid,$2::text,$3::text) result',[challenge,'primary','123456']),sessions[1].query('select public.verify_master_recovery_code($1::uuid,$2::text,$3::text) result',[challenge,'secondary','000000'])]);
    assert.equal(mixed[1].status,'fulfilled');assert.equal(mixed[1].value.rows[0].result.error,'invalid recovery code');
    if(mixed[0].status==='fulfilled')assert.equal(mixed[0].value.rows[0].result.primary_verified,true);else assert.match(mixed[0].reason.message,/locked/);
    s=await state();assert.equal(s.failed_attempts,8);assert.equal(s.locked,true);await rejects(call('primary','123456'),'locked');
    console.log('PASS native PostgreSQL pgcrypto: 12 independent sessions share exactly eight attempts; correct/wrong final-attempt race respects lock');
  }finally{await Promise.all(sessions.map(c=>c.end()));}
}else console.log('LIMIT: STRICT crypt stub; independent-session concurrency requires native PostgreSQL');
await db.close();
