// Synthetic disposable PG17 only; real Collector function bodies and pgcrypto.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash,createHmac,randomBytes,randomUUID} from 'node:crypto';
import {pathToFileURL} from 'node:url';
const u=new URL(process.env.SKO_NOTICE_PG_FIXTURE_URL??'');
if(u.protocol!=='postgresql:'||u.hostname!=='127.0.0.1'||u.pathname!=='/security_notice_fixture'||u.username!=='postgres'||u.password!=='notice-fixture-only'||u.search)throw Error('Disposable loopback fixture only');
const pg=await import(pathToFileURL(process.argv[2]).href),{Client}=pg.default??pg;
const connect=async()=>{const c=new Client({connectionString:u.href});await c.connect();return c;};
const db=await connect(),a=await connect(),b=await connect();
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
const actor='10000000-0000-0000-0000-000000000001',other='10000000-0000-0000-0000-000000000002',sid='20000000-0000-0000-0000-000000000001',cid='30000000-0000-0000-0000-000000000001', collector='30000000-0000-0000-0000-000000000002';
const claims=async(c,role,user=actor,session=sid)=>c.query("select set_config('request.jwt.claims',$1,false),set_config('request.method','POST',false)",[JSON.stringify({sub:user,role,session_id:session})]);
const sha=x=>createHash('sha256').update(x).digest('hex');
const eq=(x,y,label)=>assert.deepEqual(x,y,label);
try{
 eq(Number((await db.query('show server_version_num')).rows[0].server_version_num)>=170000,true,'PG17');
 eq((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname not in('pg_catalog','information_schema') and n.nspname not like 'pg_toast%' and c.relkind='r'")).rows[0].n,0,'empty disposable database');
 await db.query(`create role anon nologin;create role authenticated nologin;create role service_role nologin bypassrls;create schema private;create schema auth;create schema extensions;create extension pgcrypto with schema extensions;
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
 revoke all on schema private,auth,extensions from public,anon,authenticated,service_role;
 grant usage on schema private,auth to authenticated,service_role;grant execute on all functions in schema auth to authenticated,service_role;`);
 await db.query('insert into auth.users(id)values($1),($2)',[actor,other]);await db.query('insert into auth.sessions values($1,$2,null)',[sid,actor]);
 await db.query('insert into public.company_members values($1,$2,$3)',[cid,actor,'owner']);await db.query('insert into private.master_admins values($1,true)',[actor]);
 const root='../../../docs/review/collector-current-core-20261026/';
 let core=await read(root+'sources/reauthentication_proofs.sql');core=core.slice(0,core.indexOf('create function public.replace_secondary_password_with_proof('))+'commit;';await db.query(core);
 await db.query("alter table private.reauthentication_rollout drop constraint reauthentication_rollout_scope_check;alter table private.reauthentication_rollout add constraint reauthentication_rollout_scope_check check(scope in('secondary_password','master_feature','master_security','attendance_management'));insert into private.reauthentication_rollout values('attendance_management',false)");
 const originals=JSON.parse(await read(root+'sources/current-core-originals.json'));for(const item of originals)await db.query(item.definition);
 await db.query(await read(root+'install-off.sql.review-only'));
 await db.query(await read('./install.sql.review-only'));
 const key=randomBytes(32);await db.query("insert into private.security_collector_keys values($1,1,$2,true,null,clock_timestamp()-interval '1 minute',clock_timestamp()+interval '1 day')",[collector,key]);
 await db.query('update private.security_collector_control set ingest_enabled=true,read_enabled=true');
 await db.query('update private.reauthentication_rollout set enabled=true where scope=$1',['master_security']);
 await db.query('update security_observation_notice_private.config set enabled=true,collector_id=$1,company_id=$2,master_id=$3',[collector,cid,actor]);
 const event={event_id:randomUUID(),collector_id:collector,occurred_at:new Date().toISOString(),event_kind:'current_lure_touched',generation:1,correlation_key:sha('synthetic only'),key_epoch:new Date().toISOString().slice(0,10)};
 const envelope=(e,secret=key)=>{const raw=Buffer.from(JSON.stringify(e)),stamp=Date.now();return {collector_id:collector,key_version:1,timestamp:stamp,body_base64:raw.toString('base64'),signature:createHmac('sha256',secret).update(`sko-collector-v2\n${collector}\n1\n${stamp}\n`).update(raw).digest('hex')};};
 const count=async(name)=>(await db.query(`select count(*)::int n from security_observation_notice_private.${name}`)).rows[0].n;
 await claims(a,'service_role');await claims(b,'service_role');
 const signed=envelope(event);const jobs=await Promise.all([a.query('select public.ingest_signed_security_collector_event($1)v',[signed]),b.query('select public.ingest_signed_security_collector_event($1)v',[signed])]);eq(jobs.map(x=>x.rows[0].v),[event.event_id,event.event_id],'simultaneous signed retries');eq(await count('outbox'),1,'one outbox');eq(await count('audit'),1,'one queue audit');
 const bad={...event,event_id:randomUUID()};await assert.rejects(a.query('select public.ingest_signed_security_collector_event($1)',[envelope(bad,randomBytes(32))]));eq(await count('outbox'),1,'bad MAC no notice');
 const lost={...event,event_id:randomUUID()};await a.query('begin');await a.query('select public.ingest_signed_security_collector_event($1)',[envelope(lost)]);await a.query('rollback');eq(await count('outbox'),1,'rollback leaves no notice');
 await a.query('set role service_role');await b.query('set role service_role');
 const notices=await Promise.all([a.query('select public.publish_security_observation_notice($1)v',[event.event_id]),b.query('select public.publish_security_observation_notice($1)v',[event.event_id])]);
 await a.query('reset role');await b.query('reset role');eq(notices.map(x=>x.rows[0].v),['available','available'],'concurrent publish idempotent');eq(await count('inbox'),1,'one inbox');eq(await count('audit'),2,'one publish audit');
 // Existing seven-day purge must wait for concurrent evidence insertion, then
 // see its outbox pin and preserve the source and key.
 const retained={...event,event_id:randomUUID()};await a.query('begin');await a.query('select public.ingest_signed_security_collector_event($1)',[envelope(retained)]);
 await a.query("update private.security_collector_events set received_at=clock_timestamp()-interval '8 days' where event_id=$1",[retained.event_id]);
 const purgePid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const waitingPurge=b.query('select private.purge_expired_security_collector_events()');let purgeWait=false;
 for(let i=0;i<100;i++){const x=await db.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1",[purgePid]);if(x.rows[0]?.waiting){purgeWait=true;break;}await new Promise(r=>setTimeout(r,10));}
 eq(purgeWait,true,'retention waits for in-flight signed evidence');await a.query('commit');await waitingPurge;
 eq((await db.query('select count(*)::int n from private.security_collector_evidence where event_id=$1',[retained.event_id])).rows[0].n,1,'concurrent retention preserves pinned evidence');
 eq((await db.query('select count(*)::int n from private.security_collector_keys where collector_id=$1',[collector])).rows[0].n,1,'key remains with pinned evidence');
 // A genuinely unreferenced event still follows the existing seven-day rule.
 await db.query('update security_observation_notice_private.config set enabled=false');
 const legacy={...event,event_id:randomUUID()};await a.query('select public.ingest_signed_security_collector_event($1)',[envelope(legacy)]);
 await db.query("update private.security_collector_events set received_at=clock_timestamp()-interval '8 days' where event_id=$1",[legacy.event_id]);
 await db.query('select private.purge_expired_security_collector_events()');
 eq((await db.query('select count(*)::int n from private.security_collector_events where event_id=$1',[legacy.event_id])).rows[0].n,0,'unreferenced expired event retains existing purge');
 await db.query('update security_observation_notice_private.config set enabled=true');
 // A role revocation committed before publication prevents delivery. The
 // current Master row is locked through the enqueue transaction.
 const race={...event,event_id:randomUUID()};await a.query('select public.ingest_signed_security_collector_event($1)',[envelope(race)]);
 await a.query('begin');await a.query('update private.master_admins set enabled=false where user_id=$1',[actor]);
 const pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const waitingPublish=b.query('select security_observation_notice_private.publish($1)v',[race.event_id]);let waiting=false;
 for(let i=0;i<100;i++){const x=await db.query("select wait_event_type='Lock' as waiting from pg_stat_activity where pid=$1",[pid]);if(x.rows[0]?.waiting){waiting=true;break;}await new Promise(r=>setTimeout(r,10));}
 eq(waiting,true,'publish waits for concurrent Master revocation');await a.query('commit');
 eq((await waitingPublish).rows[0].v,'held_binding','revoked Master cannot receive queued event');eq(await count('inbox'),1,'revocation did not add inbox item');
 await db.query('update private.master_admins set enabled=true where user_id=$1',[actor]);
 const proof=randomBytes(32).toString('hex');await claims(db,'service_role');await db.query('select public.issue_reauthentication_proof($1,$2,$3,$4,$5)',[actor,sid,'master.security_collector.read',{scope:'decoy_collector'},sha(proof)]);
 // Two independently issued, valid one-use proofs race to update the same
 // record. Revision CAS accepts only one and rolls back the rejected command.
 const proofA=randomBytes(32).toString('hex'),proofB=randomBytes(32).toString('hex');
 await db.query('select public.issue_reauthentication_proof($1,$2,$3,$4,$5)',[actor,sid,'master.security_collector.read',{scope:'decoy_collector'},sha(proofA)]);
 await db.query('select public.issue_reauthentication_proof($1,$2,$3,$4,$5)',[actor,sid,'master.security_collector.read',{scope:'decoy_collector'},sha(proofB)]);
 await claims(a,'authenticated');await claims(b,'authenticated');
 const c1=randomUUID(),c2=randomUUID();const raceCommands=await Promise.allSettled([
  a.query('select public.update_security_observation_notice($1,$2,$3,$4,$5,$6)v',[event.event_id,'resolved','reviewed fixture',1,c1,proofA]),
  b.query('select public.update_security_observation_notice($1,$2,$3,$4,$5,$6)v',[event.event_id,'investigating','reviewed fixture',1,c2,proofB])]);
 eq(raceCommands.filter(x=>x.status==='fulfilled').length,1,'concurrent CAS allows exactly one action');
 eq((await db.query('select count(*)::int n from security_observation_notice_private.audit where command_id is not null')).rows[0].n,1,'one durable review action');
 await claims(db,'authenticated');await db.query('set role authenticated');await db.query("select set_config('request.method','GET',false)");await assert.rejects(db.query('select public.read_security_observation_notices($1)',[proof]));await db.query("select set_config('request.method','POST',false)");
 const result=(await db.query('select public.read_security_observation_notices($1)v',[proof])).rows[0].v;eq(result.events.length,1,'Master proof reads notice');eq(result.attack_confirmed,false,'never attacker attribution');eq('correlation_key' in result.events[0],false,'no correlation secret');await assert.rejects(db.query('select public.read_security_observation_notices($1)',[proof]));await db.query('reset role');
 // Separate signed events race for the final slot. Capture at most one and
 // account explicitly for the missing notice; both real collector evidences
 // remain intact and neither caller controls the recipient.
 await db.query(`insert into security_observation_notice_private.outbox(event_id,collector_id,company_id,recipient_id,config_revision)
  select gen_random_uuid(),$1,$2,$3,1 from generate_series(1,999-(select count(*)::int from security_observation_notice_private.outbox))`,[collector,cid,actor]);
 await claims(a,'service_role');await claims(b,'service_role');
 const capacityA={...event,event_id:randomUUID()},capacityB={...event,event_id:randomUUID()};
 await Promise.all([a.query('select public.ingest_signed_security_collector_event($1)',[envelope(capacityA)]),b.query('select public.ingest_signed_security_collector_event($1)',[envelope(capacityB)])]);
 eq(await count('outbox'),1000,'concurrent capture never exceeds bound');
 eq((await db.query('select capacity_gaps::int n from security_observation_notice_private.coverage')).rows[0].n,1,'one missing notification is explicitly counted');
 eq((await db.query('select count(*)::int n from private.security_collector_evidence where event_id=any($1::uuid[])',[[capacityA.event_id,capacityB.event_id]])).rows[0].n,2,'both signed observations remain in collector');
 await db.query("update private.security_collector_keys set valid_from=clock_timestamp()-interval '9 days',valid_until=clock_timestamp()-interval '8 days' where collector_id=$1",[collector]);
 await db.query('select private.purge_expired_security_collector_events()');
 eq((await db.query('select count(*)::int n from private.security_collector_keys where collector_id=$1',[collector])).rows[0].n,1,'expired historical key is retained while pinned signed evidence exists');
 console.log(JSON.stringify({ok:true,postgres17:true,actual_collector_sql:true,real_pgcrypto:true,concurrent_signed_retries:true,concurrent_publication:true,post_only:true,actual_proof_sql:true,synthetic_auth_surroundings:true,real_gotrue:false,actual_notifications:false}));
}finally{for(const c of [a,b,db]){await c.query('rollback').catch(()=>{});await c.end();}}
