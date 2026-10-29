// CI-only disposable GoTrue + Native PG + actual TLS/server/client composition.
// Registry/Master/company association is synthetic; source-owner registration,
// independent custody, production least-privilege pool and deployment are absent.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';import path from 'node:path';
import {execFile} from 'node:child_process';import {promisify} from 'node:util';
import {createServer as reservePort} from 'node:net';import {request as httpsRequest} from 'node:https';
import {createHash,randomBytes,randomUUID,generateKeyPairSync,sign} from 'node:crypto';
import {createArchiveByteStoreCandidate} from '../src/archive-byte-store-candidate.mjs';
import {createArchiveReadbackServerCandidate} from '../src/archive-readback-server-candidate.mjs';
import {createArchiveReadbackHTTPSVerifierCandidate} from '../src/archive-readback-https-candidate.mjs';

const run=promisify(execFile),root=process.cwd(),parent=path.resolve(process.env.RUNNER_TEMP??'');
if(process.env.CI!=='true'||!process.env.RUNNER_TEMP||parent==='/'||Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))throw Error('Dedicated disposable CI without hosted credentials required');
const project=`sko-archive-native-${randomBytes(8).toString('hex')}`,workdir=path.join(parent,project);
const cli=(args,timeout=120000)=>run('npx',['--yes','supabase@2.121.0',...args,'--workdir',workdir],{cwd:root,timeout,maxBuffer:1024*1024,env:process.env});
const claims=token=>JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString('utf8'));
const sha=x=>createHash('sha256').update(x).digest('hex'),delay=ms=>new Promise(r=>setTimeout(r,ms));
function deferred(){let resolve;return {promise:new Promise(r=>resolve=r),resolve:(...v)=>resolve(...v)};}
let phase='setup',started=false,owned=false,db,pool,pg,lastStatus,poolErrors=0;const servers=[],extraClients=[];
async function until(check){for(let i=0;i<250;i++){if(await check())return;await delay(20);}throw Error('native condition not observed');}
async function stage(promise){let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('native fixture stage unavailable')),15000);})]);}finally{clearTimeout(timer);}}
try{
 await fs.mkdir(workdir,{mode:0o700});owned=true;await cli(['init']);
 const configPath=path.join(workdir,'supabase/config.toml');let config=await fs.readFile(configPath,'utf8');
 config=config.replace(/^project_id = .*$/m,`project_id = "${project}"`).replaceAll('54321','54181').replaceAll('54322','54182').replaceAll('54320','54180')
  .replaceAll('54323','54183').replaceAll('54324','54184').replaceAll('54327','54187').replaceAll('54329','54189').replaceAll('127.0.0.1:3000','127.0.0.1:54181')
  .replace(/(\[db.seed\][\s\S]*?enabled = )true/,'$1false');
 await fs.writeFile(configPath,config,{mode:0o600});
 assert.equal((await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.ID}}'])).stdout.trim(),'');
 phase='disposable-stack';started=true;
 await cli(['start','--exclude','edge-runtime,realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor,mailpit'],600000);
 const status=JSON.parse((await cli(['status','--output','json'])).stdout),api=new URL(status.API_URL),database=new URL(status.DB_URL);
 assert.equal(api.origin,'http://127.0.0.1:54181');assert.equal(database.hostname,'127.0.0.1');assert.equal(database.port,'54182');assert.equal(database.pathname,'/postgres');
 const anon=status.ANON_KEY,service=status.SERVICE_ROLE_KEY;assert.equal(typeof anon,'string');assert.equal(claims(service).role,'service_role');
 pg=(await import(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 db=new pg.Client({connectionString:database.href});await db.connect();
 const native=Number((await db.query("select current_setting('server_version_num') n")).rows[0].n);assert.ok(native>=170000&&native<180000);
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0);
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
 const authRequest=async(route,{token,body,admin=false,method='POST'}={})=>{
  const url=new URL(route,api);assert.equal(url.origin,api.origin);
  const result=await fetch(url,{method,redirect:'error',signal:AbortSignal.timeout(15000),headers:{apikey:admin?service:anon,
   ...(admin?{Authorization:`Bearer ${service}`}:{ }),...(token?{Authorization:`Bearer ${token}`}:{ }),...(body===undefined?{}:{'content-type':'application/json'})},
   ...(body===undefined?{}:{body:JSON.stringify(body)})});lastStatus=result.status;return result;
 };
 const json=async response=>{assert.equal(response.status,200,phase);return response.json();};
 phase='same-guard-schema';
 await db.query(await fs.readFile(new URL('./archive-readback-real-auth-fixture.sql',import.meta.url),'utf8'));
 for(const f of JSON.parse(await fs.readFile(new URL('../../free-worker-candidate/issuer/current-core-fixtures.json',import.meta.url),'utf8')))await db.query(f.definition);
 await db.query(await fs.readFile(new URL('../../free-worker-candidate/issuer/management-issuer.sql.review-only',import.meta.url),'utf8'));
 await db.query(await fs.readFile(new URL('../src/archive-readback-registry.sql.review-only',import.meta.url),'utf8'));
 const login=async email=>{
  const link=await json(await authRequest('/auth/v1/admin/generate_link',{admin:true,body:{type:'magiclink',email}}));
  return json(await authRequest('/auth/v1/verify',{body:{type:'magiclink',token_hash:link.hashed_token}}));
 };
 const user=async()=>{const email=`archive-${randomUUID()}@example.invalid`;const saved=await json(await authRequest('/auth/v1/admin/users',{admin:true,body:{email,email_confirm:true}}));const signed=await login(email);assert.equal(signed.user.id,saved.id);return {...signed,email};};
 phase='real-gotrue-users';const owner=await user(),foreign=await user(),company=randomUUID(),foreignCompany=randomUUID(),authority=randomUUID(),keys=generateKeyPairSync('ed25519'),key=keys.publicKey.export({format:'jwk'});
 await db.query('insert into private.master_admins values($1,true),($2,true)',[owner.user.id,foreign.user.id]);
 await db.query("insert into company_members values($1,$2,'owner'),($3,$4,'owner')",[company,owner.user.id,foreignCompany,foreign.user.id]);
 await db.query("insert into user_secondary_credentials(user_id,password_hash)values($1,extensions.crypt('fixture-only',extensions.gen_salt('bf',4))),($2,extensions.crypt('fixture-only',extensions.gen_salt('bf',4)))",[owner.user.id,foreign.user.id]);
 for(const [deployment,c,a]of[['native_archive_a',company,owner.user.id],['native_archive_b',foreignCompany,foreign.user.id]])await db.query('insert into security_management_issuer_private.deployments(deployment_id,company_id,owner_id,enabled,key_id,key_version,manager_jwk)values($1,$2,$3,true,$1,1,$4)',[deployment,c,a,key]);
 const byteRoot=path.join(workdir,'opaque-bytes');await fs.mkdir(byteRoot,{mode:0o700});const store=await createArchiveByteStoreCandidate({enabled:true,directory:byteRoot});
 const put=async(c,p)=>store.retain({company_id:c,event_id:randomUUID(),revision:2,snapshot_sha256:'a'.repeat(64),payload_sha256:sha(p),payload:p});
 const own=await put(company,Buffer.from('opaque native own')),other=await put(foreignCompany,Buffer.from('opaque native foreign'));
 const register=async(d,a,deployment)=>db.query('insert into archive_readback_private.authority_records(object_id,authority_id,company_id,owner_id,deployment_id,event_id,revision,snapshot_sha256,payload_sha256,byte_length)values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',[d.object_id,authority,d.company_id,a,deployment,d.event_id,d.revision,d.snapshot_sha256,d.payload_sha256,d.byte_length]);
 // Synthetic administrator seeds only. Authentic source-owner enrollment is absent.
 await register(own,owner.user.id,'native_archive_a');await register(other,foreign.user.id,'native_archive_b');
 const tlsKey=path.join(workdir,'tls.key'),tlsCert=path.join(workdir,'tls.crt');
 await run('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-days','1','-keyout',tlsKey,'-out',tlsCert,'-subj','/CN=localhost','-addext','subjectAltName=IP:127.0.0.1']);
 const tls={key:await fs.readFile(tlsKey),cert:await fs.readFile(tlsCert)};
 pool=new pg.Pool({connectionString:database.href,max:1});
 pool.on('error',()=>{poolErrors++;process.exitCode=1;}); // unexpected idle errors fail CI without private details
 const releases=[],queries=[];let acquired=0,restored=0,signed=0,authVerified=0;
 let dbDelay=false;const slowQueryEntered=deferred();
 const tracked={async connect(){const c=await pool.connect();acquired++;return {query:async(text,args)=>{
  queries.push({pid:c.processID,text});
  if(dbDelay&&text.startsWith('select * from archive_readback_private.authority_records')){slowQueryEntered.resolve(c.processID);await c.query('select pg_sleep(30)');}
  return c.query(text,args);
 },release(destroy=false){releases.push({pid:c.processID,destroy});c.release(destroy);}};}};
 // Test-only fixed-origin bridge. Actual /user goes to real disposable GoTrue;
 // no success response is fabricated and the exact JWT/bounds/abort are retained.
 const realAuthFetch=async(url,options)=>{
  assert.equal(url,'https://archive-auth-fixture.invalid/auth/v1/user');assert.equal(options.method,'GET');assert.equal(options.headers.apikey,anon);
  const response=await fetch(new URL('/auth/v1/user',api),{...options,redirect:'error'});authVerified++;return response;
 };
 const base={enabled:true,tls,auth:{url:'https://archive-auth-fixture.invalid',publicKey:anon,serviceBearer:service,fetchImpl:realAuthFetch},pool:tracked,
  store:{async restore(d){restored++;return store.restore(d);}},authorityId:authority,key,timeoutMs:10000,
  signObservation:async b=>{signed++;return sign(null,b,keys.privateKey);}};
 async function server(options={}){
  const reservation=reservePort();await new Promise(r=>reservation.listen(0,'127.0.0.1',r));const port=reservation.address().port;await new Promise(r=>reservation.close(r));
  const endpoint=`https://127.0.0.1:${port}/readback`,s=createArchiveReadbackServerCandidate({...base,endpoint,...options});
  await new Promise((resolve,reject)=>{s.once('error',reject);s.listen(port,'127.0.0.1',resolve);});servers.push(s);
  return {endpoint,client:(bearer=owner.access_token)=>createArchiveReadbackHTTPSVerifierCandidate({enabled:true,endpoint,bearer,ca:tls.cert,authorityId:authority,key,timeoutMs:15000})};
 }
 const normal=await server();
 const clean=async()=>{await until(async()=>pool.waitingCount===0&&pool.idleCount===pool.totalCount);const c=await pool.connect();try{assert.deepEqual((await c.query("select auth.uid() as actor,nullif(current_setting('request.jwt.claims',true),'') as jwt")).rows[0],{actor:null,jwt:null});}finally{c.release();}};
 const backendGone=pid=>until(async()=>!(await db.query('select exists(select 1 from pg_stat_activity where pid=$1) present',[pid])).rows[0].present);
 const newAdmin=async()=>{const c=new pg.Client({connectionString:database.href});await c.connect();extraClients.push(c);return c;};
 phase='real-auth-native-success';assert.equal((await normal.client().verify(own)).status,'readback_verified_unattested');assert.equal(restored,1);assert.equal(signed,1);assert.ok(authVerified>0);await clean();
 phase='forged-exact-token-before-pool';const token=owner.access_token.split('.'),beforePool=acquired;
 const forged=[token[0],Buffer.from(JSON.stringify({...claims(owner.access_token),sub:foreign.user.id})).toString('base64url'),token[2]].join('.');
 await assert.rejects(normal.client(forged).verify(own));assert.equal(acquired,beforePool);
 phase='foreign-and-provenance-refusal';const beforeRestore=restored,beforeSign=signed;
 await assert.rejects(normal.client().verify(other));await assert.rejects(normal.client().verify({...other,company_id:company}));
 const unregistered=await put(company,Buffer.from('unregistered native bytes'));await assert.rejects(normal.client().verify(unregistered));assert.equal(restored,beforeRestore);assert.equal(signed,beforeSign);await clean();
 phase='real-user-metadata-is-not-master';
 await json(await authRequest('/auth/v1/user',{method:'PUT',token:owner.access_token,body:{data:{is_master:true,company_id:company}}}));
 await db.query('update private.master_admins set enabled=false where user_id=$1',[owner.user.id]);
 await assert.rejects(normal.client().verify(own));assert.equal(restored,beforeRestore);await clean();await db.query('update private.master_admins set enabled=true where user_id=$1',[owner.user.id]);
 phase='native-company-revocation-shared-lock';
 async function lockedRevocation({bearer,change,restore}){
  const entered=deferred(),gate=deferred(),held=await server({signObservation:async b=>{signed++;entered.resolve();await gate.promise;return sign(null,b,keys.privateKey);}});
  const pending=held.client(bearer).verify(own);pending.catch(()=>{});await stage(entered.promise);
  const sourcePid=queries.at(-1).pid,admin=await newAdmin(),adminPid=(await admin.query('select pg_backend_pid() pid')).rows[0].pid;
  const changing=admin.query(change.sql,change.args);changing.catch(()=>{});
  try{await until(async()=>{const r=await db.query('select pg_blocking_pids($1) blockers',[adminPid]);return r.rows[0].blockers.includes(sourcePid);});}
  finally{gate.resolve();}
  assert.equal((await pending).status,'readback_verified_unattested');await changing;
  await assert.rejects(normal.client(bearer).verify(own));await clean();if(restore)await db.query(restore.sql,restore.args);
 }
 await lockedRevocation({bearer:owner.access_token,change:{sql:"update company_members set role='employee'where company_id=$1 and user_id=$2",args:[company,owner.user.id]},restore:{sql:"update company_members set role='owner'where company_id=$1 and user_id=$2",args:[company,owner.user.id]}});
 phase='native-session-revocation-shared-lock';const session=await login(owner.email),sid=claims(session.access_token).session_id;
 await lockedRevocation({bearer:session.access_token,change:{sql:'delete from auth.sessions where id=$1',args:[sid]}});
 phase='disconnect-during-sign-releases-native-transaction';
 const entered=deferred(),gate=deferred(),done=deferred();let signAttempts=0;
 const held=await server({signObservation:async b=>{signAttempts++;entered.resolve();await gate.promise;try{return sign(null,b,keys.privateKey);}finally{done.resolve();}}});
 const controller=new AbortController(),aborted=assert.rejects(held.client().verify(own,{signal:controller.signal}));await stage(entered.promise);
 const sourcePid=queries.at(-1).pid;controller.abort();await aborted;
 await until(async()=>releases.some(x=>x.pid===sourcePid&&x.destroy));await backendGone(sourcePid);await clean();
 gate.resolve();await stage(done.promise);assert.equal(signAttempts,1);assert.equal(await normal.client().verify(own).then(r=>r.status),'readback_verified_unattested');
 phase='lost-response-after-commit-preserves-original';
 const signBefore=signed,commitBefore=queries.filter(q=>q.text==='commit').length;
 await new Promise((resolve,reject)=>{
  const body=Buffer.from(JSON.stringify({authority_id:authority,challenge:randomBytes(32).toString('hex'),descriptor:own}));
  let discarded=false;
  const req=httpsRequest(normal.endpoint,{method:'POST',ca:tls.cert,agent:false,headers:{authorization:`Bearer ${owner.access_token}`,'content-type':'application/json','content-length':body.length}},res=>{
   if(res.statusCode!==200){res.destroy();req.destroy();reject(Error('read response unavailable'));return;}
   discarded=true;res.destroy();req.destroy();resolve();
  });req.setTimeout(15000,()=>{req.destroy();reject(Error('read response deadline'));});req.on('error',e=>{if(!discarded)reject(e);});req.end(body);
 });
 assert.equal(signed,signBefore+1);assert.equal(queries.filter(q=>q.text==='commit').length,commitBefore+1);await clean();
 assert.deepEqual(await store.restore(own),Buffer.from('opaque native own'));assert.equal((await normal.client().verify(own)).status,'readback_verified_unattested');assert.equal(signed,signBefore+2);
 phase='cancelled-pool-waiter-discards-late-native-lease-before-begin';
 const holder=await pool.connect(),holderPid=holder.processID,beforeQueries=queries.length,waitController=new AbortController();
 const rejected=assert.rejects(normal.client().verify(own,{signal:waitController.signal}));
 try{await until(async()=>pool.waitingCount===1);waitController.abort();await rejected;}
 finally{waitController.abort();holder.release();}
 await until(async()=>releases.some(x=>x.pid===holderPid&&x.destroy));await backendGone(holderPid);
 assert.equal(queries.length,beforeQueries);await clean();
 phase='actual-native-query-is-bounded-and-connection-terminates';
 dbDelay=true;const delayed=await server({timeoutMs:1000}),failed=assert.rejects(delayed.client().verify(own)),sleepPid=await stage(slowQueryEntered.promise);
 await until(async()=>{const r=await db.query("select query from pg_stat_activity where pid=$1",[sleepPid]);return r.rows[0]?.query==='select pg_sleep(30)';});
 await failed;await backendGone(sleepPid);dbDelay=false;await clean();
 phase='preserved-registry-source-and-user-records';
 assert.equal((await db.query('select count(*)::int n from archive_readback_private.authority_records')).rows[0].n,2);
 assert.deepEqual(await store.restore(own),Buffer.from('opaque native own'));assert.deepEqual(await store.restore(other),Buffer.from('opaque native foreign'));
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,2);
 assert.equal(poolErrors,0);
 console.log(JSON.stringify({result:'PASS real GoTrue Native PG archive readback server',native_pg_major:17,
  real_auth_exact_jwt:true,actual_tls_client_server:true,actual_existing_guard_sql:true,
  company_and_session_revocation_wait_for_shared_locks:true,disconnect_rolls_back_backend:true,
  lost_response_after_read_commit_preserves_original:true,pool_waiter_cancel_late_lease_destroyed_before_begin:true,
  actual_native_query_statement_bound_and_backend_exit:true,transaction_claim_cleanup:true,
  registry_master_company_associations_are_synthetic:true,source_owner_registration:false,
  production_pool_least_privilege:false,independent_custody:false,source_release:false,deployed:false,production_changed:false}));
}catch(error){
 console.error(JSON.stringify({result:'FAIL real GoTrue Native PG archive readback server',phase,
  kind:error?.code==='ERR_ASSERTION'?'assertion':/^[0-9A-Z]{5}$/.test(error?.code??'')?'postgres':'other',
  sqlstate:/^[0-9A-Z]{5}$/.test(error?.code??'')?error.code:null,last_http_status:lastStatus,
  source_line:Number(error?.stack?.match(/archive-readback-server-real-auth\.mjs:(\d+)/)?.[1]??0),private_details_omitted:true}));process.exitCode=1;
}finally{
 for(const server of servers){server.closeAllConnections();await new Promise(r=>server.close(r));}
 if(pool)await pool.end().catch(()=>{});for(const c of extraClients)await c.end().catch(()=>{});if(db)await db.end().catch(()=>{});
 let stopped=!started;if(started){try{await cli(['stop','--no-backup'],120000);stopped=true;}catch{process.exitCode=1;console.error('Disposable archive stack cleanup failed; private details omitted.');}}
 if(owned&&stopped)await fs.rm(workdir,{recursive:true,force:true});
}
