import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash,generateKeyPairSync,sign} from 'node:crypto';
import {approvalPayload} from './approval-signature.mjs';
import {verifyNewDeviceProof} from './new-device-proof.mjs';

test('new device must own the key bound to the exact server-issued challenge',()=>{
  const keys=generateKeyPairSync('ec',{namedCurve:'prime256v1'}), other=generateKeyPairSync('ec',{namedCurve:'prime256v1'}), now=1700000000000;
  const pem=keys.publicKey.export({type:'spki',format:'pem'});
  const intent={id:'00000000-0000-0000-0000-000000000001',actor:'00000000-0000-0000-0000-000000000002',requesterSession:'00000000-0000-0000-0000-000000000003',deviceKeyHash:createHash('sha256').update(pem).digest('hex'),deviceType:'ipad',nonce:'b'.repeat(64),createdMs:now,expiresMs:now+120000,consumed:false};
  const approvingDevice={id:'00000000-0000-0000-0000-000000000004'};
  const payload=Buffer.concat([Buffer.from('sko-master-new-device-proof-v1\n'),approvalPayload(intent,approvingDevice)]);
  const signature=sign('sha256',payload,keys.privateKey);
  const a={intent,approvingDevice,newPublicKeyPem:pem,signature,nowMs:now+1};
  assert.equal(verifyNewDeviceProof(a),true);
  assert.equal(verifyNewDeviceProof({...a,signature:sign('sha256',payload,other.privateKey)}),false);
  assert.equal(verifyNewDeviceProof({...a,newPublicKeyPem:other.publicKey.export({type:'spki',format:'pem'})}),false);
  assert.equal(verifyNewDeviceProof({...a,intent:{...intent,nonce:'c'.repeat(64)}}),false);
  assert.equal(verifyNewDeviceProof({...a,intent:{...intent,requesterSession:'00000000-0000-0000-0000-000000000005'}}),false);
  assert.equal(verifyNewDeviceProof({...a,intent:{...intent,consumed:true}}),false);
  assert.equal(verifyNewDeviceProof({...a,nowMs:intent.expiresMs}),false);
  assert.equal(verifyNewDeviceProof({...a,signature:sign('sha256',approvalPayload(intent,approvingDevice),keys.privateKey)}),false);
});
