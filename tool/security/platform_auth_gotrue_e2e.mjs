import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile,spawn} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {sanitizePlatformRows} from './platform_log_adapter.mjs';
const run=promisify(execFile),root=process.cwd(),project=`sko-platform-proof-${randomBytes(8).toString('hex')}`;
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
 await fs.writeFile(path.join(workdir,'owned-fixture.json'),JSON.stringify({project,ports:[53920,53921,53922]}),{mode:0o600});
 await cli(['init']);
 const configPath=path.join(workdir,'supabase/config.toml');let config=await fs.readFile(configPath,'utf8');
 config=config.replace(/^project_id = .*$/m,`project_id = "${project}"`).replaceAll('54321','53921').replaceAll('54322','53922').replaceAll('54320','53920').replaceAll('54323','53923').replaceAll('54324','53924').replaceAll('54327','53927').replaceAll('54329','53929').replaceAll('127.0.0.1:3000','127.0.0.1:53921');
 // Only generated local config changes; product provider/Auth configuration is untouched.
 config=config.replace(/(\[db.seed\][\s\S]*?enabled = )true/, '$1false');
 await fs.writeFile(configPath,config,{mode:0o600});
 const fn=path.join(workdir,'supabase/functions/reauthenticate-operation');await fs.mkdir(fn,{recursive:true});
 for(const name of ['index.ts','handler.mjs'])await fs.copyFile(path.join(root,'supabase/functions/reauthenticate-operation',name),path.join(fn,name));
 phase='local-stack';
 // Output may contain local keys; capture in memory, never print/upload stdout/stderr.
 const existing=await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.ID}}']);if(existing.stdout.trim())throw Error('Existing fixture container collision');
 started=true;await cli(['start','--exclude','realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor'],600000);
 const raw=await cli(['status','--output','json']);const status=JSON.parse(raw.stdout);
 const api=new URL(status.API_URL),database=new URL(status.DB_URL);
 if(!['127.0.0.1','localhost','[::1]'].includes(api.hostname)||api.protocol!=='http:'||api.port!=='53921'||!['127.0.0.1','localhost','[::1]'].includes(database.hostname)||database.port!=='53922'||database.pathname!=='/postgres')throw Error('Unexpected fixture endpoint');
 const publicKey=status.ANON_KEY??status.PUBLISHABLE_KEY,serviceKey=status.SERVICE_ROLE_KEY??status.SECRET_KEY;
 if(typeof publicKey!=='string'||typeof serviceKey!=='string')throw Error('Missing local fixture keys');
 const pg=(await import(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 db=new pg.Client({connectionString:database.href});await db.connect();
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0,'Fresh local public schema required');
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0,'Fresh GoTrue fixture required');
 assert.equal((await db.query("select to_regnamespace('private') is null absent")).rows[0].absent,true);
 const serviceHeaders={apikey:serviceKey,...(!serviceKey.startsWith('sb_'+'secret_')?{Authorization:`Bearer ${serviceKey}`}:{})};
 async function request(route,{token,body,service=false,method='POST'}={}){
  const url=new URL(route,api);if(url.origin!==api.origin)throw Error('Nonlocal request refused');
  const response=await fetch(url,{method,redirect:'error',signal:AbortSignal.timeout(20000),headers:{...(service?serviceHeaders:{apikey:publicKey}),...(token?{Authorization:`Bearer ${token}`}:{}) ,...(body===undefined?{}:{'Content-Type':'application/json'})},...(body===undefined?{}:{body:JSON.stringify(body)})});
  let code;try{const data=await response.clone().json();const candidate=typeof data.error==='string'?data.error:data.code;if(typeof candidate==='string'&&/^[a-zA-Z0-9_-]{1,64}$/.test(candidate))code=candidate;}catch{/* Never log response content. */}
  lastHttp={route,status:response.status,code};return response;
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
 await db.query(await read('supabase/tests/fixtures/secondary_reset_before.sql'));
 await db.query(await read('supabase/tests/fixtures/reauthentication_master_before.sql'));
 await db.query(await read('supabase/migrations/20261013223123_master_security_incident_records.sql'));
 const company=randomUUID();await db.query("insert into public.companies(id,name) values($1,'isolated company')",[company]);
 for(const [name,user] of Object.entries(users))await db.query('insert into public.company_members values($1,$2,$3)',[company,user.id,name==='master'?'owner':'admin']);
 await db.query('insert into private.master_admins(user_id) values($1)',[users.master.id]);
 const incident=randomUUID(),correlation=randomUUID(),date=new Date(Date.now()-120000).toISOString();
 const synthetic={incident_id:incident,correlation_id:correlation,detected_at:date,window_from:date,window_to:date,status:'detected',collection_status:'partial',missing_before:true,missing_after:false,event_count:0,events:[],first_seen:null,last_seen:null,source_tracking:'unavailable'};
 await db.query('insert into private.security_incident_records(incident_id,record_version,company_id,recipient_user_id,correlation_id,record) values($1,1,$2,$3,$4,$5)',[incident,company,users.master.id,correlation,synthetic]);
 await db.query("notify pgrst,'reload schema'");
 async function oldRead(token){const r=await rpc('master_security_incidents',{},token);statusCode(r,200);return r.json();}
 let oldBefore;for(let i=0;i<30;i++){const r=await rpc('master_security_incidents',{},master.access_token);if(r.status===200){oldBefore=await r.json();break;}if(r.status!==404&&r.status!==503)throw Error('Original monitor initialization failed');await wait(300);}assert.equal(oldBefore?.incidents.length,1,'Actual original RPC must return synthetic evidence');
 async function protectedIdentity(){return (await db.query(`select jsonb_build_object('members',(select jsonb_agg(to_jsonb(x) order by user_id) from public.company_members x),'companies',(select jsonb_agg(to_jsonb(x) order by id) from public.companies x),'masters',(select jsonb_agg(to_jsonb(x) order by user_id) from private.master_admins x),'users',(select jsonb_agg(jsonb_build_object('id',id,'email',email,'phone',phone,'app_metadata',raw_app_meta_data) order by id) from auth.users),'identities',(select jsonb_agg(jsonb_build_object('user_id',user_id,'provider',provider,'provider_id',provider_id) order by user_id,provider) from auth.identities)) state`)).rows[0].state;}
 const protectedBefore=await protectedIdentity();
 phase='actual-staged-sql';
 await db.query(await read('tool/staged/reauthentication_proofs.sql'));
 await db.query(await read('supabase/migrations/20261016104838_platform_security_monitor.sql'));
 assert.deepEqual(await oldRead(master.access_token),oldBefore,'Original synthetic read unchanged while gates OFF');
 assert.ok([400,401,403].includes((await rpc('master_security_incidents',{},normalAdmin.access_token)).status));
 assert.deepEqual(await protectedIdentity(),protectedBefore);
 await db.query("notify pgrst,'reload schema'");
 phase='actual-edge-runtime';
 server=spawn('npx',[...cliArgs,'functions','serve','--workdir',workdir],{cwd:root,stdio:['ignore','pipe','pipe'],env:process.env});
 for(const stream of [server.stdout,server.stderr])stream.on('data',chunk=>{edgeOutput=(edgeOutput+chunk.toString()).slice(-65536);});
 let edgeReady=false;for(let i=0;i<90;i++){
  try{const r=await request('/functions/v1/reauthenticate-operation',{token:master.access_token,body:{operation:'master.security_incidents.read',target:{scope:'platform'},password}});if(r.status===403){const data=await r.json();if(data.error==='reauthentication_disabled'){edgeReady=true;break;}}}catch{/* Local startup may still be in progress. */}
  await wait(500);
 }assert.ok(edgeReady,'Actual Edge must reject the default-OFF operation');
 await db.query("update private.reauthentication_rollout set enabled=true where scope='master_security';update private.platform_monitor_control set enabled=true");
 const to=new Date(Date.now()-60000).toISOString(),from=new Date(Date.parse(to)-300000).toISOString();
 const batch=sanitizePlatformRows({source:'edge_logs',rows:[{id:'isolated-platform-event',timestamp:new Date(Date.parse(from)+1000).toISOString(),status:'403',target:'/rest/v1/fixture?excluded=secret'}],from,to,hmacKey:randomBytes(32),keyEpoch:1});
 let ingested=false;for(let i=0;i<30;i++){const r=await rpc('service_ingest_platform_monitor',{p_batch:batch},undefined,true);if(r.status===200){ingested=true;break;}if(r.status!==404&&r.status!==503)throw Error('Local ingestion schema unavailable');await wait(300);}assert.ok(ingested);
 const proofBody={operation:'master.security_incidents.read',target:{scope:'platform'},password};
 async function obtain(token=master.access_token,body=proofBody){return request('/functions/v1/reauthenticate-operation',{token,body});}
 async function proof(token=master.access_token){const r=await obtain(token);statusCode(r,200);const data=await r.json();assert.match(data.proof,/^[0-9a-f]{64}$/);assert.equal(data.access_token,undefined);assert.equal(data.refresh_token,undefined);assert.ok(Date.parse(data.expiresAt)>Date.now()&&Date.parse(data.expiresAt)<=Date.now()+125000);return data.proof;}
 async function consume(p,token=master.access_token){return rpc('master_platform_security_monitor',{p_proof:p},token);}
 const sessionIds=async()=> (await db.query('select id::text from auth.sessions where user_id=$1 order by id',[users.master.id])).rows;
 phase='actual-proof-success-and-cleanup';
 const beforeSessions=await sessionIds(),p=await proof();assert.deepEqual(await sessionIds(),beforeSessions,'Temporary password session must be removed; original sessions remain');
 statusCode(await request('/auth/v1/user',{token:master.access_token,method:'GET'}),200);
 const report=await consume(p);statusCode(report,200);const value=await report.json();assert.equal(value.source_provenance,'supabase_platform_logs');assert.equal(value.events.length,1);assert.equal(value.events[0].source_tracking,'unavailable');
 statusCode(await consume(p),403);
 phase='actual-negative-boundaries';
 const wrong=await obtain(master.access_token,{...proofBody,password:'wrong-fixture-password'});assert.ok([400,401,403].includes(wrong.status));
 phase='negative-nonmaster-admin';statusCode(await obtain(normalAdmin.access_token),403);phase='negative-other-admin';statusCode(await obtain(other.access_token),403);
 phase='negative-target';statusCode(await obtain(master.access_token,{...proofBody,target:{scope:'other'}}),400);
 phase='negative-cross-session';const second=await login(users.master),bound=await proof();statusCode(await consume(bound,second.access_token),403);statusCode(await consume(bound),200);
 phase='negative-expiry';const expiring=await proof();await db.query("update private.reauthentication_proofs set issued_at=statement_timestamp()-interval '3 minutes',expires_at=statement_timestamp()-interval '1 minute' where proof_hash=$1",[hash(expiring)]);statusCode(await consume(expiring),403);
 phase='negative-disabled-master';const disabled=await proof();await db.query('update private.master_admins set enabled=false,disabled_at=clock_timestamp() where user_id=$1',[users.master.id]);statusCode(await consume(disabled),403);
 statusCode(await rpc('issue_reauthentication_proof',{p_actor:users.master.id,p_session:masterSid,p_operation:'master.security_incidents.read',p_target:{scope:'platform'},p_proof_hash:hash(randomBytes(32).toString('hex'))},undefined,true),403);
 statusCode(await obtain(),403);await db.query('update private.master_admins set enabled=true,disabled_at=null where user_id=$1',[users.master.id]);statusCode(await consume(disabled),200);
 phase='negative-restricted-account';const restricted=await proof();await db.query('insert into private.account_deletion_access_restrictions values($1)',[users.master.id]);statusCode(await consume(restricted),403);await db.query('delete from private.account_deletion_access_restrictions where user_id=$1',[users.master.id]);statusCode(await consume(restricted),200);
 phase='negative-revoked-session';const revoked=await proof(second.access_token);statusCode(await request('/auth/v1/logout?scope=local',{token:second.access_token}),204);assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1',[claims(second.access_token).session_id])).rows[0].n,0);assert.ok([401,403].includes((await consume(revoked,second.access_token)).status));
 phase='original-master-and-identities-preserved';
 assert.deepEqual(await oldRead(master.access_token),oldBefore,'Original real synthetic RPC remains unchanged with the new monitor enabled');
 assert.deepEqual(await protectedIdentity(),protectedBefore,'Account identity/provider/company/member/master fields remain unchanged');
 statusCode(await request('/auth/v1/user',{token:master.access_token,method:'GET'}),200);statusCode(await request('/auth/v1/user',{token:normalAdmin.access_token,method:'GET'}),200);
 assert.equal((await db.query('select count(*)::int n from private.security_incident_notification_outbox')).rows[0].n,0,'Read flow cannot enqueue notifications');
 console.log('PASS actual local GoTrue -> Edge password verification -> temporary-session cleanup -> service proof -> PostgREST platform read; TTL/replay/session/master/account/target/default-OFF boundaries.');
 console.log('PASS actual original synthetic RPC unchanged, normal-admin Auth session and original-master session/identity/company/member/master values preserved; notification outbox remains empty.');
 console.log('LIMIT: minimal fake app/account prerequisites, not complete production RLS/config/provider OAuth/device validation; no hosted connection, real secrets, external mail or production change.');
}catch(error){console.error(`FAIL local platform/auth integration phase=${phase} code=${typeof error?.code==='string'?error.code:'E2E_ASSERTION'}${typeof error?.actual==='number'&&typeof error?.expected==='number'?` actual=${error.actual} expected=${error.expected}`:''}`);if(lastHttp)console.error(JSON.stringify(lastHttp));
 if(server)console.error(JSON.stringify({edge_launcher_exit_code:server.exitCode,edge_launcher_signal:server.signalCode}));
 if(started){try{
  const listing=await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.Names}}'],{timeout:10000,maxBuffer:65536});const names=listing.stdout.trim().split('\n').filter(Boolean);
  console.error(JSON.stringify({owned_local_services:{edge:names.filter(n=>n.includes('edge')).length,kong:names.filter(n=>n.includes('kong')).length,database:names.filter(n=>n.includes('_db_')).length}}));
  const edge=names.find(n=>n.includes('edge')&&n.endsWith(project));if(edge){const logs=await run('docker',['logs','--tail','100',edge],{timeout:10000,maxBuffer:262144});edgeOutput+=(logs.stdout+logs.stderr).slice(-65536);}
 }catch{/* Only bounded process metadata is emitted below. */}}
 const tags=['InvalidWorkerCreation','WORKER_LIMIT','CPU time limit','wall clock','TypeError','SyntaxError','connection refused','worker boot','error','shutdown'];console.error(JSON.stringify({local_edge_diagnostic_counts:Object.fromEntries(tags.map(tag=>[tag,edgeOutput.split(tag).length-1]))}));
 if(db&&fixtureActor){try{console.error(JSON.stringify({local_auth_sessions:(await db.query('select count(*)::int active_sessions,count(*) filter(where id=$1)::int original_alive from auth.sessions where user_id=$2',[fixtureSession,fixtureActor])).rows[0]}));}catch{/* No raw query/response is printed. */}}

 process.exitCode=1;}
finally{
 if(db)await db.end().catch(()=>{});
 if(server){server.kill('SIGTERM');}
 if(started)await cli(['stop','--no-backup'],120000).catch(()=>{console.error('Local fixture cleanup failed');process.exitCode=1;});
 // CLI credentials remain memory-only; remove generated private fixture files.
 if(owns)await fs.rm(workdir,{recursive:true,force:true}).catch(()=>{});
}
