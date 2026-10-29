// Real GoTrue/JWT to existing pending adapter in an isolated CI stack only.
// Master ownership and device registration are synthetic fixtures; no activation.
// Disposable CI only. Real GoTrue credential enrollment; synthetic Google
// identity fixture and email bootstrap are NOT real Google OAuth/Face ID proof.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash,randomBytes,randomUUID,generateKeyPairSync,sign} from 'node:crypto';
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
import {migrationPossessionPayload} from './key-migration-possession.mjs';

const run=promisify(execFile),root=process.cwd();
const parent=path.resolve(process.env.RUNNER_TEMP??'');
if(process.env.CI!=='true'||!process.env.RUNNER_TEMP||parent==='/'||
 Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))
 throw Error('Dedicated disposable CI without hosted credentials required');
const project=`sko-master-pending-${randomBytes(8).toString('hex')}`,workdir=path.join(parent,project);
let phase='setup',db,pool,started=false,owned=false,lastStatus;
const cli=(args,timeout=120000)=>run('npx',['--yes','supabase@2.121.0',...args,'--workdir',workdir],
 {cwd:root,timeout,maxBuffer:1024*1024,env:process.env});
const digest=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const claims=token=>JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString('utf8'));
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));

try {
 await fs.mkdir(workdir,{recursive:false,mode:0o700});owned=true;
 await cli(['init']);
 const configPath=path.join(workdir,'supabase/config.toml');
 let config=await fs.readFile(configPath,'utf8');
 config=config.replace(/^project_id = .*$/m,`project_id = "${project}"`)
  .replaceAll('54321','53881').replaceAll('54322','53882').replaceAll('54320','53880')
  .replaceAll('54323','53883').replaceAll('54324','53884').replaceAll('54327','53887')
  .replaceAll('54329','53889').replaceAll('127.0.0.1:3000','127.0.0.1:53881')
  .replace(/(\[db.seed\][\s\S]*?enabled = )true/,'$1false');
 await fs.writeFile(configPath,config,{mode:0o600});
 phase='disposable-stack';
 const existing=await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.ID}}']);
 assert.equal(existing.stdout.trim(),'');
 started=true;
 await cli(['start','--exclude','edge-runtime,realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor,mailpit'],600000);
 const status=JSON.parse((await cli(['status','--output','json'])).stdout);
 const api=new URL(status.API_URL),database=new URL(status.DB_URL);
 assert.equal(api.protocol,'http:');assert.equal(api.hostname,'127.0.0.1');assert.equal(api.port,'53881');
 assert.equal(database.hostname,'127.0.0.1');assert.equal(database.port,'53882');assert.equal(database.pathname,'/postgres');
 const anon=status.ANON_KEY??status.PUBLISHABLE_KEY,service=status.SERVICE_ROLE_KEY??status.SECRET_KEY;
 assert.equal(typeof anon,'string');assert.equal(typeof service,'string');
 const pg=(await import(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 db=new pg.Client({connectionString:database.href});await db.connect();
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0);
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
 async function request(route,{token,body,admin=false,method='POST'}={}) {
  const url=new URL(route,api);assert.equal(url.origin,api.origin);
  const key=admin?service:anon;
  const response=await fetch(url,{method,redirect:'error',signal:AbortSignal.timeout(15000),
   headers:{apikey:key,...(admin&&!service.startsWith('sb_secret_')?{Authorization:`Bearer ${service}`}:{ }),
    ...(token?{Authorization:`Bearer ${token}`}:{ }),...(body===undefined?{}:{'Content-Type':'application/json'})},
   ...(body===undefined?{}:{body:JSON.stringify(body)})});
  lastStatus=response.status;return response;
 }
 async function json(response,expected=200) {assert.equal(response.status,expected,phase);return response.json();}

 phase='fixture-schema';
 await db.query(await fs.readFile(path.join(root,'tool/security/master-device-enrollment-candidate/key-migration-pending-adapter.gotrue.sql'),'utf8'));
 await db.query(await fs.readFile(path.join(root,'tool/security/master-device-enrollment-candidate/native-real-functions.sql'),'utf8'));
 await db.query(await fs.readFile(path.join(root,'tool/security/master-device-enrollment-candidate/key-migration-registry.sql.review-only'),'utf8'));
 const {storePendingDeviceKey}=await import('./key-migration-pending-adapter.mjs');
 const {handleMigrationChallengeRequest}=await import('./key-migration-challenge-http-candidate.mjs');
 await db.query(await fs.readFile(path.join(root,'tool/security/master-device-enrollment-candidate/key-migration-challenges.sql.review-only'),'utf8'));
 await db.query(await fs.readFile(path.join(root,'tool/security/master-device-enrollment-candidate/key-migration-owner-request.sql.review-only'),'utf8'));
 await db.query(await fs.readFile(path.join(root,'tool/security/master-device-enrollment-candidate/owner-issuer-store.sql.review-only'),'utf8'));
 const makeUser=async()=>{
  const email='master-pending-'+randomUUID()+'@example.invalid';
  const seed=await json(await request('/auth/v1/admin/users',{admin:true,body:{email,email_confirm:true}}));
  const link=await json(await request('/auth/v1/admin/generate_link',{admin:true,body:{type:'magiclink',email}}));
  const signed=await json(await request('/auth/v1/verify',{body:{type:'magiclink',token_hash:link.hashed_token}}));
  assert.equal(signed.user.id,seed.id);
  const c=claims(signed.access_token);
  assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',[c.session_id,seed.id])).rows[0].n,1);
  return signed;
 };
 phase='real-users';
 const owner=await makeUser(),other=await makeUser(),deviceId=randomUUID();
 await db.query('insert into private.fixture_master_owners values($1)',[owner.user.id]);
 await db.query("insert into private.master_devices(id,master_user_id,device_key,device_name,device_type) values($1,$2,'fixture-legacy-identifier','Fixture iPhone','iphone')",[deviceId,owner.user.id]);
 const pgModule=(await import(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 pool=new pgModule.Pool({connectionString:database.href,max:1});
 let acquisitions=0;
 // Harness-only bridge. /user verifies the real token before claims are decoded.
 // The bridge installs verified claims transaction-locally, never session-wide.
 // This is not a deployed API or a production trust/pool implementation.
 const authenticatedContext=async token=>{
  const response=await request('/auth/v1/user',{method:'GET',token});
  if(response.status!==200) throw Error('GoTrue rejected token');
  const user=await response.json(),c=claims(token);
  assert.equal(user.id,c.sub);assert.equal(c.role,'authenticated');
  assert.equal(c.is_anonymous,false);assert.equal(typeof c.session_id,'string');
  assert.ok(Number.isSafeInteger(c.exp)&&c.exp>Math.floor(Date.now()/1000));
  const verified=JSON.stringify(c);
  const verifiedPool={connect:async()=>{
   acquisitions++;
   const client=await pool.connect();
   return {query:async(text,params)=>{
    const result=await client.query(text,params);
    if(text==='begin') await client.query("select set_config('request.jwt.claims',$1,true)",[verified]);
    return result;
   },release:()=>client.release()};
  }};
  return {pool:verifiedPool,actor:user.id,session:c.session_id};
 };
 const enroll=async(token,extra={})=>storePendingDeviceKey({...await authenticatedContext(token),deviceId,
  publicKeyPem:generateKeyPairSync('ec',{namedCurve:'prime256v1'}).publicKey.export({type:'spki',format:'pem'}).toString(),...extra});
 const signingPair=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
 const key=signingPair.publicKey.export({type:'spki',format:'pem'}).toString();
 const http=async(token,action,extra={})=>handleMigrationChallengeRequest(new Request('https://fixture.invalid/challenge',{
  method:'POST',headers:{authorization:`Bearer ${token}`,'content-type':'application/json'},
  body:JSON.stringify({action,deviceId,publicKeyPem:key,...extra})}),{authenticateBearer:authenticatedContext});
 const count=async()=>Number((await db.query('select count(*) from master_device_enrollment_candidate.pending_key_migrations')).rows[0].count);
 phase='valid-real-jwt';
 const first=await enroll(owner.access_token);
 assert.equal(first.status,'pending');assert.equal(await count(),1);
 const clean=async()=>{
  const x=await pool.query("select auth.uid() as actor, nullif(current_setting('request.jwt.claims',true),'') as jwt");
  assert.equal(x.rows[0].actor,null);assert.equal(x.rows[0].jwt,null);
 };
 await clean();
 phase='http-verified-password-issue-and-exact-session-readback';
 const secret=randomBytes(24).toString('hex');
 await db.query("insert into public.user_secondary_credentials(user_id,password_hash) values($1,extensions.crypt($2,extensions.gen_salt('bf')))",[owner.user.id,secret]);
 const hashBefore=(await db.query('select password_hash from public.user_secondary_credentials where user_id=$1',[owner.user.id])).rows[0].password_hash;
 const wrong=await http(owner.access_token,'issue',{secondPassword:'synthetic-wrong'});
 assert.equal(wrong.status,403);assert.deepEqual(await wrong.json(),{accepted:false});
 assert.equal((await db.query('select failed_attempts from public.user_secondary_credentials where user_id=$1',[owner.user.id])).rows[0].failed_attempts,1);
 const issued=await http(owner.access_token,'issue',{secondPassword:secret});
 assert.equal(issued.status,200);const original=await issued.json();
 assert.equal(original.accepted,true);assert.equal(original.challenge.actor,owner.user.id);
 assert.equal(original.challenge.session,claims(owner.access_token).session_id);
 const readback=await http(owner.access_token,'read');assert.equal(readback.status,200);
 assert.deepEqual(await readback.json(),original);
 assert.equal((await http(owner.access_token,'issue',{secondPassword:secret})).status,409);
 assert.equal((await http(owner.access_token,'read',{actor:other.user.id})).status,400);
 assert.equal(Number((await db.query('select count(*) from master_device_enrollment_candidate.key_possession_challenges')).rows[0].count),1);
 assert.equal((await db.query('select password_hash from public.user_secondary_credentials where user_id=$1',[owner.user.id])).rows[0].password_hash,hashBefore);
 await clean();
 phase='http-submit-proof-and-read-original-pending';
 const proposal=pendingDeviceKeyMigration({actor:owner.user.id,device:{id:deviceId,master_user_id:owner.user.id,is_locked:false,revoked_at:null},publicKeyPem:key});
 const signature=sign('sha256',migrationPossessionPayload(original.challenge,proposal),signingPair.privateKey).toString('base64');
 assert.equal((await http(owner.access_token,'status',{challengeId:original.challenge.id})).status,409);
 const submitted=await http(owner.access_token,'submit',{challengeId:original.challenge.id,signature});
 assert.equal(submitted.status,200);const pendingReceipt=await submitted.json();assert.equal(pendingReceipt.submission.status,'pending');
 assert.equal((await http(owner.access_token,'submit',{challengeId:original.challenge.id,signature})).status,409);
 const submissionStatus=await http(owner.access_token,'status',{challengeId:original.challenge.id});assert.equal(submissionStatus.status,200);
 assert.deepEqual(await submissionStatus.json(),pendingReceipt);
 assert.equal(await count(),2);await clean();
 phase='http-owner-evidence-forced-stored-issuer';
 const {requestIndependentOwnerApproval}=await import('./key-migration-owner-request.mjs');
 const {ownerDecisionPayload}=await import('./owner-decision-attestation.mjs');
 const ownerRequest=await requestIndependentOwnerApproval({...await authenticatedContext(owner.access_token),deviceId,publicKeyPem:key,
  challengeId:original.challenge.id,pendingId:pendingReceipt.submission.id});
 const authorityId=randomUUID(),issuer=generateKeyPairSync('ed25519');
 const issuerPin={purpose:'sko-master-independent-owner-decision-v1',authorityId,epoch:1,keyId:'synthetic-independent-issuer',
  publicKeyJwk:issuer.publicKey.export({format:'jwk'}),headSha256:'a'.repeat(64),retiredKeys:[]};
 // Explicit synthetic authority bootstrap/checkpoint. Real GoTrue proves only
 // bearer/session validation, NOT this independent human-verification issuer.
 const ownerCheckpoint={authorityId,epoch:1,headSha256:issuerPin.headSha256,keyId:issuerPin.keyId,
  publicKeySha256:createHash('sha256').update(issuer.publicKey.export({type:'spki',format:'der'})).digest('hex'),
  retiredKeysSha256:digest(['sko-master-owner-issuer-retired-keys-v1',authorityId,[]])};
 await db.query('insert into master_device_enrollment_candidate.owner_issuer_heads(authority_id,epoch,pin) values($1,1,$2::jsonb)',[authorityId,JSON.stringify(issuerPin)]);
 const ownerRow=(await db.query(`select *,floor(extract(epoch from clock_timestamp())*1000)::float8 as now
  from master_device_enrollment_candidate.owner_approval_requests where id=$1`,[ownerRequest.id])).rows[0];
 const unsignedOwner={version:1,issuerKeyId:issuerPin.keyId,decision:'approved',requestId:ownerRequest.id,actor:owner.user.id,
  requesterSession:claims(owner.access_token).session_id,deviceId,pendingId:ownerRow.pending_id,challengeId:ownerRow.challenge_id,
  keySha256:ownerRow.key_sha256,reviewNonce:ownerRow.review_nonce,issuedMs:ownerRow.now,expiresMs:Math.min(ownerRow.expires_ms,ownerRow.now+120000)};
 const signedOwner={...unsignedOwner,signature:sign(null,ownerDecisionPayload(unsignedOwner),issuer.privateKey).toString('base64url')};
 let checkpointLoads=0;
 const httpOwner=async(token,{enabled=true,extra={}}={})=>handleMigrationChallengeRequest(new Request('https://fixture.invalid/challenge',{
  method:'POST',headers:{authorization:`Bearer ${token}`,'content-type':'application/json'},
  body:JSON.stringify({action:'owner-evidence',requestId:ownerRequest.id,receipt:signedOwner,...extra})}),{
  authenticateBearer:authenticatedContext,ownerEvidence:{enabled,loadAuthorityCheckpoint:async who=>{
   checkpointLoads++;assert.equal(typeof who.actor,'string');assert.equal(typeof who.session,'string');return ownerCheckpoint;
  }},
 });
 const evidenceCount=async()=>Number((await db.query('select count(*) from master_device_enrollment_candidate.owner_decision_evidence')).rows[0].count);
 assert.equal((await httpOwner(owner.access_token,{enabled:false})).status,503);assert.equal(checkpointLoads,0);assert.equal(await evidenceCount(),0);
 const ownerRecorded=await httpOwner(owner.access_token);assert.equal(ownerRecorded.status,200);
 const recordedOwner=await ownerRecorded.json();assert.equal(recordedOwner.evidence.status,'evidence_recorded');assert.equal(await evidenceCount(),1);
 assert.equal(ownerRecorded.headers.get('cache-control'),'no-store');
 for(const extra of [{issuerMode:'fixed'},{pinnedIssuer:issuerPin},{authorityCheckpoint:ownerCheckpoint},{actor:other.user.id}]){
  const acquiredBefore=acquisitions;assert.equal((await httpOwner(owner.access_token,{extra})).status,400);assert.equal(acquisitions,acquiredBefore);
 }
 assert.deepEqual(await(await httpOwner(owner.access_token)).json(),recordedOwner);assert.equal(await evidenceCount(),1);await clean();
 phase='tampered-token-rejected-before-pool';
 const parts=owner.access_token.split('.');
 const altered={...claims(owner.access_token),sub:other.user.id};
 const forged=[parts[0],Buffer.from(JSON.stringify(altered)).toString('base64url'),parts[2]].join('.');
 const before=acquisitions;
 await assert.rejects(enroll(forged));
 assert.equal(acquisitions,before);assert.equal(await count(),2);
 assert.equal((await http(forged,'read')).status,409);assert.equal(acquisitions,before);
 assert.equal((await httpOwner(forged)).status,409);assert.equal(acquisitions,before);assert.equal(await evidenceCount(),1);
 phase='other-real-user-not-master';
 await assert.rejects(enroll(other.access_token));
 assert.equal(await count(),2);await clean();
 assert.equal((await http(other.access_token,'read')).status,409);await clean();
 assert.equal((await http(other.access_token,'status',{challengeId:original.challenge.id})).status,409);await clean();
 assert.equal((await httpOwner(other.access_token)).status,409);assert.equal(await evidenceCount(),1);await clean();
 phase='user-editable-metadata-not-master';
 await json(await request('/auth/v1/user',{method:'PUT',token:other.access_token,body:{data:{master:true,is_master_admin:true}}}));
 await assert.rejects(enroll(other.access_token));
 assert.equal(await count(),2);await clean();
 assert.equal((await http(other.access_token,'read')).status,409);await clean();
 assert.equal((await httpOwner(other.access_token)).status,409);assert.equal(await evidenceCount(),1);await clean();
 phase='verified-owner-cannot-substitute-session';
 await assert.rejects(enroll(owner.access_token,{session:claims(other.access_token).session_id}));
 assert.equal(await count(),2);await clean();
 phase='expired-session-row-rejected';
 await db.query("update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=$1",[claims(owner.access_token).session_id]);
 await assert.rejects(enroll(owner.access_token));
 assert.equal(await count(),2);await clean();
 assert.equal((await http(owner.access_token,'read')).status,409);await clean();
 assert.equal((await http(owner.access_token,'status',{challengeId:original.challenge.id})).status,409);await clean();
 assert.equal((await httpOwner(owner.access_token)).status,409);assert.equal(await evidenceCount(),1);await clean();
 await db.query('update auth.sessions set not_after=null where id=$1',[claims(owner.access_token).session_id]);
 phase='revoked-session-row-rejected';
 await db.query('delete from auth.sessions where id=$1',[claims(owner.access_token).session_id]);
 await assert.rejects(enroll(owner.access_token));
 assert.equal(await count(),2);await clean();
 assert.equal((await http(owner.access_token,'read')).status,409);await clean();
 assert.equal((await http(owner.access_token,'status',{challengeId:original.challenge.id})).status,409);await clean();
 assert.equal((await httpOwner(owner.access_token)).status,409);assert.equal(await evidenceCount(),1);await clean();
 assert.equal(Number((await db.query('select count(*) from master_device_enrollment_candidate.key_possession_challenges')).rows[0].count),1);
 phase='preserved-existing-identifier';
 assert.equal((await db.query('select device_key from private.master_devices where id=$1',[deviceId])).rows[0].device_key,'fixture-legacy-identifier');
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,2);
 console.log(JSON.stringify({result:'PASS isolated real GoTrue pending-key boundary',
  real_auth_user_token_validation:true,real_auth_uid_and_sessions:true,forged_jwt_rejected:true,
  foreign_user_and_metadata_not_master:true,session_substitution_rejected:true,
  expired_and_revoked_sessions_rejected:true,transaction_claim_cleanup:true,
  http_request_boundary_with_real_gotrue:true,http_password_counter_commit:true,http_original_challenge_readback:true,
  http_key_proof_submission_pending_only:true,http_consumed_result_reconciliation:true,
  http_owner_evidence_forced_stored_issuer:true,http_owner_evidence_auth_session_fail_closed:true,
  owner_evidence_authority_is_synthetic_fixture:true,
  master_and_device_fixtures:true,public_endpoint:false,key_activation:false,production_changed:false}));
} catch(error) {
 console.error(JSON.stringify({result:'FAIL isolated real GoTrue pending-key boundary',phase,
  kind:error?.code==='ERR_ASSERTION'?'assertion':/^[0-9A-Z]{5}$/.test(error?.code??'')?'postgres':'other',
  sqlstate:/^[0-9A-Z]{5}$/.test(error?.code??'')?error.code:null,last_http_status:lastStatus,private_response_omitted:true}));
 process.exitCode=1;
}finally{
 if(pool)await pool.end().catch(()=>{});
 if(db)await db.end().catch(()=>{});
 let stopped=!started;
 if(started){try{await cli(['stop','--no-backup'],120000);stopped=true;}catch{process.exitCode=1;console.error('Disposable master stack cleanup failed; private logs omitted.');}}
 if(owned&&stopped)await fs.rm(workdir,{recursive:true,force:true});
}

