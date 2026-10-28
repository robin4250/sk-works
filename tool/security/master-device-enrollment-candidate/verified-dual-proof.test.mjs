import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash,generateKeyPairSync,sign} from 'node:crypto';
import {approvalPayload} from './approval-signature.mjs';
import {sessionBoundApprovalPayload} from './session-bound-approval.mjs';
import {issueDualProofApproval} from './verified-dual-proof.mjs';

test('both registered and requesting devices sign the same intent before one atomic claim',async()=>{
  const old=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),fresh=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),now=1700000000000;
  const actor='00000000-0000-0000-0000-000000000002',session='00000000-0000-0000-0000-000000000003';
  const pem=fresh.publicKey.export({type:'spki',format:'pem'});
  const intent={id:'00000000-0000-0000-0000-000000000001',actor,requesterSession:'00000000-0000-0000-0000-000000000005',deviceKeyHash:createHash('sha256').update(pem).digest('hex'),deviceType:'ipad',nonce:'b'.repeat(64),createdMs:now,expiresMs:now+120000,consumed:false};
  const device={id:'00000000-0000-0000-0000-000000000004',actor,active:true,publicKeyPem:old.publicKey.export({type:'spki',format:'pem'})};
  const payload=approvalPayload(intent,device);
  const approvingSignature=sign('sha256',sessionBoundApprovalPayload(intent,device,session),old.privateKey),newSignature=sign('sha256',Buffer.concat([Buffer.from('sko-master-new-device-proof-v1\n'),payload]),fresh.privateKey);
  let used=false,claims=0,databaseNowMs=now+1;
  const adapter={loadTrustedContext:async()=>({sessionActive:true,master:true,sessionActor:actor,sessionId:session,intent,device,databaseNowMs}),claimVerifiedApproval:async args=>{claims++;if(used||args.expectedNewPublicKeyPem!==pem)return false;used=true;return true;}};
  const args={adapter,actor,session,intentId:intent.id,deviceId:device.id,approvingSignature,newPublicKeyPem:pem,newSignature,nowMs:now+1};
  assert.equal(await issueDualProofApproval({...args,newSignature:approvingSignature}),null);
  assert.equal(await issueDualProofApproval({...args,approvingSignature:newSignature}),null);
  databaseNowMs=intent.expiresMs;
  assert.equal(await issueDualProofApproval({...args,nowMs:now+1}),null);
  databaseNowMs=undefined;
  assert.equal(await issueDualProofApproval(args),null);
  databaseNowMs=now+1;
  assert.equal(await issueDualProofApproval({...args,approvingSignature:sign('sha256',payload,old.privateKey)}),null);
  assert.equal(claims,0);
  const results=await Promise.all(Array.from({length:6},()=>issueDualProofApproval(args)));
  assert.equal(results.filter(Boolean).length,1);
  assert.match(results.find(Boolean),/^[0-9a-f]{64}$/);
  assert.equal(await issueDualProofApproval({...args,session:'00000000-0000-0000-0000-000000000006'}),null);
});

test('approver signature cannot transfer across active owner sessions',async()=>{
  const old=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),fresh=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),now=1700000000000;
  const actor='00000000-0000-0000-0000-000000000002';
  const sessionA='00000000-0000-0000-0000-000000000003',sessionB='00000000-0000-0000-0000-000000000006';
  const pem=fresh.publicKey.export({type:'spki',format:'pem'});
  const intent={id:'00000000-0000-0000-0000-000000000001',actor,requesterSession:'00000000-0000-0000-0000-000000000005',deviceKeyHash:createHash('sha256').update(pem).digest('hex'),deviceType:'ipad',nonce:'b'.repeat(64),createdMs:now,expiresMs:now+120000,consumed:false};
  const device={id:'00000000-0000-0000-0000-000000000004',actor,active:true,publicKeyPem:old.publicKey.export({type:'spki',format:'pem'})};
  const payload=approvalPayload(intent,device);
  const approvingSignature=sign('sha256',sessionBoundApprovalPayload(intent,device,sessionA),old.privateKey),newSignature=sign('sha256',Buffer.concat([Buffer.from('sko-master-new-device-proof-v1\n'),payload]),fresh.privateKey);
  // Session B obtains the signatures but was not the session approved by the
  // trusted device. The same proof must fail before an atomic claim is attempted.
  let claims=0;
  const adapter={loadTrustedContext:async({session})=>({sessionActive:true,master:true,sessionActor:actor,sessionId:session,intent,device,databaseNowMs:now+1}),claimVerifiedApproval:async()=>{claims++;return true;}};
  const args={adapter,actor,intentId:intent.id,deviceId:device.id,approvingSignature,newPublicKeyPem:pem,newSignature,nowMs:now+1};
  assert.equal(await issueDualProofApproval({...args,session:sessionB}),null);
  assert.equal(claims,0);
  assert.ok(await issueDualProofApproval({...args,session:sessionA}));
  assert.equal(claims,1);
});
