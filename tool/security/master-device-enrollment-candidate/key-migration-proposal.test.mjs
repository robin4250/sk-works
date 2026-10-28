import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
const actor='00000000-0000-0000-0000-000000000001';
const device={id:'00000000-0000-0000-0000-000000000002',master_user_id:actor,is_locked:false,revoked_at:null};
const pair=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
const publicKeyPem=pair.publicKey.export({format:'pem',type:'spki'}).toString();
test('canonical key migration remains pending and never reuses legacy identity as key',()=>{
 const row=pendingDeviceKeyMigration({actor,device,publicKeyPem});
 assert.equal(row.status,'pending');assert.match(row.key_sha256,/^[a-f0-9]{64}$/);assert.equal(Object.isFrozen(row),true);
 assert.throws(()=>pendingDeviceKeyMigration({actor,device,publicKeyPem:'legacy-random-identifier'}));
 assert.throws(()=>pendingDeviceKeyMigration({actor,device,publicKeyPem:pair.privateKey.export({format:'pem',type:'pkcs8'}).toString()}));
 assert.throws(()=>pendingDeviceKeyMigration({actor,device,publicKeyPem:publicKeyPem+'extra'}));
});
test('foreign, locked, revoked and non-P256 proposals are rejected',()=>{
 for(const changed of [{master_user_id:device.id},{is_locked:true},{revoked_at:'2026-10-28'}])
  assert.throws(()=>pendingDeviceKeyMigration({actor,device:{...device,...changed},publicKeyPem}));
 const rsa=generateKeyPairSync('rsa',{modulusLength:2048}).publicKey.export({format:'pem',type:'spki'}).toString();
 assert.throws(()=>pendingDeviceKeyMigration({actor,device,publicKeyPem:rsa}));
});
