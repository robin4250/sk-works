import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync,sign } from 'node:crypto';
import { approvalPayload,verifyApprovalSignature } from './approval-signature.mjs';

test('owner device signs a bounded challenge and altered/replayed data is rejected',()=>{
  const {privateKey,publicKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
  const now=1700000000000;
  const intent={id:'00000000-0000-0000-0000-000000000001',actor:'00000000-0000-0000-0000-000000000002',
    requesterSession:'00000000-0000-0000-0000-000000000003',deviceKeyHash:'a'.repeat(64),
    nonce:'b'.repeat(64),createdMs:now,expiresMs:now+120000,consumed:false};
  const device={id:'00000000-0000-0000-0000-000000000004',actor:intent.actor,active:true,
    publicKeyPem:publicKey.export({type:'spki',format:'pem'})};
  const signature=sign('sha256',approvalPayload(intent,device),privateKey);
  const verify=(changes={})=>verifyApprovalSignature({intent,device,signature,nowMs:now+1,...changes});
  assert.equal(verify(),true);
  assert.equal(verify({intent:{...intent,deviceKeyHash:'c'.repeat(64)}}),false);
  assert.equal(verify({intent:{...intent,requesterSession:'00000000-0000-0000-0000-000000000005'}}),false);
  assert.equal(verify({intent:{...intent,consumed:true}}),false);
  assert.equal(verify({nowMs:now+120000}),false);
  assert.equal(verify({device:{...device,active:false}}),false);
  // Fail closed when an adapter supplies a missing or non-boolean state.
  for (const active of [undefined, null, 1, 'true']) {
    assert.equal(verify({device:{...device,active}}),false);
  }
  for (const consumed of [undefined, null, 0, 'false']) {
    assert.equal(verify({intent:{...intent,consumed}}),false);
  }
  assert.equal(verify({device:{...device,actor:'00000000-0000-0000-0000-000000000005'}}),false);
  assert.equal(verify({device:{...device,id:'00000000-0000-0000-0000-000000000005'}}),false);
  const attacker=generateKeyPairSync('ec',{namedCurve:'prime256v1'}).publicKey.export({type:'spki',format:'pem'});
  assert.equal(verify({device:{...device,publicKeyPem:attacker}}),false);
  assert.equal(verify({intent:{...intent,expiresMs:now+120001}}),false);
  assert.equal(verify({nowMs:now-1}),false);
  assert.equal(verify({signature:Buffer.from('not-a-signature')}),false);
});
