// Disposable synthetic Auth/PG fixtures. Existing enrollment SQL is verbatim.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {createSuccessorDeliveryAckPorts} from './native_successor_delivery_ack_port.mjs';
const native=!!process.env.SKO_APPLE_ENROLLMENT_NATIVE_URL;
const Runtime=native?(await import('./native_apple_enrollment_native_runtime.mjs')).NativeRuntime:
 (await import(process.env.SKO_APPLE_ACK_PGLITE)).PGlite;
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const actor=id(1),original=id(2),successor=id(3),foreign=id(4),unrelated=id(5),company=id(10);
const subject='ack-fixture-apple',tokenHash='a'.repeat(64);
async function fixture(run,{complete=true}={}){
 const db=new Runtime();
 try{
  await db.exec(`do $$declare r text;begin foreach r in array array['anon','authenticated','service_role','supabase_auth_admin'] loop
   if not exists(select 1 from pg_roles where rolname=r) then execute format('create role %I',r);end if;end loop;end$$;
   create schema auth;create schema private;
   create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),nullif(current_setting('test.claims',true),''),'{}')::jsonb$$;
   create table auth.users(id uuid primary key,encrypted_password text,email text,phone text,raw_user_meta_data jsonb default '{}'::jsonb,is_anonymous boolean default false,deleted_at timestamptz,banned_until timestamptz);
   create table auth.sessions(id uuid primary key,user_id uuid references auth.users,not_after timestamptz,created_at timestamptz not null default clock_timestamp());
   create table auth.identities(id uuid primary key,user_id uuid references auth.users,provider text,provider_id text,identity_data jsonb,unique(provider,provider_id));
   create table public.company_members(user_id uuid,company_id uuid,role text,unique(user_id,company_id));
   create table private.account_deletion_access_restrictions(user_id uuid primary key);`);
  for(const path of ['owner-policy.sql.review-only','native-enrollment.sql.review-only','native-enrollment-successor.sql.review-only','native-successor-delivery-ack.sql.review-only'])
   await db.exec(readFileSync(new URL(path,import.meta.url),'utf8'));
  const sql=async(q,p=[]) => (await db.query(q,p)).rows;
  await db.query('insert into auth.users(id,encrypted_password) values($1,$2),($3,$4)',[actor,'synthetic-password-hash',foreign,'other-hash']);
  await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[original,actor]);
  await db.query('insert into public.company_members values($1,$2,$3)',[actor,company,'owner']);
  await db.query("insert into auth.identities values($1,$2,'google','ack-google','{\"sub\":\"ack-google\"}')",[id(11),actor]);
  await db.exec("insert into apple_owner_policy.rollout values(true,true);insert into apple_native_enrollment_private.rollout values(true,true,true,true);update apple_native_enrollment_private.successor_rollout set enabled=true");
  await db.query("select set_config('test.claims',$1,false)",[JSON.stringify({role:'service_role'})]);
  const snapshot=(await sql('select public.read_apple_native_enrollment_context($1,$2) r',[actor,original]))[0].r;
  delete snapshot.account_allowed;delete snapshot.primary_password_configured;
  const raw=JSON.stringify(snapshot),hash=createHash('sha256').update(raw).digest('hex');
  const at=Number((await sql('select floor(extract(epoch from clock_timestamp()))::bigint n'))[0].n);
  const reservation=(await sql('select public.reserve_apple_native_subject($1,$2,$3,$4,$5,$6,$7) r',[actor,original,subject,tokenHash,hash,raw,at]))[0].r;
  assert.ok(reservation);
  await sql('select apple_native_enrollment_private.claim_successor_attempt($1,$2,$3)',[reservation.request_id,actor,original]);
  await db.query("insert into auth.identities values($1,$2,'apple',$3,jsonb_build_object('sub',$3::text))",[id(12),actor,subject]);
  await db.query('insert into auth.sessions(id,user_id) values($1,$2),($3,$2)',[successor,actor,unrelated]);
  if(complete){const result=(await sql('select apple_native_enrollment_private.complete_with_successor($1,$2,$3,$4,$5,$6,$7) r',
   [reservation.request_id,actor,original,successor,subject,tokenHash,hash]))[0].r;assert.equal(result?.linked,true);}
  const setClaims=async({sid=successor,uid=actor,exp=Math.floor(Date.now()/1000)+120,role='service_role'}={},client=db)=>
   client.query("select set_config('test.claims',$1,false)",[JSON.stringify({role,sub:uid,session_id:sid,exp})]);
  await setClaims();
  const status=async(sid=successor,uid=actor,request=reservation.request_id)=>
   (await sql('select apple_native_enrollment_private.successor_delivery_status($1,$2,$3) r',[request,uid,sid]))[0].r;
  const ack=async(sid=successor,uid=actor,request=reservation.request_id)=>
   (await sql('select apple_native_enrollment_private.acknowledge_successor_possession($1,$2,$3) r',[request,uid,sid]))[0].r;
  const enable=()=>db.exec('update apple_native_enrollment_private.delivery_ack_rollout set enabled=true');
  const authState=async()=>{
   const result={};for(const table of ['auth.users','auth.sessions','auth.identities','public.company_members'])
    result[table]=(await sql(`select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]'::jsonb) r from ${table} x`))[0].r;
   return result;
  };
  await run({db,sql,reservation,setClaims,status,ack,enable,authState});
 }finally{await db.close();}
}
const expected=(request,status='server_completed')=>({schema:1,request_id:request,status,retry_allowed:false,application_adoption_confirmed:false});
test('ACK is independently OFF, RLS enabled, and all client/service table/function grants remain denied',()=>fixture(async f=>{
 assert.equal(await f.status(),null);assert.equal(await f.ack(),null);
 for(const role of ['anon','authenticated','service_role']){
  for(const name of ['successor_delivery_status','acknowledge_successor_possession'])
   assert.equal((await f.sql('select has_function_privilege($1,$2,\'EXECUTE\') ok',[role,`apple_native_enrollment_private.${name}(uuid,uuid,uuid)`]))[0].ok,false);
  assert.equal((await f.sql("select has_table_privilege($1,'apple_native_enrollment_private.delivery_possession_acks','SELECT,INSERT,UPDATE,DELETE') ok",[role]))[0].ok,false);
 }
 assert.equal((await f.sql("select bool_and(relrowsecurity) r from pg_class where oid in('apple_native_enrollment_private.delivery_possession_acks'::regclass,'apple_native_enrollment_private.delivery_ack_rollout'::regclass)"))[0].r,true);
 await f.enable();
 for(const q of ['update apple_owner_policy.rollout set enabled=false','update apple_native_enrollment_private.rollout set enabled=false',
  'update apple_native_enrollment_private.successor_rollout set enabled=false']){
  await f.db.exec('begin');await f.db.exec(q);assert.equal(await f.status(),null);assert.equal(await f.ack(),null);await f.db.exec('rollback');
 }
}));
test('only exact live successor records one immutable possession ACK; retry/status do not claim adoption or mutate Auth',()=>fixture(async f=>{
 await f.enable();const before=await f.authState(),r=f.reservation.request_id;
 assert.deepEqual(await f.status(),expected(r));assert.deepEqual(await f.ack(),expected(r,'successor_possession_recorded'));
 const row=(await f.sql('select * from apple_native_enrollment_private.delivery_possession_acks'))[0];
 assert.deepEqual(await f.ack(),expected(r,'successor_possession_recorded'));
 assert.deepEqual((await f.sql('select * from apple_native_enrollment_private.delivery_possession_acks'))[0],row);
 assert.deepEqual(await f.status(),expected(r,'successor_possession_recorded'));assert.deepEqual(await f.authState(),before);
}));
test('original/other/foreign SID, substituted claims/request, expiry and nonservice context cannot infer or ACK a receipt',()=>fixture(async f=>{
 await f.enable();
 for(const sid of [original,unrelated,id(99)]){await f.setClaims({sid});assert.equal(await f.status(sid),null);assert.equal(await f.ack(sid),null);}
 await f.setClaims({uid:foreign});assert.equal(await f.status(successor,foreign),null);assert.equal(await f.ack(successor,foreign),null);
 await f.setClaims({sid:original});assert.equal(await f.status(),null);assert.equal(await f.ack(),null);
 await f.setClaims({exp:1});assert.equal(await f.status(),null);assert.equal(await f.ack(),null);
 await f.setClaims();assert.equal(await f.status(successor,actor,id(99)),null);
 await f.setClaims({role:'authenticated'});await assert.rejects(f.status(),/server_only/);await assert.rejects(f.ack(),/server_only/);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.delivery_possession_acks'))[0].n,0);
}));
test('company/Google/profile/password/account/permit/claim/receipt drift rejects before ACK; saved ACK never bypasses current checks',()=>fixture(async f=>{
 await f.enable();
 const mutations=[
  "update public.company_members set role='worker'", "delete from auth.identities where provider='google'",
  "update auth.users set raw_user_meta_data='{\"changed\":true}' where id='"+actor+"'",
  "update auth.users set encrypted_password='changed' where id='"+actor+"'",
  "update auth.users set is_anonymous=true where id='"+actor+"'",
  "update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id='"+actor+"'",
  "update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='"+successor+"'",
  "delete from auth.sessions where id='"+successor+"'", "delete from apple_owner_policy.subject_permits",
  "delete from apple_native_enrollment_private.successor_attempts",
  "update apple_native_enrollment_private.requests set status='held'",
  "update apple_native_enrollment_private.successor_receipts set successor_session_id='"+unrelated+"'",
 ];
 for(const q of mutations){await f.db.exec('begin');await f.db.exec(q);assert.equal(await f.status(),null,q);assert.equal(await f.ack(),null,q);
  assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.delivery_possession_acks'))[0].n,0);await f.db.exec('rollback');}
 await f.ack();await f.db.exec("update public.company_members set role='worker'");
 assert.equal(await f.status(),null);assert.equal(await f.ack(),null);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.delivery_possession_acks'))[0].n,1);
}));
test('uncompleted external result remains unavailable with no retry permission or synthesized ACK',()=>fixture(async f=>{
 await f.enable();assert.equal(await f.status(),null);assert.equal(await f.ack(),null);
 await f.setClaims({sid:original});assert.equal(await f.status(original),null);assert.equal(await f.ack(original),null);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.successor_attempts'))[0].n,1);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.delivery_possession_acks'))[0].n,0);
},{complete:false}));
test('ACK insert failure rolls back and leaves Auth/receipt/claim untouched',()=>fixture(async f=>{
 await f.enable();const before=await f.authState();
 await f.db.exec("create function apple_native_enrollment_private.fail_ack() returns trigger language plpgsql as $$begin raise exception 'synthetic ACK failure';end$$;create trigger fail_ack before insert on apple_native_enrollment_private.delivery_possession_acks for each row execute function apple_native_enrollment_private.fail_ack()");
 await assert.rejects(f.ack(),/synthetic ACK failure/);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.delivery_possession_acks'))[0].n,0);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.successor_receipts'))[0].n,1);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.successor_attempts'))[0].n,1);
 assert.deepEqual(await f.authState(),before);
}));
test('real SQL adapter recovers a lost post-COMMIT ACK response without reinserting or storing bearer',()=>fixture(async f=>{
 await f.enable();const calls=[],before=await f.authState();let loseCommit=true;
 const config={enabled:true,reviewed:true,pool:{connect:async()=>({query:async(q,p=[])=>{
  calls.push({q,p});const result=await f.db.query(q,p);if(q==='commit'&&loseCommit){loseCommit=false;throw Error('synthetic response lost');}return result;
 },release:()=>{}})},authenticateExactBearer:async()=>({user:{id:actor},claims:{role:'authenticated',sub:actor,session_id:successor,exp:Math.floor(Date.now()/1000)+120}})};
 const input={request_id:f.reservation.request_id,exactBearer:'synthetic-private-successor-bearer'};
 await assert.rejects(createSuccessorDeliveryAckPorts(config).acknowledge(input),/reconciliation_unavailable/);
 const stored=(await f.sql('select * from apple_native_enrollment_private.delivery_possession_acks'))[0];assert.ok(stored);
 const recovery=createSuccessorDeliveryAckPorts(config);
 assert.deepEqual(await recovery.status(input),expected(input.request_id,'successor_possession_recorded'));
 assert.deepEqual(await recovery.acknowledge(input),expected(input.request_id,'successor_possession_recorded'));
 assert.deepEqual((await f.sql('select * from apple_native_enrollment_private.delivery_possession_acks')),[stored]);
 assert.equal(JSON.stringify(calls).includes(input.exactBearer),false);
 assert.equal((await f.sql("select coalesce(current_setting('request.jwt.claims',true),'') v"))[0].v,'');
 assert.deepEqual(await f.authState(),before);
}));
test('Native two-connection ACK race creates one possession row and returns the same outcome',{skip:!native},()=>fixture(async f=>{
 await f.enable();const a=await f.db.peer(),b=await f.db.peer();await f.setClaims({},a);await f.setClaims({},b);
 const q='select apple_native_enrollment_private.acknowledge_successor_possession($1,$2,$3) r',p=[f.reservation.request_id,actor,successor];
 const results=await Promise.all([a.query(q,p),b.query(q,p)]);
 for(const r of results)assert.deepEqual(r.rows[0].r,expected(p[0],'successor_possession_recorded'));
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.delivery_possession_acks'))[0].n,1);
}));
test('Native JWT expiry during an advisory-lock wait cannot record possession',{skip:!native},()=>fixture(async f=>{
 await f.enable();const blocker=await f.db.peer(),waiter=await f.db.peer();
 await blocker.query('begin');await blocker.query("select pg_advisory_xact_lock(hashtextextended('apple-native-subject:'||$1,0))",[subject]);
 const expiry=Number((await f.sql('select floor(extract(epoch from clock_timestamp()))::bigint n'))[0].n)+2;
 await f.setClaims({exp:expiry},waiter);
 const result=waiter.query('select apple_native_enrollment_private.acknowledge_successor_possession($1,$2,$3) r',[f.reservation.request_id,actor,successor]);
 await new Promise(resolve=>setTimeout(resolve,2200));await blocker.query('commit');
 assert.equal((await result).rows[0].r,null);
 assert.equal((await f.sql('select count(*)::int n from apple_native_enrollment_private.delivery_possession_acks'))[0].n,0);
}));
