// Disposable fixture only: actual TLS -> exact GoTrue -> existing PG adapters.
// The company permission source, privileged pool and admission decision remain
// explicit fixtures. No service is hosted or routed by production code.
import assert from 'node:assert/strict';
import {randomUUID,generateKeyPairSync,sign} from 'node:crypto';
import {createScannerRegistrationHttpsHandler} from './qr-scanner-registration-https.mjs';
import {createScannerTlsFixture} from './qr-scanner-registration-tls-fixture.mjs';
import {scannerRegistrationSigningBytes} from './qr-scanner-possession.mjs';

export async function exerciseScannerHttpsRegistration({db,pool,project,bridge,anon,makeUser,request,clean}){
 if(process.env.CI!=='true')throw Error('disposable TLS scanner fixture required');
 const manager=await makeUser(),stranger=await makeUser(),company=randomUUID(),device=randomUUID();
 const claims=token=>JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString('utf8'));
 await db.query('insert into public.companies values($1)',[company]);
 await db.query('insert into public.company_members values($1,$2)',[company,manager.user.id]);
 await db.query('insert into private.scanner_fixture_permissions values($1,$2)',[company,manager.user.id]);
 await db.query("insert into public.user_secondary_credentials values($1,extensions.crypt('synthetic-tls-password',extensions.gen_salt('bf',4)),0,null,clock_timestamp())",[manager.user.id]);
 const keys=generateKeyPairSync('ed25519'),publicKeyHex=keys.publicKey.export({format:'der',type:'spki'}).toString('hex');
 const scope={companyId:company,deviceId:device,publicKeyHex};let acquisitions=0,admitted=true;
 const admissions=[],requestPool={connect:async()=>{acquisitions++;return pool.connect();}};
 const f=await createScannerTlsFixture(publicOrigin=>createScannerRegistrationHttpsHandler({enabled:true,publicOrigin,
  projectOrigin:project,expectedIssuer:claims(manager.access_token).iss,publicKey:anon,pool:requestPool,fetchImpl:bridge,
  admitVerifiedRequest:async principal=>{assert.deepEqual(Object.keys(principal).sort(),['actor','operation','requestId','session']);
   admissions.push(principal);return admitted;}}),{dropReply:req=>req.headers['x-fixture-drop-ack']==='1'});
 const body=(operation,values)=>({schema:1,requestId:randomUUID(),operation,...values});
 const call=(value,token=manager.access_token,options={})=>f.call(value,{token,...options});
 const ownCounts=async()=>(await db.query('select (select count(*)::int from qr_attendance_private.scanner_registration_events where actor_id=$1) events,(select count(*)::int from qr_attendance_private.scanner_registration_receipts where actor_id=$1) receipts',[manager.user.id])).rows[0];
 try {
  await db.query("update private.master_feature_settings set enabled=false where feature_key='qr_attendance'");
  assert.notEqual((await call(body('challenge',scope))).status,200);await clean();
  await db.query("update private.master_feature_settings set enabled=true where feature_key='qr_attendance'");
  admitted=false;const before=acquisitions;
  assert.equal((await call(body('challenge',scope))).status,429);assert.equal(acquisitions,before);admitted=true;
  await assert.rejects(call(body('challenge',scope),manager.access_token,{headers:{'x-fixture-drop-ack':'1'}}));await clean();
  const challengeResponse=await call(body('challenge_result',scope));assert.equal(challengeResponse.status,200);
  assert.match(challengeResponse.headers['cache-control'],/no-store/);
  const challenge=challengeResponse.json.challenge;
  assert.equal(challenge.actor,manager.user.id);assert.equal(challenge.session,claims(manager.access_token).session_id);
  const original=(await db.query('select id,nonce,expires_ms::text expiry from qr_attendance_private.scanner_key_challenges where company_id=$1 and device_id=$2',[company,device])).rows;
  assert.equal(original.length,1);assert.equal(original[0].id,challenge.id);assert.equal(original[0].nonce,challenge.nonce);assert.equal(original[0].expiry,String(challenge.expiresMs));
  const wrong=await call(body('proof',{challengeId:challenge.id,password:'synthetic-wrong'}));
  assert.equal(wrong.status,200);assert.equal(wrong.json.accepted,false);assert.equal(wrong.text.includes('synthetic-wrong'),false);
  assert.equal((await db.query('select failed_attempts from public.user_secondary_credentials where user_id=$1',[manager.user.id])).rows[0].failed_attempts,1);await clean();
  // Separate actual challenge: the accepted raw proof is irretrievably lost.
  const lostScope={...scope,deviceId:randomUUID()},lostChallenge=(await call(body('challenge',lostScope))).json.challenge;
  const proofResult=body('proof_result',{challengeId:lostChallenge.id});
  assert.deepEqual((await call(proofResult)).json.issuance,{status:'not_found'});
  const beforeLostProof=await ownCounts();
  await assert.rejects(call(body('proof',{challengeId:lostChallenge.id,password:'synthetic-tls-password'}),manager.access_token,{headers:{'x-fixture-drop-ack':'1'}}));await clean();
  const markerCount=async()=>(await db.query('select count(*)::int n from qr_attendance_private.scanner_proof_issuance_receipts where challenge_id=$1',[lostChallenge.id])).rows[0].n;
  assert.equal(await markerCount(),1);
  const issuance=await call(proofResult);assert.equal(issuance.status,200);
  assert.deepEqual(issuance.json,{schema:1,requestId:proofResult.requestId,operation:'proof_result',issuance:{status:'committed_unrecoverable'}});
  assert.equal(issuance.text.includes('synthetic-tls-password')||issuance.text.includes(manager.access_token),false);
  assert.deepEqual((await call(proofResult)).json.issuance,{status:'committed_unrecoverable'});
  assert.equal(await markerCount(),1);assert.deepEqual(await ownCounts(),beforeLostProof);await clean();
  await db.query("update private.master_feature_settings set enabled=false where feature_key='qr_attendance'");
  assert.notEqual((await call(proofResult)).status,200);await clean();
  await db.query("update private.master_feature_settings set enabled=true where feature_key='qr_attendance'");
  await db.query('delete from private.scanner_fixture_permissions where company_id=$1 and user_id=$2',[company,manager.user.id]);
  assert.notEqual((await call(proofResult)).status,200);await clean();
  await db.query('insert into private.scanner_fixture_permissions values($1,$2)',[company,manager.user.id]);
  await db.query('update qr_attendance_private.scanner_key_challenges set created_ms=created_ms-100000,expires_ms=expires_ms-100000 where id=$1',[lostChallenge.id]);
  assert.deepEqual((await call(proofResult)).json.issuance,{status:'committed_unrecoverable'});await clean();

  assert.notEqual((await call(proofResult,stranger.access_token)).status,200);await clean();
  const proof=await call(body('proof',{challengeId:challenge.id,password:'synthetic-tls-password'}));
  assert.equal(proof.status,200);assert.equal(proof.json.accepted,true);assert.match(proof.json.proof,/^[0-9a-f]{64}$/);
  const command=body('complete',{challengeId:challenge.id,proof:proof.json.proof,
   signature:sign(null,scannerRegistrationSigningBytes(challenge),keys.privateKey).toString('base64url')});
  // Real TLS response is destroyed only after the underlying COMMIT succeeded.
  await assert.rejects(call(command,manager.access_token,{headers:{'x-fixture-drop-ack':'1'}}));await clean();
  assert.deepEqual(await ownCounts(),{events:1,receipts:1});
  const resultRequest=body('result',{...scope,challengeId:challenge.id});
  const result=await call(resultRequest);assert.equal(result.status,200);assert.equal(result.json.receipt.deviceId,device);
  assert.equal(result.json.requestId,resultRequest.requestId);assert.match(result.headers['cache-control'],/no-store/);
  assert.equal(result.text.includes(manager.access_token)||result.text.includes(proof.json.proof),false);await clean();
  const again=await call(body('result',{...scope,challengeId:challenge.id}));
  assert.deepEqual(again.json.receipt,result.json.receipt);assert.deepEqual(await ownCounts(),{events:1,receipts:1});
  assert.notEqual((await call(command)).status,200);assert.deepEqual(await ownCounts(),{events:1,receipts:1});await clean();
  assert.notEqual((await call(resultRequest,stranger.access_token)).status,200);await clean();
  const linkResponse=await request('/auth/v1/admin/generate_link',{admin:true,body:{type:'magiclink',email:manager.user.email}});
  assert.equal(linkResponse.status,200);const link=await linkResponse.json();
  const signedResponse=await request('/auth/v1/verify',{body:{type:'magiclink',token_hash:link.hashed_token}});
  assert.equal(signedResponse.status,200);const nextSid=await signedResponse.json();
  assert.equal(nextSid.user.id,manager.user.id);assert.notEqual(claims(nextSid.access_token).session_id,claims(manager.access_token).session_id);
  assert.notEqual((await call(proofResult,nextSid.access_token)).status,200);await clean();
  const otherSid=await call(resultRequest,nextSid.access_token);assert.equal(otherSid.status,200);assert.equal(otherSid.json.receipt,null);await clean();
  const parts=manager.access_token.split('.'),forged=[parts[0],Buffer.from(JSON.stringify({...claims(manager.access_token),sub:stranger.user.id})).toString('base64url'),parts[2]].join('.');
  const beforeTamper=acquisitions;assert.equal((await call(resultRequest,forged)).status,401);assert.equal(acquisitions,beforeTamper);await clean();
  await db.query('delete from auth.sessions where id=$1',[claims(manager.access_token).session_id]);
  assert.notEqual((await call(proofResult)).status,200);assert.equal(await markerCount(),1);await clean();
  assert.notEqual((await call(resultRequest)).status,200);assert.deepEqual(await ownCounts(),{events:1,receipts:1});await clean();
  assert.equal(admissions.every(p=>Object.isFrozen(p)),true);
  console.log('PASS actual TLS HTTP -> real GoTrue -> private PG challenge/password proof/PoP registration/receipt; dropped acknowledgement recovered without duplicate, foreign/otherSID/tampered/deletedSID denied, pooled claims cleared');
  console.log('PASS actual TLS lost raw password-proof acknowledgement -> exact-challenge immutable issuance evidence only; no raw proof, registration, reissue or other-actor/SID access');
  console.log('LIMIT synthetic business permission/admission and privileged fixture pool; no production listener, client key custody, ingress limits or canonical QR attendance writer');
 } finally {await f.close();}
}
