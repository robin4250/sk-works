// Disposable DB composition. All authority keys/checkpoints and Auth identities
// are explicit fixtures; this never establishes independent human trust.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash,createPublicKey,generateKeyPairSync,randomBytes,sign,verify} from 'node:crypto';
import {ownerIssuerContinuityPayload,verifyOwnerIssuerContinuity} from './owner-issuer-continuity.mjs';
import {commitOwnerIssuerTransition} from './owner-issuer-store.mjs';
import {recordOwnerDecisionUsingStoredIssuer} from './owner-decision-evidence.mjs';
import {ownerDecisionPayload} from './owner-decision-attestation.mjs';
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
import {migrationPossessionPayload} from './key-migration-possession.mjs';
import {storeProvenPendingDeviceKey} from './key-migration-proven-adapter.mjs';
import {requestIndependentOwnerApproval} from './key-migration-owner-request.mjs';
import {handleMigrationChallengeRequest} from './key-migration-challenge-http-candidate.mjs';
import {cancelIndependentOwnerApprovalRequest} from './key-migration-owner-request-lifecycle.mjs';
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const actor=id(1),session=id(2),deviceId=id(3);
const pair=()=>{const k=generateKeyPairSync('ed25519');return {...k,jwk:k.publicKey.export({format:'jwk'})};};
const spki=key=>createHash('sha256').update(createPublicKey({key,format:'jwk'}).export({type:'spki',format:'der'})).digest('hex');
const checkpoint=pin=>({authorityId:pin.authorityId,epoch:pin.epoch,headSha256:pin.headSha256,keyId:pin.keyId,publicKeySha256:spki(pin.publicKeyJwk),
 retiredKeysSha256:createHash('sha256').update(JSON.stringify(['sko-master-owner-issuer-retired-keys-v1',pin.authorityId,pin.retiredKeys.map(k=>[k.epoch,k.keyId,spki(k.publicKeyJwk)])])).digest('hex')});
export async function checkOwnerIssuerStore({pool,nativeConcurrency=false,pglite=false}){
 for(const name of ['native-setup.sql','native-real-functions.sql','key-migration-registry.sql.review-only','key-migration-challenges.sql.review-only','key-migration-owner-request.sql.review-only','owner-issuer-store.sql.review-only']){
  let sql=await readFile(new URL(name,import.meta.url),'utf8');
  if(pglite)sql=sql.replace('create extension pgcrypto with schema extensions;','').replace("extensions.crypt('synthetic-correct',extensions.gen_salt('bf',4))","'synthetic-unused'");
  await pool.query(sql);
 }
 const fixturePool={connect:async()=>{const c=await pool.connect();await c.query("select set_config('test.actor',$1,false),set_config('test.jwt',$2,false)",[actor,JSON.stringify({role:'authenticated',session_id:session,is_anonymous:false})]);return c;}};
 await pool.query(`insert into private.master_devices(id,master_user_id,device_key,device_name,device_type) values($1,$2,'legacy-original','Synthetic device','iphone')`,[deviceId,actor]);
 const now=async()=>Number((await pool.query('select floor(extract(epoch from clock_timestamp())*1000)::float8 as now')).rows[0].now);
 let authority=20;
 async function seed(){
  const old=pair(),next=pair(),authorityId=id(authority++);
  const pin={purpose:'sko-master-independent-owner-decision-v1',authorityId,epoch:1,keyId:'issuer_old',publicKeyJwk:old.jwk,headSha256:'a'.repeat(64),retiredKeys:[]};
  // Test-only independent genesis. The candidate exposes NO bootstrap writer.
  await pool.query('insert into master_device_enrollment_candidate.owner_issuer_heads(authority_id,epoch,pin) values($1,1,$2::jsonb)',[authorityId,JSON.stringify(pin)]);
  return {old,next,pin,external:checkpoint(pin)};
 }
 async function rotation(f,key=f.next,keyId='issuer_new'){
  const at=await now(),raw={version:1,authorityId:f.pin.authorityId,fromEpoch:f.pin.epoch,toEpoch:f.pin.epoch+1,previousSha256:f.pin.headSha256,
   oldKeyId:f.pin.keyId,newKeyId:keyId,newPublicKeyJwk:key.jwk,issuedMs:at,expiresMs:at+120000,oldSignature:'',newSignature:''};
  const payload=ownerIssuerContinuityPayload(raw),proposal={...raw,oldSignature:sign(null,payload,f.old.privateKey).toString('base64url'),newSignature:sign(null,payload,key.privateKey).toString('base64url')};
  const prepared=verifyOwnerIssuerContinuity({enabled:true,trusted:f.pin,authorityCheckpoint:f.external,proposal,databaseNowMs:at});assert.ok(prepared);
  return {proposal,prepared,args:{enabled:true,pool,authorityCheckpoint:f.external,proposal}};
 }
 const head=async authorityId=>(await pool.query('select epoch,pin from master_device_enrollment_candidate.owner_issuer_heads where authority_id=$1',[authorityId])).rows[0];
 const count=async authorityId=>Number((await pool.query('select count(*) as n from master_device_enrollment_candidate.owner_issuer_transitions where authority_id=$1',[authorityId])).rows[0].n);
 async function request(){
  const device={id:deviceId,master_user_id:actor,is_locked:false,revoked_at:null},key=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),publicKeyPem=key.publicKey.export({type:'spki',format:'pem'}).toString();
  const p=pendingDeviceKeyMigration({actor,device,publicKeyPem}),createdMs=await now(),expiresMs=createdMs+120000;
  const row=(await pool.query(`insert into master_device_enrollment_candidate.key_possession_challenges(actor,session_id,device_id,key_sha256,nonce,created_ms,expires_ms)
   values($1,$2,$3,$4,$5,$6,$7) returning id`,[actor,session,deviceId,p.key_sha256,randomBytes(32).toString('hex'),createdMs,expiresMs])).rows[0];
  const challenge=(await pool.query(`select id,actor,session_id as session,device_id as "deviceId",key_sha256 as "keySha256",nonce,created_ms as "createdMs",expires_ms as "expiresMs",false as consumed
   from master_device_enrollment_candidate.key_possession_challenges where id=$1`,[row.id])).rows[0];
  const args={pool:fixturePool,actor,session,deviceId,challengeId:row.id,publicKeyPem,signature:sign('sha256',migrationPossessionPayload(challenge,p),key.privateKey)};
  const pending=await storeProvenPendingDeviceKey(args),owner=await requestIndependentOwnerApproval({...args,pendingId:pending.id});return owner.id;
 }
 async function evidence(requestId,key,keyId,external,poolOverride=fixturePool){
  const row=(await pool.query('select * from master_device_enrollment_candidate.owner_approval_requests where id=$1',[requestId])).rows[0];const at=await now();
  const unsigned={version:1,issuerKeyId:keyId,decision:'approved',requestId,actor,requesterSession:session,deviceId,pendingId:row.pending_id,challengeId:row.challenge_id,keySha256:row.key_sha256,reviewNonce:row.review_nonce,issuedMs:at,expiresMs:Math.min(row.expires_ms,at+60000)};
  const receipt={...unsigned,signature:sign(null,ownerDecisionPayload(unsigned),key.privateKey).toString('base64url')};
  return {enabled:true,pool:poolOverride,actor,session,requestId,receipt,authorityCheckpoint:external};
 }
 async function httpEvidence(args,{enabled=true,action='owner-evidence',external=args.authorityCheckpoint,extra={},mutateContext=false,fixedPin,checkpointUnavailable=false}={}){
  const token='synthetic-owner-evidence-auth-token',context={actor,session,pool:args.pool};let checkpointCalls=0;
  const response=await handleMigrationChallengeRequest(new Request('https://fixture.invalid/master/migration',{
   method:'POST',headers:{authorization:`Bearer ${token}`,'content-type':'application/json'},
   body:JSON.stringify({action,requestId:args.requestId,receipt:args.receipt,...extra})}),{
   authenticateBearer:async bearer=>{assert.equal(bearer,token);return context;},
   ownerEvidence:{enabled,pinnedIssuer:fixedPin,loadAuthorityCheckpoint:async who=>{
    checkpointCalls++;assert.equal(who.actor,actor);assert.equal(who.session,session);assert.ok(Object.isFrozen(who));
    if(mutateContext){context.actor=id(999);context.session=id(998);}if(checkpointUnavailable)throw Error('fixture external checkpoint unavailable');return external;
   }},
  });
  return {response,checkpointCalls};
 }
 let calls=0;const forbiddenPool={connect:async()=>{calls++;throw Error('OFF must not acquire');}};
 await assert.rejects(commitOwnerIssuerTransition({pool:forbiddenPool}));
 await assert.rejects(recordOwnerDecisionUsingStoredIssuer({pool:forbiddenPool}));assert.equal(calls,0);
 const f=await seed(),r=await rotation(f),firstRequest=await request(),oldReceipt=await evidence(firstRequest,f.old,f.pin.keyId,f.external);
 const off=await httpEvidence(oldReceipt,{enabled:false});assert.equal(off.response.status,503);assert.equal(off.checkpointCalls,0);
 const admitted=await httpEvidence(oldReceipt,{mutateContext:true});assert.equal(admitted.response.status,200);
 assert.equal((await admitted.response.json()).evidence.status,'evidence_recorded');
 assert.equal(admitted.response.headers.get('cache-control'),'no-store');
 for(const extra of [{issuerMode:'fixed'},{authorityCheckpoint:f.external},{pinnedIssuer:{keyId:'issuer_old',publicKeyJwk:f.old.jwk}}]){
  const spoofed=await httpEvidence(oldReceipt,{extra});assert.equal(spoofed.response.status,400);assert.equal(spoofed.checkpointCalls,0);
 }
 assert.equal((await commitOwnerIssuerTransition(r.args)).status,'transition_committed');
 assert.deepEqual((await head(f.pin.authorityId)).pin,r.prepared.next);assert.equal(await count(f.pin.authorityId),1);
 const saved=(await pool.query('select * from master_device_enrollment_candidate.owner_issuer_transitions where authority_id=$1',[f.pin.authorityId])).rows[0];
 const payload=Buffer.from(saved.signed_payload),oldSig=Buffer.from(saved.old_signature),newSig=Buffer.from(saved.new_signature);
 assert.equal(verify(null,payload,f.old.publicKey,oldSig),true);assert.equal(verify(null,payload,f.next.publicKey,newSig),true);
 assert.deepEqual(saved.old_pin,f.pin);assert.deepEqual(saved.new_pin,r.prepared.next);assert.deepEqual(saved.authority_checkpoint,f.external);
 assert.equal(createHash('sha256').update(payload).update(oldSig).update(newSig).digest('hex'),saved.head_sha256);
 await assert.rejects(commitOwnerIssuerTransition(r.args),'replay cannot write again');
 await assert.rejects(commitOwnerIssuerTransition((await rotation(f,pair(),'fork')).args),'stale sibling fork cannot overwrite');
 assert.equal(await count(f.pin.authorityId),1);
 const externalNext=checkpoint(r.prepared.next),secondRequest=await request();
 assert.equal((await httpEvidence(oldReceipt,{external:externalNext,fixedPin:{purpose:f.pin.purpose,keyId:f.pin.keyId,publicKeyJwk:f.old.jwk}})).response.status,409,'handler cannot fall back to a configured fixed pin after rotation');
 assert.equal((await httpEvidence(await evidence(secondRequest,f.old,'issuer_old',externalNext))).response.status,409,'retired issuer cannot admit a new receipt');
 assert.equal((await httpEvidence(await evidence(secondRequest,f.next,'issuer_new',f.external))).response.status,409,'stale checkpoint cannot select a retired pin');
 const current=await httpEvidence(await evidence(secondRequest,f.next,'issuer_new',externalNext));assert.equal(current.response.status,200);
 assert.equal((await current.response.json()).evidence.status,'evidence_recorded');
 // The actual consumer must validate stored retired history, not just current
 // key/head metadata, against the independently supplied checkpoint.
 const corrupted={...r.prepared.next,retiredKeys:[{epoch:1,keyId:'fake_retired',publicKeyJwk:pair().jwk}]};
 await pool.query('update master_device_enrollment_candidate.owner_issuer_heads set pin=$2::jsonb where authority_id=$1',[f.pin.authorityId,JSON.stringify(corrupted)]);
 assert.equal((await httpEvidence(await evidence(secondRequest,f.next,'issuer_new',externalNext))).response.status,409);
 await pool.query('update master_device_enrollment_candidate.owner_issuer_heads set pin=$2::jsonb where authority_id=$1',[f.pin.authorityId,JSON.stringify(r.prepared.next)]);
 const oldEvidence=(await pool.query('select attestation_payload,attestation_signature from master_device_enrollment_candidate.owner_decision_evidence where request_id=$1',[firstRequest])).rows[0];
 assert.equal(verify(null,Buffer.from(oldEvidence.attestation_payload),f.old.publicKey,Buffer.from(oldEvidence.attestation_signature)),true,'historical original remains verifiable');
 // Simulate a real DB commit whose ACK is lost before the handler can respond.
 // The follow-up action only reads the exact original; it never retries writing.
 let lostAck=false;
 const lossPool={connect:async()=>{const c=await fixturePool.connect();return {release:()=>c.release(),query:async(sql,args)=>{
  const result=await c.query(sql,args);if(sql==='commit'&&!lostAck){lostAck=true;throw Error('synthetic lost commit ACK');}return result;
 }};}};
 const uncertainId=await request(),uncertain=await evidence(uncertainId,f.next,'issuer_new',externalNext,lossPool);
 assert.equal((await httpEvidence(uncertain)).response.status,409);assert.equal(lostAck,true);
 assert.equal(Number((await pool.query('select count(*) as n from master_device_enrollment_candidate.owner_decision_evidence where request_id=$1',[uncertainId])).rows[0].n),1);
 const lookupQueries=[];
 const lookupPool={connect:async()=>{const c=await fixturePool.connect();return {release:()=>c.release(),query:(sql,args)=>{lookupQueries.push(sql);return c.query(sql,args);}};}};
 const lookupArgs={...uncertain,pool:lookupPool};
 const lookup=await httpEvidence(lookupArgs,{action:'owner-evidence-result',checkpointUnavailable:true});
 assert.equal(lookup.response.status,200);assert.equal(lookup.checkpointCalls,0);
 const reconciled=(await lookup.response.json()).evidenceResult;assert.equal(reconciled.status,'evidence_recorded');assert.equal(reconciled.requestState,'awaiting_independent_owner');
 assert.equal(lookup.response.headers.get('cache-control'),'no-store');
 assert.equal(lookupQueries.some(sql=>/^\s*(insert|update|delete|truncate)\b/i.test(sql)),false,'lookup may not mutate or retry evidence');
 assert.equal(Number((await pool.query('select count(*) as n from master_device_enrollment_candidate.owner_decision_evidence where request_id=$1',[uncertainId])).rows[0].n),1);
 const offLookup=await httpEvidence(lookupArgs,{action:'owner-evidence-result',enabled:false});assert.equal(offLookup.response.status,503);
 const changedSignature=Buffer.from(uncertain.receipt.signature,'base64url');changedSignature[0]^=1;
 for(const patch of [{signature:changedSignature.toString('base64url')},{decision:'denied'},{reviewNonce:'0'.repeat(64)},{actor:id(9)},{requesterSession:id(999)}]){
  assert.equal((await httpEvidence({...lookupArgs,receipt:{...uncertain.receipt,...patch}},{action:'owner-evidence-result'})).response.status,409);
 }
 const absentId=await request(),absent=await evidence(absentId,f.next,'issuer_new',externalNext);
 const unconfirmed=await httpEvidence(absent,{action:'owner-evidence-result'});assert.equal(unconfirmed.response.status,200);
 assert.equal((await unconfirmed.response.json()).evidenceResult.status,'evidence_unconfirmed','absence is not permission to replay or a definitive rollback');
 await cancelIndependentOwnerApprovalRequest({pool:fixturePool,actor,session,requestId:uncertainId});
 const withdrawn=await httpEvidence(lookupArgs,{action:'owner-evidence-result'});assert.equal(withdrawn.response.status,200);
 assert.equal((await withdrawn.response.json()).evidenceResult.requestState,'cancelled');
 assert.equal((await httpEvidence({...uncertain,pool:fixturePool})).response.status,409,'readback cannot revive a withdrawn request');
 // Reconciliation remains historical after issuer retirement and fixture expiry.
 await pool.query(`update master_device_enrollment_candidate.key_possession_challenges
  set created_ms=floor(extract(epoch from clock_timestamp())*1000)-120000,
   expires_ms=floor(extract(epoch from clock_timestamp())*1000)-60000 where id=$1`,[oldReceipt.receipt.challengeId]);
 await pool.query(`update master_device_enrollment_candidate.owner_approval_requests set expires_ms=
  (select expires_ms from master_device_enrollment_candidate.key_possession_challenges where id=$1) where id=$2`,[oldReceipt.receipt.challengeId,firstRequest]);
 const historical=await httpEvidence(oldReceipt,{action:'owner-evidence-result',checkpointUnavailable:true});assert.equal(historical.response.status,200);
 const historicalResult=(await historical.response.json()).evidenceResult;assert.equal(historicalResult.status,'evidence_recorded');assert.equal(historicalResult.requestState,'expired');
 const preserved=(await pool.query('select attestation_payload,attestation_signature from master_device_enrollment_candidate.owner_decision_evidence where request_id=$1',[firstRequest])).rows[0];
 assert.deepEqual(preserved,oldEvidence,'historical lookup preserves original bytes');
 for(const sql of ['update master_device_enrollment_candidate.owner_issuer_transitions set previous_sha256=previous_sha256','delete from master_device_enrollment_candidate.owner_issuer_transitions','truncate master_device_enrollment_candidate.owner_issuer_transitions'])await assert.rejects(pool.query(sql),e=>e.code==='55000');
 for(const role of ['anon','authenticated','service_role'])for(const table of ['owner_issuer_heads','owner_issuer_transitions']){
  const c=await pool.connect();try{await c.query('begin');await c.query('set local role '+role);await assert.rejects(c.query('select * from master_device_enrollment_candidate.'+table),e=>e.code==='42501');}finally{await c.query('rollback');c.release();}
 }
 const rollback=await seed(),failed=await rotation(rollback);
 await pool.query(`create function master_device_enrollment_candidate.reject_issuer_cas_fixture() returns trigger language plpgsql as $$ begin raise exception 'synthetic final CAS failure';end $$;
  create trigger reject_issuer_cas_fixture before update on master_device_enrollment_candidate.owner_issuer_heads for each row execute function master_device_enrollment_candidate.reject_issuer_cas_fixture()`);
 await assert.rejects(commitOwnerIssuerTransition(failed.args));assert.equal(await count(rollback.pin.authorityId),0);assert.deepEqual((await head(rollback.pin.authorityId)).pin,rollback.pin);
 await pool.query('drop trigger reject_issuer_cas_fixture on master_device_enrollment_candidate.owner_issuer_heads');
 const cas=await seed(),casChange=await rotation(cas);let unexpectedChange=false;
 const casPool={connect:async()=>{const c=await pool.connect();return {release:()=>c.release(),query:async(sql,args)=>{
  if(sql.startsWith('update master_device_enrollment_candidate.owner_issuer_heads')&&!unexpectedChange){
   unexpectedChange=true;await c.query("update master_device_enrollment_candidate.owner_issuer_heads set pin=pin||jsonb_build_object('headSha256',$2::text) where authority_id=$1",[cas.pin.authorityId,'b'.repeat(64)]);
  }return c.query(sql,args);
 }};}};
 await assert.rejects(commitOwnerIssuerTransition({...casChange.args,pool:casPool}),'full-pin CAS must refuse unexpected in-transaction state changes');
 assert.equal(unexpectedChange,true);assert.equal(await count(cas.pin.authorityId),0);assert.deepEqual((await head(cas.pin.authorityId)).pin,cas.pin);
 const mutable=await seed(),change=await rotation(mutable),proposal=structuredClone(change.proposal),external=structuredClone(mutable.external);
 const racedPool={connect:async()=>{proposal.newKeyId='changed';proposal.newPublicKeyJwk.x='x'.repeat(43);external.publicKeySha256='b'.repeat(64);return pool.connect();}};
 await commitOwnerIssuerTransition({...change.args,pool:racedPool,proposal,authorityCheckpoint:external});
 assert.deepEqual((await head(mutable.pin.authorityId)).pin,change.prepared.next,'pre-await snapshots bind the committed transition');
 const receiptRequest=await request(),rawReceipt=await evidence(receiptRequest,f.next,'issuer_new',structuredClone(externalNext));
 const originalSignature=rawReceipt.receipt.signature;
 const mutationPool={connect:async()=>{rawReceipt.receipt.signature='x'.repeat(86);rawReceipt.authorityCheckpoint.retiredKeysSha256='b'.repeat(64);return fixturePool.connect();}};
 assert.equal((await recordOwnerDecisionUsingStoredIssuer({...rawReceipt,pool:mutationPool})).status,'evidence_recorded');
 assert.deepEqual(Buffer.from((await pool.query('select attestation_signature from master_device_enrollment_candidate.owner_decision_evidence where request_id=$1',[receiptRequest])).rows[0].attestation_signature),Buffer.from(originalSignature,'base64url'));
 if(nativeConcurrency){
  const concurrent=await seed(),a=await rotation(concurrent),b=await rotation(concurrent,pair(),'fork_other');
  const attempts=await Promise.allSettled([commitOwnerIssuerTransition(a.args),commitOwnerIssuerTransition(b.args)]);
  assert.equal(attempts.filter(x=>x.status==='fulfilled').length,1);assert.equal(attempts.filter(x=>x.status==='rejected').length,1);assert.equal(await count(concurrent.pin.authorityId),1);
  const identical=await seed(),same=await rotation(identical),duplicates=await Promise.allSettled([commitOwnerIssuerTransition(same.args),commitOwnerIssuerTransition(same.args)]);
  assert.equal(duplicates.filter(x=>x.status==='fulfilled').length,1);assert.equal(duplicates.filter(x=>x.status==='rejected').length,1);assert.equal(await count(identical.pin.authorityId),1);
  const ordered=await seed(),turn=await rotation(ordered),requestId=await request();
  let releaseReceipt,receivedLock,rotationStarted,rotationPid;
  const release=new Promise(resolve=>{releaseReceipt=resolve;}),locked=new Promise(resolve=>{receivedLock=resolve;}),started=new Promise(resolve=>{rotationStarted=resolve;});
  const receiptPool={connect:async()=>{const c=await fixturePool.connect();return {release:()=>c.release(),query:async(sql,args)=>{
   if(sql.startsWith('select auth.uid() as actor')){receivedLock();await release;}return c.query(sql,args);
  }};}};
  const rotationPool={connect:async()=>{const c=await pool.connect();rotationPid=(await c.query('select pg_backend_pid() as pid')).rows[0].pid;return {release:()=>c.release(),query:(sql,args)=>{
   const pending=c.query(sql,args);if(sql.includes('owner_issuer_heads')&&sql.includes('for update'))rotationStarted();return pending;
  }};}};
  const receiptAttempt=recordOwnerDecisionUsingStoredIssuer(await evidence(requestId,ordered.old,'issuer_old',ordered.external,receiptPool));
  await locked;const rotationAttempt=commitOwnerIssuerTransition({...turn.args,pool:rotationPool});await started;
  let waiting=false;
  try{for(let i=0;i<100;i++){waiting=(await pool.query("select wait_event_type='Lock' as waiting from pg_stat_activity where pid=$1",[rotationPid])).rows[0]?.waiting===true;if(waiting)break;await new Promise(resolve=>setTimeout(resolve,10));}
   assert.equal(waiting,true,'rotation must wait for the issuer lock held by the actual receipt transaction');
  }finally{releaseReceipt();}
  assert.equal((await receiptAttempt).status,'evidence_recorded');assert.equal((await rotationAttempt).status,'transition_committed');
  assert.equal((await head(ordered.pin.authorityId)).epoch,2);
 }
 assert.equal((await pool.query('select device_key from private.master_devices where id=$1',[deviceId])).rows[0].device_key,'legacy-original');
 assert.equal(Number((await pool.query('select count(*) as n from private.master_devices')).rows[0].n),1);
 assert.equal(Number((await pool.query("select count(*) as n from master_device_enrollment_candidate.pending_key_migrations where status<>'pending'")).rows[0].n),0);
 console.log('Issuer persistence: OFF, exact checkpoint, atomic signed-history/CAS, replay/fork refusal, rollback, snapshots, append-only/ACL, actual HTTP-to-current-issuer receipt/no fixed-pin fallback, lost-commit ACK exact readback/no writes, historical cancelled/expired result and unchanged devices passed. Synthetic authority/Auth fixtures only.');
 if(nativeConcurrency)console.log('Native separate-connection forks/duplicate transitions and receipt-vs-rotation lock ordering passed.');
}
