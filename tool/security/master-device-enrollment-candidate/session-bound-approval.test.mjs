import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { generateKeyPairSync, sign } from 'node:crypto';
import { sessionBoundApprovalPayload, verifySessionBoundApproval } from './session-bound-approval.mjs';
const uid = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
test('approval signature is limited to the authenticated approving session', () => {
  const {privateKey,publicKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
  const intent={id:uid(1),actor:uid(2),requesterSession:uid(3),deviceKeyHash:'a'.repeat(64),nonce:'b'.repeat(64),deviceType:'ipad',createdMs:1000,expiresMs:61000,consumed:false};
  const device={id:uid(4),actor:uid(2),active:true,publicKeyPem:publicKey.export({type:'spki',format:'pem'})};
  const session=uid(5), signature=sign('sha256',sessionBoundApprovalPayload(intent,device,session),privateKey);
  const args={intent,device,approvingSession:session,sessionActor:uid(2),sessionActive:true,signature,nowMs:2000};
  assert.equal(verifySessionBoundApproval(args),true);
  assert.equal(verifySessionBoundApproval({...args,approvingSession:uid(6)}),false);
  assert.equal(verifySessionBoundApproval({...args,sessionActive:false}),false);
  assert.equal(verifySessionBoundApproval({...args,sessionActor:uid(6)}),false);
  assert.equal(verifySessionBoundApproval({...args,nowMs:61000}),false);
  assert.equal(verifySessionBoundApproval({...args,intent:{...intent,nonce:'c'.repeat(64)}}),false);
});
