import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash,generateKeyPairSync} from 'node:crypto';
import {handleMigrationChallengeRequest} from './key-migration-challenge-http-candidate.mjs';
const actor='00000000-0000-0000-0000-000000000001',session='00000000-0000-0000-0000-000000000002',deviceId='00000000-0000-0000-0000-000000000003';
const publicKeyPem=generateKeyPairSync('ec',{namedCurve:'prime256v1'}).publicKey.export({type:'spki',format:'pem'}).toString();
const token='synthetic-token-not-a-real-jwt';
const body={action:'issue',deviceId,publicKeyPem,secondPassword:'synthetic-wrong'};
const request=(value=body,extra={})=>new Request('https://fixture.invalid/challenge',{method:'POST',headers:{authorization:`Bearer ${token}`,'content-type':'application/json'},body:JSON.stringify(value),...extra});
function fixture({read=false,fail=false}={}) {
 const calls=[];
 const challenge={id:'00000000-0000-0000-0000-000000000004',actor,session,deviceId,keySha256:createHash('sha256').update(publicKeyPem).digest('hex'),nonce:'a'.repeat(64),createdMs:1000,expiresMs:61000,consumed:false};
 const pool={connect:async()=>({release:()=>{},query:async(sql,args)=>{
  calls.push({sql,args});if(fail)throw Error('synthetic credential MUST NOT LEAK');
  if(sql.includes('select auth.uid()'))return {rows:[{actor,session,master:true}]};
  if(sql.includes('verify_secondary_password'))return {rows:[{verified:false}]};
  if(sql.includes('from private.master_devices'))return {rows:[{id:deviceId,master_user_id:actor,is_locked:false,revoked_at:null}]};
  if(sql.includes('join master_device_enrollment_candidate.pending_key_migrations')&&read)return {rows:[{id:'00000000-0000-0000-0000-000000000005',status:'pending'}]};
  if(sql.includes('from master_device_enrollment_candidate.key_possession_challenges')&&read)return {rows:[challenge]};
  return {rows:[]};
 }})};
 return {calls,challenge,authenticateBearer:async received=>{assert.equal(received,token);return {actor,session,pool};}};
}
test('wrong second password commits existing verifier counter without delivering a challenge',async()=>{
 const f=fixture(),r=await handleMigrationChallengeRequest(request(),f);
 assert.equal(r.status,403);assert.deepEqual(await r.json(),{accepted:false});
 assert.ok(f.calls.some(x=>x.sql==='commit'));assert.ok(!f.calls.some(x=>x.sql.includes('insert into')));
 assert.equal(r.headers.get('cache-control'),'no-store');
 assert.equal(f.calls.filter(x=>x.sql.includes('verify_secondary_password')).length,1);
});
test('readback uses only authenticated identity and returns the original nonce',async()=>{
 const f=fixture({read:true});const r=await handleMigrationChallengeRequest(request({action:'read',deviceId,publicKeyPem}),f);
 assert.equal(r.status,200);assert.deepEqual(await r.json(),{accepted:true,challenge:f.challenge});
 assert.ok(!f.calls.some(x=>x.sql.includes('insert into')||x.sql.includes('verify_secondary_password')));
});
test('body identity, extra password on read, malformed and oversized bodies cannot reach database',async()=>{
 for(const value of [{...body,actor},{action:'read',deviceId,publicKeyPem,secondPassword:'secret'},null,[],{...body,publicKeyPem:'x'.repeat(9000)}]){
  const f=fixture();const r=await handleMigrationChallengeRequest(request(value),f);
  assert.equal(r.status,400);assert.equal(f.calls.length,0);
 }
});
test('HTTPS POST and verified authentication are required before database access',async()=>{
 const f=fixture();
 assert.equal((await handleMigrationChallengeRequest(new Request('http://fixture.invalid/challenge'),f)).status,400);
 assert.equal((await handleMigrationChallengeRequest(request(body,{headers:{'content-type':'application/json'}}),f)).status,401);
 assert.equal((await handleMigrationChallengeRequest(request(),{authenticateBearer:async()=>null})).status,401);
 assert.equal(f.calls.length,0);
});
test('database failures are generic and never expose credentials or retry a write',async()=>{
 const f=fixture({fail:true});const r=await handleMigrationChallengeRequest(request(),f);
 assert.equal(r.status,409);assert.ok(!(await r.text()).includes('MUST NOT LEAK'));
 assert.equal(f.calls.filter(x=>x.sql==='begin').length,1);
});
test('unresponsive authentication is bounded without retry',async()=>{
 let calls=0;const r=await handleMigrationChallengeRequest(request(),{timeoutMs:10,authenticateBearer:()=>{calls++;return new Promise(()=>{});}});
 assert.equal(r.status,409);assert.equal(calls,1);
});
test('status returns only an original pending receipt, never the consumed nonce',async()=>{
 const f=fixture({read:true});
 const r=await handleMigrationChallengeRequest(request({action:'status',deviceId,publicKeyPem,challengeId:f.challenge.id}),f);
 assert.equal(r.status,200);assert.deepEqual(await r.json(),{accepted:true,submission:{id:'00000000-0000-0000-0000-000000000005',status:'pending'}});
 assert.ok(!f.calls.some(x=>/^(insert|update|delete)/.test(x.sql)));
});
test('submit requires a canonical bounded DER transport and cannot accept body identity',async()=>{
 for(const extra of [{signature:'abcd==='},{signature:'x'.repeat(109)},{signature:'YQ=='},{signature:'YQ'},{signature:'AAAAAAAAAAA=',actor}]) {
  const f=fixture();
  const r=await handleMigrationChallengeRequest(request({action:'submit',deviceId,publicKeyPem,challengeId:f.challenge.id,...extra}),f);
  assert.equal(r.status,400);assert.equal(f.calls.length,0);
 }
});
const ownerRequestId='00000000-0000-0000-0000-000000000008';
const ownerBody={action:'owner-evidence',requestId:ownerRequestId,receipt:{requestId:ownerRequestId}};
test('owner evidence defaults OFF and cannot use a configured fixed pin',async()=>{
 const f=fixture();let checkpoints=0;
 const r=await handleMigrationChallengeRequest(request(ownerBody),{...f,ownerEvidence:{pinnedIssuer:{keyId:'old'},loadAuthorityCheckpoint:async()=>{checkpoints++;return {};}}});
 assert.equal(r.status,503);assert.equal(checkpoints,0);assert.equal(f.calls.length,0);
});
test('enabled owner evidence fails closed without a server checkpoint adapter, never fixed-pin fallback',async()=>{
 const f=fixture();
 const r=await handleMigrationChallengeRequest(request(ownerBody),{...f,ownerEvidence:{enabled:true,pinnedIssuer:{keyId:'old'}}});
 assert.equal(r.status,503);assert.equal(f.calls.length,0);
});
test('body cannot choose issuer mode, pin, checkpoint, auth identity or pool',async()=>{
 for(const extra of [{issuerMode:'fixed'},{pinnedIssuer:{keyId:'old'}},{authorityCheckpoint:{}},{actor},{session},{pool:{}},{ownerEvidence:{enabled:true}}]){
  const f=fixture();let checkpoints=0;
  const r=await handleMigrationChallengeRequest(request({...ownerBody,...extra}),{...f,ownerEvidence:{enabled:true,loadAuthorityCheckpoint:async()=>{checkpoints++;return {};}}});
  assert.equal(r.status,400);assert.equal(checkpoints,0);assert.equal(f.calls.length,0);
 }
});
test('owner request/receipt mismatch is refused before checkpoint or database access',async()=>{
 const f=fixture();let calls=0;
 const r=await handleMigrationChallengeRequest(request({...ownerBody,receipt:{requestId:deviceId}}),{...f,ownerEvidence:{enabled:true,loadAuthorityCheckpoint:async()=>{calls++;return {};}}});
 assert.equal(r.status,400);assert.equal(calls,0);assert.equal(f.calls.length,0);
});
test('checkpoint failure stays generic and cannot fall back to a fixed issuer',async()=>{
 const f=fixture();let calls=0;
 const r=await handleMigrationChallengeRequest(request(ownerBody),{...f,ownerEvidence:{enabled:true,pinnedIssuer:{keyId:'old'},loadAuthorityCheckpoint:async()=>{calls++;throw Error('private authority detail MUST NOT LEAK');}}});
 assert.equal(r.status,409);assert.ok(!(await r.text()).includes('MUST NOT LEAK'));assert.equal(calls,1);assert.equal(f.calls.length,0);
});
test('captured checkpoint adapter cannot be replaced during authentication',async()=>{
 const f=fixture();let original=0,replaced=0;
 const config={enabled:true,loadAuthorityCheckpoint:async args=>{original++;assert.equal(args.actor,actor);assert.equal(args.session,session);assert.ok(Object.isFrozen(args));return {};}};
 const authenticateBearer=async value=>{config.loadAuthorityCheckpoint=async()=>{replaced++;return {};};return f.authenticateBearer(value);};
 const r=await handleMigrationChallengeRequest(request(ownerBody),{authenticateBearer,ownerEvidence:config});
 assert.equal(r.status,409);assert.equal(original,1);assert.equal(replaced,0);assert.equal(f.calls.length,0);
});
test('late checkpoint completion cannot start evidence recording after HTTP deadline',async()=>{
 const f=fixture();let calls=0,resolveCheckpoint;
 const pending=new Promise(resolve=>{resolveCheckpoint=resolve;});
 const r=await handleMigrationChallengeRequest(request(ownerBody),{...f,timeoutMs:10,ownerEvidence:{enabled:true,loadAuthorityCheckpoint:async({signal})=>{calls++;assert.equal(signal.aborted,false);return pending;}}});
 assert.equal(r.status,409);resolveCheckpoint({});await new Promise(resolve=>setTimeout(resolve,10));
 assert.equal(calls,1);assert.equal(f.calls.length,0);
});
