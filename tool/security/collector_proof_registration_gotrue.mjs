import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile,spawn} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
const run=promisify(execFile),root=process.cwd(),project=`sko-collector-proof-${randomBytes(8).toString('hex')}`;
const parent=path.resolve(process.env.RUNNER_TEMP??'');
if(!process.env.CI||!process.env.RUNNER_TEMP||parent==='/'||Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))throw Error('Isolated CI without hosted credentials required');
const workdir=path.join(parent,project),cliArgs=['--yes','supabase@2.121.0'];
let phase='setup',db,server,started=false,owns=false,lastHttp,edgeOutput='',fixtureActor,fixtureSession;
const cli=(args,timeout=120000)=>run('npx',[...cliArgs,...args,'--workdir',workdir],{cwd:root,timeout,maxBuffer:1024*1024,env:process.env});
const read=p=>fs.readFile(path.join(root,p),'utf8');
const hash=s=>createHash('sha256').update(s).digest('hex');
function claims(token){return JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString('utf8'));}
function statusCode(response,expected){assert.equal(response.status,expected,`HTTP status mismatch during ${phase}`);}
const wait=ms=>new Promise(r=>setTimeout(r,ms));
try{
 await fs.mkdir(workdir,{recursive:false,mode:0o700});owns=true;
 await fs.writeFile(path.join(workdir,'owned-fixture.json'),JSON.stringify({project,ports:[54020,54021,54022]}),{mode:0o600});
 await cli(['init']);
 const configPath=path.join(workdir,'supabase/config.toml');let config=await fs.readFile(configPath,'utf8');
 config=config.replace(/^project_id = .*$/m,`project_id = "${project}"`).replaceAll('54321','54021').replaceAll('54322','54022').replaceAll('54320','54020').replaceAll('54323','54023').replaceAll('54324','54024').replaceAll('54327','54027').replaceAll('54329','54029').replaceAll('127.0.0.1:3000','127.0.0.1:54021');
 // Only generated local config changes; product provider/Auth configuration is untouched.
 config=config.replace(/(\[db.seed\][\s\S]*?enabled = )true/, '$1false');
 await fs.writeFile(configPath,config,{mode:0o600});
 const fn=path.join(workdir,'supabase/functions/reauthenticate-operation');await fs.mkdir(fn,{recursive:true});
 for(const name of ['index.ts','handler.mjs'])await fs.copyFile(path.join(root,'supabase/functions/reauthenticate-operation',name),path.join(fn,name));
 const baselineFn=path.join(workdir,'supabase/functions/collector-baseline-proof');
 await fs.mkdir(baselineFn,{recursive:true});
 await fs.copyFile(path.join(root,'supabase/functions/reauthenticate-operation/index.ts'),path.join(baselineFn,'index.ts'));
 const candidateHandler=await read('supabase/functions/reauthenticate-operation/handler.mjs');
 const baselineHandler=candidateHandler
  .replace(" ['master.security_collector.read', 'master_security'],\n",'')
  .replace("  if(payload.operation==='master.security_collector.read'&&(Object.keys(target).join(',')!=='scope'||target.scope!=='decoy_collector'))return reply(400,{error:'invalid_request'});\n",'');
 assert.equal(hash(baselineHandler),'4dd554c9a298c312a88b255303e55324020b3dc81b21ee2e913b4cc530104be6','Known main baseline bytes required, not the missing historical collector candidate');
 await fs.writeFile(path.join(baselineFn,'handler.mjs'),baselineHandler,{mode:0o600});
 phase='local-stack';
 // Keep one Edge runtime owner: start must not serve the function before
 // the separately spawned functions-serve process has initialized it.
 // Output may contain local keys; capture in memory, never print/upload stdout/stderr.
 const existing=await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.ID}}']);if(existing.stdout.trim())throw Error('Existing fixture container collision');
 started=true;await cli(['start','--exclude','edge-runtime,realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor'],600000);
 const raw=await cli(['status','--output','json']);const status=JSON.parse(raw.stdout);
 const api=new URL(status.API_URL),database=new URL(status.DB_URL);
 if(!['127.0.0.1','localhost','[::1]'].includes(api.hostname)||api.protocol!=='http:'||api.port!=='54021'||!['127.0.0.1','localhost','[::1]'].includes(database.hostname)||database.port!=='54022'||database.pathname!=='/postgres')throw Error('Unexpected fixture endpoint');
 const publicKey=status.ANON_KEY??status.PUBLISHABLE_KEY,serviceKey=status.SERVICE_ROLE_KEY??status.SECRET_KEY;
 if(typeof publicKey!=='string'||typeof serviceKey!=='string')throw Error('Missing local fixture keys');
 const pg=(await import(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 db=new pg.Client({connectionString:database.href});await db.connect();
 const serverVersion=Number((await db.query('show server_version_num')).rows[0].server_version_num);
 assert.ok(serverVersion>=170000&&serverVersion<180000,'Native PostgreSQL17 fixture required');
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0,'Fresh local public schema required');
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0,'Fresh GoTrue fixture required');
 assert.equal((await db.query("select to_regnamespace('private') is null absent")).rows[0].absent,true);
 const serviceHeaders={apikey:serviceKey,...(!serviceKey.startsWith('sb_'+'secret_')?{Authorization:`Bearer ${serviceKey}`}:{})};
 async function request(route,{token,body,service=false,method='POST'}={}){
  const url=new URL(route,api);if(url.origin!==api.origin)throw Error('Nonlocal request refused');
  const response=await fetch(url,{method,redirect:'error',signal:AbortSignal.timeout(20000),headers:{...(service?serviceHeaders:{apikey:publicKey}),...(token?{Authorization:`Bearer ${token}`}:{}) ,...(body===undefined?{}:{'Content-Type':'application/json'})},...(body===undefined?{}:{body:JSON.stringify(body)})});
  let code;try{const data=await response.clone().json();const candidate=typeof data.error==='string'?data.error:data.code;if(typeof candidate==='string'&&/^[a-zA-Z0-9_-]{1,64}$/.test(candidate))code=candidate;}catch{/* Never log response content. */}
  lastHttp={route,status:response.status,code};
  if(response.status===502){
   const text=(await response.clone().text()).slice(0,4096).toLowerCase();
   const tags=['upstream','worker','boot','connection','timeout','bad gateway','invalidworkercreation'];
   lastHttp.gateway_markers=Object.fromEntries(tags.map(tag=>[tag,text.includes(tag)]));
   lastHttp.response_bytes=Buffer.byteLength(text);lastHttp.content_type=response.headers.get('content-type')?.split(';')[0];
  }
  return response;
 }
 async function rpc(name,body,token,service=false){return request(`/rest/v1/rpc/${name}`,{body,token,service});}
 const password=`fixture-${randomBytes(20).toString('hex')}!A1`;
 phase='real-gotrue-users';
 const users={};for(const name of ['master','admin','other']){
  const response=await request('/auth/v1/admin/users',{service:true,body:{email:`${name}@example.invalid`,password,email_confirm:true}});statusCode(response,200);const user=await response.json();assert.ok(typeof user.id==='string');users[name]=user;
 }
 async function login(user,pw=password){const r=await request('/auth/v1/token?grant_type=password',{body:{email:user.email,password:pw}});statusCode(r,200);const data=await r.json();assert.equal(data.user.id,user.id);assert.ok(claims(data.access_token).session_id);return data;}
 const master=await login(users.master),normalAdmin=await login(users.admin),other=await login(users.other);
 const masterSid=claims(master.access_token).session_id;fixtureActor=users.master.id;fixtureSession=masterSid;
 assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',[masterSid,users.master.id])).rows[0].n,1,'Real GoTrue must create the original session');

 phase='original-app-fixtures';
 await db.query(await read('tool/security/platform_auth_e2e_dependencies.sql'));
 await db.query(await read('supabase/migrations/20260929220000_add_master_admin_role_foundation.sql'));
 await db.query(await read('supabase/migrations/20260929221500_add_master_device_foundation.sql'));
 await db.query(await read('supabase/tests/fixtures/secondary_reset_before.sql'));
 await db.query(await read('supabase/tests/fixtures/reauthentication_master_before.sql'));
 await db.query(await read('supabase/migrations/20261013223123_master_security_incident_records.sql'));
 const company=randomUUID();
 await db.query("insert into public.companies(id,name) values($1,'isolated company')",[company]);
 for(const [name,user] of Object.entries(users))await db.query('insert into public.company_members values($1,$2,$3)',[company,user.id,name==='master'?'owner':'admin']);
 // Two real local users are masters, so cross-actor denial exercises proof
 // binding rather than merely rejecting a non-master before consumption.
 for(const name of ['master','other'])await db.query('insert into private.master_admins(user_id) values($1)',[users[name].id]);
 async function protectedIdentity(){return (await db.query("select jsonb_build_object('members',(select jsonb_agg(to_jsonb(x) order by user_id) from public.company_members x),'companies',(select jsonb_agg(to_jsonb(x) order by id) from public.companies x),'masters',(select jsonb_agg(to_jsonb(x) order by user_id) from private.master_admins x),'devices',(select jsonb_agg(to_jsonb(x) order by id) from private.master_devices x),'users',(select jsonb_agg(jsonb_build_object('id',id,'email',email,'phone',phone,'app_metadata',raw_app_meta_data) order by id) from auth.users),'identities',(select jsonb_agg(jsonb_build_object('user_id',user_id,'provider',provider,'provider_id',provider_id) order by user_id,provider) from auth.identities)) state")).rows[0].state;}
 const protectedBefore=await protectedIdentity();
 phase='base-mapper-and-issuer';
 await db.query(await read('tool/staged/reauthentication_proofs.sql'));
 assert.equal((await db.query("select private.reauthentication_scope('master.security_collector.read') s")).rows[0].s,'master_security');
 await db.query("notify pgrst,'reload schema'");
 for(let i=0;i<30;i++){const r=await rpc('reauthentication_capabilities',{},master.access_token);if(r.status===200)break;if(i===29)throw Error('Base capability schema unavailable');await wait(300);}
 await db.query("update private.reauthentication_rollout set enabled=true where scope='master_security'");
 const directNonce=randomBytes(32).toString('hex');
 const directBody={p_actor:users.master.id,p_session:masterSid,p_operation:'master.security_collector.read',p_target:{scope:'decoy_collector'},p_proof_hash:hash(directNonce)};
 statusCode(await rpc('issue_reauthentication_proof',{...directBody,p_target:{scope:'platform'}},undefined,true),403);
 statusCode(await rpc('issue_reauthentication_proof',directBody,undefined,true),200);
 await db.query('delete from private.reauthentication_proofs where proof_hash=$1',[hash(directNonce)]);
 await db.query("update private.reauthentication_rollout set enabled=false where scope='master_security'");
 phase='device-override-mapper-and-issuer';
 await db.query(await read('tool/staged/master_device_lock_reauthentication.sql'));
 assert.equal((await db.query("select private.reauthentication_scope('master.security_collector.read') s")).rows[0].s,'master_security');
 assert.equal((await db.query('select enabled from private.master_device_lock_rollout')).rows[0].enabled,false);
 assert.deepEqual(await protectedIdentity(),protectedBefore,'Registration cannot change identity/provider/company/member/master/device values');
 phase='exact-collector-review-unit-install';
 const collector=await read('docs/candidates/security_collector_storage_v1_20261020.sql.review-only');
 assert.equal(hash(collector),'b96f6e4365e2e992886f38dad0f777e55665f18b03525cddf4edbdf746348207');
 await db.query('create role sko_security_collector_ingest nologin noinherit');
 await db.query(collector);
 phase='explicit-fixture-private-read-bridges';
 // These two narrow RPCs exist ONLY in this disposable fixture. Current product
 // source has no public collector read route. They preserve the real request JWT
 // and call the exact existing private consumer; they are not a proposed API.
 await db.query("create function public.fixture_read_security_collector_events(p_proof text) returns jsonb language plpgsql security definer set search_path='' as $$begin if coalesce(auth.role(),'')<>'authenticated' then raise sqlstate '42501';end if;return private.read_security_collector_events(p_proof);end$$;revoke all on function public.fixture_read_security_collector_events(text) from public,anon,service_role;grant execute on function public.fixture_read_security_collector_events(text) to authenticated;");
 await db.query("create function public.fixture_consume_platform_scope(p_proof text) returns void language plpgsql security definer set search_path='' as $$begin if coalesce(auth.role(),'')<>'authenticated' then raise sqlstate '42501';end if;perform private.consume_reauthentication_proof('master.security_incidents.read','{\"scope\":\"platform\"}'::jsonb,p_proof);end$$;revoke all on function public.fixture_consume_platform_scope(text) from public,anon,service_role;grant execute on function public.fixture_consume_platform_scope(text) to authenticated;");
 assert.deepEqual((await db.query('select ingest_enabled,read_enabled from private.security_collector_control')).rows[0],{ingest_enabled:false,read_enabled:false});
 const collectorId=randomUUID(),eventId=randomUUID(),now=new Date().toISOString();
 const event={event_id:eventId,collector_id:collectorId,occurred_at:now,event_kind:'current_lure_touched',generation:1,correlation_key:'a'.repeat(64),key_epoch:now.slice(0,10)};
 await db.query('update private.security_collector_control set ingest_enabled=true');
 // The fixture owner seeds through the exact ingest function. Bridge-role and
 // HMAC authorization are covered by the separate signed transport Native job;
 // this proof does not grant role membership or pretend to re-prove that path.
 phase='fixture-owner-seeds-exact-ingest';
 await db.query('select private.ingest_security_collector_event($1)',[event]);
 await db.query('update private.security_collector_control set ingest_enabled=false');
 await db.query("notify pgrst,'reload schema'");
 phase='actual-edge-runtime';
 const beforeServe=await run('docker',['ps','--filter','name='+project,'--format','{{.Names}}']);
 assert.ok(!beforeServe.stdout.split('\n').some(n=>n.includes('edge')),'No prior Edge runtime can satisfy readiness');
 server=spawn('npx',[...cliArgs,'functions','serve','--workdir',workdir],{cwd:root,stdio:['ignore','pipe','pipe'],env:process.env});
 for(const stream of [server.stdout,server.stderr])stream.on('data',chunk=>{edgeOutput=(edgeOutput+chunk.toString()).slice(-65536);});
 const proofBody={operation:'master.security_collector.read',target:{scope:'decoy_collector'},password};
 async function obtain(token=master.access_token,body=proofBody,route='/functions/v1/reauthenticate-operation'){return request(route,{token,body});}
 let edgeReady=false;
 for(let i=0;i<90;i++){try{const r=await obtain();if(r.status===403&&(await r.json()).error==='reauthentication_disabled'){edgeReady=true;break;}}catch{}await wait(500);}
 assert.ok(edgeReady,'Actual candidate Edge must reject the default-OFF operation');
 phase='actual-baseline-fails-closed';
 const sessions=async()=> (await db.query('select id::text from auth.sessions where user_id=$1 order by id',[users.master.id])).rows;
 const baselineSessions=await sessions();
 const old=await obtain(master.access_token,proofBody,'/functions/v1/collector-baseline-proof');statusCode(old,400);
 assert.equal((await old.json()).error,'invalid_request');
 assert.deepEqual(await sessions(),baselineSessions,'Old handler rejects before a password verification session');
 assert.equal((await db.query('select count(*)::int n from private.reauthentication_proofs')).rows[0].n,0);
 phase='actual-proof-issuer-and-session-cleanup';
 await db.query("update private.reauthentication_rollout set enabled=true where scope='master_security'");
 async function proof(token=master.access_token,body=proofBody){
  const r=await obtain(token,body);statusCode(r,200);const value=await r.json();
  assert.match(value.proof,/^[0-9a-f]{64}$/);assert.equal(value.operation,body.operation);assert.deepEqual(value.target,body.target);
  assert.equal(value.access_token,undefined);assert.equal(value.refresh_token,undefined);
  assert.ok(Date.parse(value.expiresAt)>Date.now()&&Date.parse(value.expiresAt)<=Date.now()+125000);
  return value.proof;
 }
 const consumer=(p,token=master.access_token)=>rpc('fixture_read_security_collector_events',{p_proof:p},token);
 const stored=p=>db.query('select actor_id::text,session_id::text,operation,target,consumed_at from private.reauthentication_proofs where proof_hash=$1',[hash(p)]);
 const beforeSessions=await sessions(),p=await proof();
 assert.deepEqual(await sessions(),beforeSessions,'Temporary password session removed and original session retained');
 const bound=(await stored(p)).rows[0];assert.equal(bound.actor_id,users.master.id);assert.equal(bound.session_id,masterSid);assert.equal(bound.operation,proofBody.operation);assert.deepEqual(bound.target,proofBody.target);
 statusCode(await request('/auth/v1/user',{token:master.access_token,method:'GET'}),200);
 phase='collector-read-gate-does-not-burn-proof';
 statusCode(await consumer(p),500);
 assert.equal((await stored(p)).rows[0].consumed_at,null);
 assert.equal((await db.query('select count(*)::int n from private.security_collector_read_audit')).rows[0].n,0);
 await db.query('update private.security_collector_control set read_enabled=true');
 phase='actual-private-consumer-and-single-consumption';
 const response=await consumer(p);statusCode(response,200);const report=await response.json();
 assert.equal(report.source_provenance,'trusted_collector_observation');assert.equal(report.attack_confirmed,false);assert.equal(report.events.length,1);assert.equal(report.events[0].event_id,eventId);
 assert.notEqual((await stored(p)).rows[0].consumed_at,null);
 statusCode(await consumer(p),403);
 const audit=(await db.query('select actor_id::text,result_count from private.security_collector_read_audit')).rows;
 assert.deepEqual(audit,[{actor_id:users.master.id,result_count:1}]);
 phase='actual-negative-actor-session-scope-target';
 const actorBound=await proof();statusCode(await consumer(actorBound,other.access_token),403);statusCode(await consumer(actorBound),200);
 statusCode(await obtain(normalAdmin.access_token),403);
 const second=await login(users.master),sessionBound=await proof();statusCode(await consumer(sessionBound,second.access_token),403);statusCode(await consumer(sessionBound),200);
 const scopeBound=await proof();statusCode(await rpc('fixture_consume_platform_scope',{p_proof:scopeBound},master.access_token),403);statusCode(await consumer(scopeBound),200);
 const platform=await proof(master.access_token,{operation:'master.security_incidents.read',target:{scope:'platform'},password});
 statusCode(await consumer(platform),403);assert.equal((await stored(platform)).rows[0].consumed_at,null);
 for(const target of [{scope:'platform'},{scope:'decoy_collector',extra:true},{scope:'DECOY_COLLECTOR'},{}])statusCode(await obtain(master.access_token,{...proofBody,target}),400);
 statusCode(await obtain(master.access_token,{...proofBody,password:'wrong-fixture-password'}),403);
 phase='actual-expired-revoked-and-disabled-boundaries';
 const expiring=await proof();await db.query("update private.reauthentication_proofs set issued_at=statement_timestamp()-interval '3 minutes',expires_at=statement_timestamp()-interval '1 minute' where proof_hash=$1",[hash(expiring)]);statusCode(await consumer(expiring),403);
 const revoked=await proof(second.access_token);statusCode(await request('/auth/v1/logout?scope=local',{token:second.access_token}),204);assert.ok([401,403].includes((await consumer(revoked,second.access_token)).status));
 const readOff=await proof();await db.query('update private.security_collector_control set read_enabled=false');statusCode(await consumer(readOff),500);assert.equal((await stored(readOff)).rows[0].consumed_at,null);
 await db.query('update private.security_collector_control set read_enabled=true');statusCode(await consumer(readOff),200);
 const gateOff=await proof();await db.query("update private.reauthentication_rollout set enabled=false where scope='master_security'");statusCode(await obtain(),403);statusCode(await consumer(gateOff),403);assert.equal((await stored(gateOff)).rows[0].consumed_at,null);
 await db.query("update private.reauthentication_rollout set enabled=true where scope='master_security'");statusCode(await consumer(gateOff),200);
 // The exact collector reader already fails closed for NULL helpers. Preserve
 // that contract; do not change the pinned consumer or claim a production bug.
 phase='forced-null-fixture-helpers-retain-proof';
 for(const signature of ['private.account_access_allowed()','public.is_current_user_master_admin()']){
  const nullableProof=await proof();
  const original=(await db.query('select pg_get_functiondef($1::regprocedure) definition,md5(prosrc) source_hash from pg_proc where oid=$1::regprocedure',[signature])).rows[0];
  const body=/LANGUAGE plpgsql/i.test(original.definition)?'BEGIN RETURN NULL; END;':'SELECT NULL::boolean';
  const forced=original.definition.replace(/\bAS\s+(\$[A-Za-z_0-9]*\$)[\s\S]*?\1\s*;?\s*$/i,(_all,tag)=>'AS '+tag+body+tag+';').replace(/^CREATE FUNCTION /i,'CREATE OR REPLACE FUNCTION ');
  assert.notEqual(forced,original.definition);
  const auditsBefore=(await db.query('select count(*)::int n from private.security_collector_read_audit')).rows[0].n;
  await db.query(forced);
  try{
   statusCode(await consumer(nullableProof),403);
   assert.equal((await stored(nullableProof)).rows[0].consumed_at,null);
   assert.equal((await db.query('select count(*)::int n from private.security_collector_read_audit')).rows[0].n,auditsBefore);
  }finally{
   await db.query(original.definition.replace(/^CREATE FUNCTION /i,'CREATE OR REPLACE FUNCTION '));
  }
  assert.equal((await db.query('select md5(prosrc) source_hash from pg_proc where oid=$1::regprocedure',[signature])).rows[0].source_hash,original.source_hash);
  statusCode(await consumer(nullableProof),200);
 }
 phase='identity-original-session-and-default-off-restored';
 assert.deepEqual(await protectedIdentity(),protectedBefore);
 statusCode(await request('/auth/v1/user',{token:master.access_token,method:'GET'}),200);
 statusCode(await request('/auth/v1/user',{token:normalAdmin.access_token,method:'GET'}),200);
 await db.query('update private.security_collector_control set ingest_enabled=false,read_enabled=false');
 await db.query("update private.reauthentication_rollout set enabled=false where scope='master_security'");
 assert.equal((await db.query('select enabled from private.master_device_lock_rollout')).rows[0].enabled,false);
 console.log(JSON.stringify({pass:true,real_local_gotrue:true,real_edge_runtime:true,real_postgrest:true,native_postgres:true,actual_private_collector_consumer:true,fixture_only_rpc_bridge:true,product_public_collector_route_exists:false,baseline_handler_fail_closed:true,original_session_preserved:true,temporary_session_cleaned:true,actor_session_scope_target_ttl_replay_and_gate_denials:true,existing_null_helper_guards_verified:true,original_identity_company_role_preserved:true,missing_historical_sources_recovered:false,production_changed:false}));
}catch(error){console.error(`FAIL local platform/auth integration phase=${phase} code=${typeof error?.code==='string'?error.code:'E2E_ASSERTION'}${typeof error?.actual==='number'&&typeof error?.expected==='number'?` actual=${error.actual} expected=${error.expected}`:''}`);if(lastHttp)console.error(JSON.stringify(lastHttp));
 if(server)console.error(JSON.stringify({edge_launcher_exit_code:server.exitCode,edge_launcher_signal:server.signalCode}));
 if(started){try{
  const listing=await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.Names}}'],{timeout:10000,maxBuffer:65536});const names=listing.stdout.trim().split('\n').filter(Boolean);
  console.error(JSON.stringify({owned_local_services:{edge:names.filter(n=>n.includes('edge')).length,kong:names.filter(n=>n.includes('kong')).length,database:names.filter(n=>n.includes('_db_')).length}}));
  const edge=names.find(n=>n.includes('edge')&&n.includes(project));if(edge){const logs=await run('docker',['logs','--tail','100',edge],{timeout:10000,maxBuffer:262144});edgeOutput+=(logs.stdout+logs.stderr).slice(-65536);}
 }catch{/* Only bounded process metadata is emitted below. */}}
 const tags=['InvalidWorkerCreation','WORKER_LIMIT','CPU time limit','wall clock','TypeError','SyntaxError','connection refused','worker boot','error','shutdown','failed','Failed','exception','Exception','Uncaught','retired','idle','event loop'];console.error(JSON.stringify({local_edge_diagnostic_counts:Object.fromEntries(tags.map(tag=>[tag,edgeOutput.split(tag).length-1]))}));
 if(db&&fixtureActor){try{console.error(JSON.stringify({local_auth_sessions:(await db.query('select count(*)::int active_sessions,count(*) filter(where id=$1)::int original_alive from auth.sessions where user_id=$2',[fixtureSession,fixtureActor])).rows[0]}));}catch{/* No raw query/response is printed. */}}

 process.exitCode=1;}
finally{
 if(db)await db.end().catch(()=>{});
 if(server){server.kill('SIGTERM');}
 if(started)await cli(['stop','--no-backup'],120000).catch(()=>{console.error('Local fixture cleanup failed');process.exitCode=1;});
 // CLI credentials remain memory-only; remove generated private fixture files.
 if(owns)await fs.rm(workdir,{recursive:true,force:true}).catch(()=>{});
}
