import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { approvalPayload } from './approval-signature.mjs';
import { issueVerifiedApproval } from './verified-approval.mjs';

test('trusted signature, current session, exact binding and atomic claim are required', async()=>{
  const keys=generateKeyPairSync('ec',{namedCurve:'prime256v1'}), now=1700000000000;
  const actor='00000000-0000-0000-0000-000000000002',session='00000000-0000-0000-0000-000000000003';
  const intent={id:'00000000-0000-0000-0000-000000000001',actor,requesterSession:session,deviceKeyHash:'a'.repeat(64),nonce:'b'.repeat(64),createdMs:now,expiresMs:now+120000,consumed:false};
  const device={id:'00000000-0000-0000-0000-000000000004',actor,active:true,publicKeyPem:keys.publicKey.export({type:'spki',format:'pem'})};
  const signature=sign('sha256',approvalPayload(intent,device),keys.privateKey);
  let claimed=false;
  const context={sessionActive:true,master:true,sessionActor:actor,sessionId:session,intent,device};
  const adapter={loadTrustedContext:async()=>context,claimVerifiedApproval:async(v)=>{
    if(claimed||v.expectedDevice.active!==true||v.expectedIntent.consumed!==false)return false;
    claimed=true;return /^[0-9a-f]{64}$/.test(v.tokenHash);
  }};
  const args={adapter,actor,session,intentId:intent.id,deviceId:device.id,signature,nowMs:now+1};
  for (const changes of [{sessionActive:false},{master:false},{sessionActor:'other'}, {device:{...device,active:false}}, {intent:{...intent,nonce:'c'.repeat(64)}}]) {
    Object.assign(context,changes);
    assert.equal(await issueVerifiedApproval(args),null);
    Object.assign(context,{sessionActive:true,master:true,sessionActor:actor,device,intent});
  }
  assert.match(await issueVerifiedApproval(args),/^[0-9a-f]{64}$/);
  assert.equal(await issueVerifiedApproval(args),null);
});
