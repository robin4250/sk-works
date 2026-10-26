// Current-core connection only. Synthetic auth surroundings, real current proof SQL.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash,createHmac,randomBytes,randomUUID} from 'node:crypto';
import {createServer} from 'node:http';
import {Readable} from 'node:stream';
import {createSecurityCollectorHandler} from '../../../supabase/functions/security-collector-ingest/handler.mjs';
import {DecoyCollectorProducer} from './sources/decoy_collector_producer.mjs';
const root=new URL('./',import.meta.url),read=p=>readFile(new URL(p,root),'utf8');
const u=new URL(process.env.SKO_COLLECTOR_CURRENT_FIXTURE_URL??'');
if(u.protocol!=='postgresql:'||u.hostname!=='127.0.0.1'||u.pathname!=='/collector_current_fixture'||u.username!=='postgres'||u.password!=='collector-fixture-only'||u.search)throw Error('Disposable fixed loopback fixture only');
const imported=await import(process.argv[2]);const {Client}=imported.default??imported;
const db=new Client({connectionString:u.href});await db.connect();let checks=0;
const eq=(actual,expected,msg)=>{assert.deepEqual(actual,expected,msg);checks++;};
const reject=async(fn,pattern=/collector|reauthentication|permission|denied|post_required/)=>{await assert.rejects(fn,pattern);await db.query('rollback');checks++;};
const actor='10000000-0000-0000-0000-000000000001',other='10000000-0000-0000-0000-000000000002';
const sid='20000000-0000-0000-0000-000000000001',otherSid='20000000-0000-0000-0000-000000000002';
const cid='30000000-0000-0000-0000-000000000001';
const hash=x=>createHash('sha256').update(x).digest('hex');
async function role(name,id=actor,session=sid){await db.query('reset role');await db.query("select set_config('request.jwt.claims',$1,false),set_config('request.method','POST',false)",[JSON.stringify({sub:id,role:name,session_id:session})]);await db.query('set role '+name);}
const currentSources=JSON.parse(await read('sources/current-core-originals.json'));
const originalSignatures=currentSources.map(x=>x.signature);
const routineSnapshot=async()=>{await role('postgres');return (await db.query('select oid::regprocedure::text signature,to_jsonb(p) metadata from pg_proc p where oid=any($1::regprocedure[]) order by oid',[originalSignatures])).rows;};
const surroundings=async()=>{await role('postgres');return (await db.query(`select jsonb_build_object('users',(select jsonb_agg(to_jsonb(t) order by id)from auth.users t),'sessions',(select jsonb_agg(to_jsonb(t)order by id)from auth.sessions t),'members',(select jsonb_agg(to_jsonb(t)order by user_id)from public.company_members t),'payroll',(select jsonb_agg(to_jsonb(t))from public.payroll_statements t),'rollout',(select jsonb_agg(to_jsonb(t)order by scope)from private.reauthentication_rollout t))v`)).rows[0].v;};
const count=async table=>{await role('postgres');return Number((await db.query('select count(*)n from '+table)).rows[0].n);};
const install=await read('install-off.sql.review-only'),undo=await read('restore-unused.sql.review-only');
try{
 eq(Number((await db.query('show server_version_num')).rows[0].server_version_num)>=170000,true,'PostgreSQL17');
 eq((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname not in('pg_catalog','information_schema') and n.nspname not like 'pg_toast%' and c.relkind='r'")).rows[0].n,0,'Empty disposable catalog');
 await db.query(`create role anon nologin;create role authenticated nologin;create role service_role nologin;create schema private;create schema auth;create schema extensions;create extension pgcrypto with schema extensions;
 create function auth.jwt()returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid()returns uuid language sql stable as $$select(auth.jwt()->>'sub')::uuid$$;
 create function auth.role()returns text language sql stable as $$select auth.jwt()->>'role'$$;
 create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz,encrypted_password text);
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table private.master_admins(user_id uuid primary key,enabled boolean);
 create table private.account_deletion_access_restrictions(user_id uuid primary key);
 create function private.account_access_allowed()returns boolean language sql stable security definer set search_path=''as $$select auth.uid() is not null and not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())$$;
 create function private.account_deletion_barrier_key(a uuid)returns bigint language sql immutable as $$select hashtextextended('fixture-delete:'||a::text,0)$$;
 create function public.is_current_user_master_admin()returns boolean language sql stable security definer set search_path=''as $$select exists(select 1 from private.master_admins where user_id=auth.uid() and enabled)$$;
 create table public.user_secondary_credentials(user_id uuid primary key,password_hash text,failed_attempts int,locked_until timestamptz,updated_at timestamptz);
 create table public.payroll_statements(id uuid,payload text);insert into public.payroll_statements values('90000000-0000-0000-0000-000000000001','preserved frozen financial sentinel');
 revoke all on schema private,auth,extensions from public,anon,authenticated,service_role;
 grant usage on schema private,auth to authenticated;grant usage on schema auth to service_role;grant execute on all functions in schema auth to authenticated,service_role;
 `);
 await db.query('insert into auth.users(id)values($1),($2)',[actor,other]);await db.query('insert into auth.sessions values($1,$2,null),($3,$4,null)',[sid,actor,otherSid,other]);
 await db.query('insert into public.company_members values($1,$2,$3),($4,$5,$6)',[cid,actor,'owner',randomUUID(),other,'owner']);
 await db.query('insert into private.master_admins values($1,true)',[actor]);
 let core=await read('sources/reauthentication_proofs.sql');core=core.slice(0,core.indexOf('create function public.replace_secondary_password_with_proof('))+'commit;';await db.query(core);
 await db.query("alter table private.reauthentication_rollout drop constraint reauthentication_rollout_scope_check;alter table private.reauthentication_rollout add constraint reauthentication_rollout_scope_check check(scope in('secondary_password','master_feature','master_security','attendance_management'));insert into private.reauthentication_rollout values('attendance_management',false)");
 // Exact current 05 scope + exact current original issuer/consumer, not old three-scope bootstrap.
 for(const original of currentSources)await db.query(original.definition);
 const originals=await routineSnapshot(),before=await surroundings();
 await db.query(install);eq(await surroundings(),before,'All identities, companies, payroll and four scope rows preserved');
 eq(await count('private.security_collector_keys'),0,'No secret/key seed');
 eq((await db.query("select to_regrole('sko_security_collector_ingest')v")).rows[0].v,null,'No bridge role created');
 await reject(()=>db.query(install),/precondition/);
 await role('postgres');await db.query(undo);eq(await routineSnapshot(),originals,'Unused restore preserves exact original function OIDs and all pg_proc fields');eq(await surroundings(),before,'Unused restore preserves core/business state');
 await db.query(install);await db.query('create view public.unknown_collector_dependency as select event_id from private.security_collector_events');
 await reject(()=>db.query(undo),/depend|cannot drop/);await role('postgres');eq(await count('private.security_collector_events'),0,'Unknown dependency refusal leaves whole installation intact');await db.query('drop view public.unknown_collector_dependency');
 await db.query("create function public.untracked_collector_dependency()returns bigint language plpgsql as $$begin return(select count(*)from private.security_collector_events);end$$");await reject(()=>db.query(undo),/external_runtime_dependency/);await role('postgres');await db.query('drop function public.untracked_collector_dependency()');
 await db.query(undo);eq(await routineSnapshot(),originals,'Dependency refusal and retry restore old core exactly');await db.query(install);
 const key=randomBytes(32),key2=randomBytes(32),event={event_id:randomUUID(),collector_id:cid,occurred_at:new Date().toISOString(),event_kind:'current_lure_touched',generation:1,correlation_key:hash('synthetic repeated source'),key_epoch:new Date().toISOString().slice(0,10)};
 const envelope=(payload=event,secret=key,version=1,stamp=Date.now(),raw=Buffer.from(JSON.stringify(payload)))=>({collector_id:cid,key_version:version,timestamp:stamp,body_base64:raw.toString('base64'),signature:createHmac('sha256',secret).update(`sko-collector-v2\n${cid}\n${version}\n${stamp}\n`).update(raw).digest('hex')});
 const ingest=async e=>{await role('service_role');return(await db.query('select public.ingest_signed_security_collector_event($1)v',[e])).rows[0].v;};
 await reject(()=>ingest(envelope()),/collector_unavailable/);await role('postgres');
 await db.query("insert into private.security_collector_keys values($1,1,$2,true,null,clock_timestamp()-interval '1 minute',clock_timestamp()+interval '1 day')",[cid,key]);
 await db.query('update private.security_collector_control set ingest_enabled=true');
 eq(await ingest(envelope()),event.event_id,'Correct signed owner-bound source persists');eq(await ingest(envelope()),event.event_id,'Identical event retry stays idempotent');eq(await count('private.security_collector_events'),1,'One durable event after retry');eq(await count('private.security_collector_evidence'),1,'One first signed evidence after retry');
 await reject(()=>ingest(envelope({...event,generation:2})),/conflict/);
 await reject(()=>ingest(envelope({...event,event_id:randomUUID()},randomBytes(32))),/collector_unavailable/);
 await reject(()=>ingest({...envelope(),key_version:2}),/collector_unavailable/);
 await reject(()=>ingest(envelope(event,key,1,Date.now()-61000)),/collector_unavailable/);
 await reject(()=>ingest(envelope({...event,event_id:randomUUID(),collector_id:randomUUID()})),/invalid_metadata/);
 await reject(()=>ingest(envelope({...event,event_id:randomUUID(),ip:'forbidden'})),/collector_invalid_metadata/);
 const duplicateRaw=Buffer.from(JSON.stringify(event).replace('"generation":1','"generation":1,"generation":1'));
 await reject(()=>ingest(envelope(event,key,1,Date.now(),duplicateRaw)),/invalid_metadata/);
 for(const name of ['anon','authenticated']){await role(name);await reject(()=>db.query('select public.ingest_signed_security_collector_event($1)',[envelope()]),/permission/);}
 for(const name of ['anon','authenticated','service_role']){await role(name);for(const table of ['private.security_collector_events','private.security_collector_keys','private.security_collector_evidence'])await reject(()=>db.query('select * from '+table),/permission/);}
 await role('postgres');await db.query('update private.security_collector_keys set enabled=false,revoked_at=clock_timestamp() where collector_id=$1',[cid]);await db.query("insert into private.security_collector_keys values($1,2,$2,true,null,clock_timestamp()-interval '1 minute',clock_timestamp()+interval '1 day')",[cid,key2]);
 await reject(()=>ingest(envelope()),/collector_unavailable/);
 eq(await ingest(envelope(event,key2,2)),event.event_id,'Rotated active key may retry same original event without rewriting evidence');
 await role('postgres');eq((await db.query('select key_version from private.security_collector_evidence where event_id=$1',[event.event_id])).rows[0].key_version,1,'Historical key/evidence retained after rotation');
 const committedLostAck={...event,event_id:randomUUID()};await ingest(envelope(committedLostAck,key2,2));eq(await ingest(envelope(committedLostAck,key2,2)),committedLostAck.event_id,'Lost caller ACK retries original committed event');eq(await count('private.security_collector_events'),2,'Unknown ACK causes no duplicate');
 const rolledBack={...event,event_id:randomUUID()};await role('service_role');await db.query('begin');await db.query('select public.ingest_signed_security_collector_event($1)',[envelope(rolledBack,key2,2)]);await db.query('rollback');eq(await count('private.security_collector_events'),2,'Rolled-back transaction retains no event/evidence');eq(await ingest(envelope(rolledBack,key2,2)),rolledBack.event_id,'Pre-commit failure can retry original event');
 // Actual loopback HTTP -> actual handler -> native PG service adapter. No hosted URL/key.
 const rest=new URL(process.env.SKO_COLLECTOR_POSTGREST_FIXTURE_URL??'');if(rest.protocol!=='http:'||rest.hostname!=='127.0.0.1'||rest.pathname!=='/'||rest.search)throw Error('Disposable PostgREST fixture only');
 const jwtSecret='synthetic-collector-http-jwt-secret-at-least-32-characters';const jwtParts=[Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),Buffer.from(JSON.stringify({role:'service_role',exp:Math.floor(Date.now()/1000)+600})).toString('base64url')];const serviceJWT=jwtParts.join('.')+'.'+createHmac('sha256',jwtSecret).update(jwtParts.join('.')).digest('base64url');
 let upstreamCalls=0,loseAck=false;let server;
 try{
  await role('postgres');await db.query("notify pgrst,'reload schema'");let ready=false;for(let i=0;i<100;i++){try{const r=await fetch(new URL('rpc/ingest_signed_security_collector_event',rest),{method:'POST',headers:{apikey:serviceJWT,Authorization:'Bearer '+serviceJWT,'content-type':'application/json'},body:JSON.stringify({p_envelope:{}})});const text=await r.text();if(r.status===400&&text.includes('collector_invalid_envelope')){ready=true;break;}}catch{}await new Promise(resolve=>setTimeout(resolve,100));}eq(ready,true,'Actual PostgREST service JWT authenticates before RPC schema validation');
  const apiOnly=await fetch(new URL('rpc/ingest_signed_security_collector_event',rest),{method:'POST',headers:{apikey:serviceJWT,'content-type':'application/json'},body:JSON.stringify({p_envelope:{}})});eq([401,403].includes(apiOnly.status),true,'Legacy apikey without Bearer is not silently promoted by the PostgreSQL fixture');await apiOnly.arrayBuffer();
  const handler=createSecurityCollectorHandler({baseUrl:'https://fixture.invalid',serviceKey:serviceJWT,keys:[{collector_id:cid,key_version:2,key_hex:key2.toString('hex')}],enabled:()=>true,fetcher:async(url,options)=>{assert.equal(String(url),'https://fixture.invalid/rest/v1/rpc/ingest_signed_security_collector_event');eq(options.headers.Authorization,'Bearer '+serviceJWT,'Handler passes real service JWT to actual PostgREST');upstreamCalls++;const result=await fetch(new URL('rpc/ingest_signed_security_collector_event',rest),options);if(loseAck&&result.status===200){loseAck=false;await result.arrayBuffer();throw Error('fixture lost response after actual PostgREST commit');}return result;}});
  server=createServer(async(req,res)=>{try{const result=await handler(new Request('http://127.0.0.1'+req.url,{method:req.method,headers:req.headers,body:Readable.toWeb(req),duplex:'half'}));res.writeHead(result.status,Object.fromEntries(result.headers));res.end(Buffer.from(await result.arrayBuffer()));}catch{res.writeHead(503);res.end();}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const address=server.address();assert.equal(address.address,'127.0.0.1');
  const http=async(payload,changes={})=>{const e=envelope(payload,key2,2),raw=Buffer.from(e.body_base64,'base64');return fetch(`http://127.0.0.1:${address.port}/functions/v1/security-collector-ingest`,{method:'POST',headers:{'content-type':'application/json','x-sko-collector-id':e.collector_id,'x-sko-collector-key-version':String(e.key_version),'x-sko-collector-time':String(e.timestamp),'x-sko-collector-signature':e.signature,...changes},body:raw});};
  const producerSource=await read('sources/decoy_collector_producer.mjs');eq(createHash('sha1').update(Buffer.concat([Buffer.from('blob '+Buffer.byteLength(producerSource)+'\0'),Buffer.from(producerSource)])).digest('hex'),'8e6251baff86cb70b22b521beb72f5d7f0c665e8','Exact existing PR1435 producer reused without edits');const producer=new DecoyCollectorProducer({collectorId:cid,sessionId:randomUUID(),derivationKey:randomBytes(32)});const built=producer.build({kind:'current_lure_touched',at:Date.now(),generation:1,sequence:1});const httpEvent=built.event;eq(JSON.stringify(httpEvent),built.body,'Existing producer body reaches v2 signing without rewriting');producer.close();const beforeHTTP=await count('private.security_collector_events');eq((await http(httpEvent)).status,204,'Actual loopback HTTP persists through signed handler/native SQL');eq((await http(httpEvent)).status,204,'Actual HTTP retry succeeds');eq(await count('private.security_collector_events'),beforeHTTP+1,'HTTP retry commits one event');
  const writes=upstreamCalls;eq((await http(httpEvent,{'x-sko-collector-signature':'f'.repeat(64)})).status,401,'HTTP forged signature rejected');eq((await http(httpEvent,{'x-sko-collector-key-version':'1'})).status,401,'HTTP retired key rejected');eq(upstreamCalls,writes,'Rejected HTTP never reaches database');
  const unknownAck={...event,event_id:randomUUID()};loseAck=true;eq((await http(unknownAck)).status,503,'Actual HTTP commit with lost ACK remains unavailable');eq((await http(unknownAck)).status,204,'HTTP identical retry resolves lost commit ACK');eq(await count('private.security_collector_events'),beforeHTTP+2,'Lost HTTP ACK creates no duplicate');
 }finally{if(server){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}}
 // Physical key rotation waits for in-flight verified ingress, then denies stale keys.
 const writer=new Client({connectionString:u.href});await writer.connect();
 try{
  await role('postgres');const mainPid=(await db.query('select pg_backend_pid()pid')).rows[0].pid;
  await writer.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({role:'service_role'})]);await writer.query('set role service_role');await writer.query('begin');
  const racingEvent={...event,event_id:randomUUID()};await writer.query('select public.ingest_signed_security_collector_event($1)',[envelope(racingEvent,key2,2)]);
  const rotate=db.query('update private.security_collector_keys set enabled=false,revoked_at=clock_timestamp() where collector_id=$1 and key_version=2',[cid]);let waiting=false;
  for(let i=0;i<80;i++){waiting=(await writer.query("select wait_event_type='Lock'waiting from pg_stat_activity where pid=$1",[mainPid])).rows[0]?.waiting;if(waiting)break;await new Promise(resolve=>setTimeout(resolve,10));}
  eq(waiting,true,'Physical revocation waits behind ingress key SHARE lock');await writer.query('commit');await rotate;
  await reject(()=>ingest(envelope({...event,event_id:randomUUID()},key2,2)),/collector_unavailable/);await role('postgres');eq((await db.query('select count(*)::int n from private.security_collector_events where event_id=$1',[racingEvent.event_id])).rows[0].n,1,'In-flight event commits atomically before revocation');
  await db.query('update private.security_collector_keys set enabled=true,revoked_at=null where collector_id=$1 and key_version=2',[cid]);
 }finally{await writer.query('rollback').catch(()=>{});await writer.end();}
 // A locked source row cannot hold an ingest forever; function-local lock_timeout is real.
 const blocker=new Client({connectionString:u.href});await blocker.connect();
 try{await blocker.query('begin');await blocker.query('select * from private.security_collector_keys where collector_id=$1 and key_version=2 for update',[cid]);const started=Date.now();await reject(()=>ingest(envelope({...event,event_id:randomUUID()},key2,2)),/lock timeout/);eq(Date.now()-started<4000,true,'Ingress lock wait is bounded at one second');}finally{await blocker.query('rollback');await blocker.end();}
 for(let i=0;i<103;i++)await ingest(envelope({...event,event_id:randomUUID()},key2,2));
 const eventCountBeforeRead=await count('private.security_collector_events');
 await role('postgres');await db.query('update private.security_collector_events set generation=2 where event_id=$1',[event.event_id]);
 await role('postgres');await db.query("update private.reauthentication_rollout set enabled=true where scope='master_security';update private.security_collector_control set read_enabled=true");
 const issue=async(id=actor,session=sid,target={scope:'decoy_collector'},operation='master.security_collector.read')=>{const nonce=randomBytes(32).toString('hex');await role('service_role');await db.query('select public.issue_reauthentication_proof($1,$2,$3,$4,$5)',[id,session,operation,target,hash(nonce)]);return nonce;};
 const readEvents=async(nonce,id=actor,session=sid)=>{await role('authenticated',id,session);return(await db.query('select public.master_security_collector_events($1)v',[nonce])).rows[0].v;};
 await reject(()=>issue(actor,sid,{scope:'platform'}),/reauthentication/);await reject(()=>issue(other,otherSid),/reauthentication/);
 const nonce=await issue();await reject(()=>readEvents(nonce,other,otherSid),/unavailable|reauthentication/);const response=await readEvents(nonce);eq(response.events.length,100,'Current Master reads exactly the latest bounded hundred signed observations');eq(response.attack_confirmed,false,'Observation is not labelled confirmed attack');eq(Object.keys(response.events[0]).sort(),['collector_id','correlation_key','event_id','event_kind','generation','key_epoch','occurred_at','received_at','source_provenance'],'No secret/evidence/signing key leaked to UI');await reject(()=>readEvents(nonce),/reauthentication/);await role('postgres');await db.query('update private.security_collector_events set generation=1 where event_id=$1',[event.event_id]);const latestSelected=response.events[0].event_id;
 const methodProof=await issue();await role('authenticated');await db.query("select set_config('request.method','GET',false)");await reject(()=>db.query('select public.master_security_collector_events($1)',[methodProof]),/post_required/);eq((await readEvents(methodProof)).events.length,100,'Refused GET does not consume proof');
 const integrityProof=await issue();await role('postgres');await db.query('update private.security_collector_events set generation=2 where event_id=$1',[latestSelected]);await reject(()=>readEvents(integrityProof),/integrity/);await role('postgres');await db.query('update private.security_collector_events set generation=1 where event_id=$1',[latestSelected]);eq((await readEvents(integrityProof)).events.length,100,'Integrity refusal rolls back audit/proof consumption');
 await role('postgres');const used=await surroundings();await db.query('update private.security_collector_control set ingest_enabled=false,read_enabled=false');await reject(()=>db.query(undo),/used_restore/);eq(await surroundings(),used,'Used restore leaves source/core/business state unchanged');
 await role('postgres');await db.query("update private.security_collector_events set received_at=clock_timestamp()-interval '8 days' where event_id=$1",[event.event_id]);const purge=(await db.query('select private.purge_expired_security_collector_events()v')).rows[0].v;eq(Number(purge.events_removed),1,'Only expired event and its evidence removed');eq(await count('private.security_collector_events'),eventCountBeforeRead-1,'Recent events retained');eq(await count('private.security_collector_retention_audit'),1,'Retention action audited');
 for(const name of ['anon','authenticated','service_role']){await role(name);await reject(()=>db.query('select private.purge_expired_security_collector_events()'),/permission/);}
 await role('postgres');const final=await surroundings();eq(final.users,before.users,'Real IDs/auth surroundings unchanged');eq(final.sessions,before.sessions,'Original sessions unchanged');eq(final.members,before.members,'Company links unchanged');eq(final.payroll,before.payroll,'Financial sentinel unchanged');eq(final.rollout.map(x=>x.scope),before.rollout.map(x=>x.scope),'All four existing scope names preserved');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,loopback_http_native_db:true,actual_postgrest_service_jwt:true,opaque_secret_gateway_verified:false,exact_existing_producer:true,physical_key_rotation_lock:true,bounded_lock_wait:true,bounded_latest_hundred:true,current_four_scope_core:true,bridge_role_created:false,key_seeded_in_install:false,keys_ephemeral_fixture_only:true,signed_raw_byte_ingress:true,rotation_revocation:true,durable_retry_and_commit_ack:true,master_read_proof:true,other_company_nonmaster_denied:true,unused_exact_restore:true,unknown_dependency_rollback:true,used_restore_refused:true,retention_verified:true,synthetic_auth_surroundings:true,real_gotrue:false,production_changed:false}));
}finally{await db.query('rollback').catch(()=>{});await db.end();}
