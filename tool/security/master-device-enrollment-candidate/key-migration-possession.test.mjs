import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign} from 'node:crypto';
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
import {migrationPossessionPayload,verifyMigrationKeyPossession} from './key-migration-possession.mjs';
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
function fixture(){
 const pair=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
 const publicKeyPem=pair.publicKey.export({type:'spki',format:'pem'}).toString();
 const actor=id(1),session=id(2),device={id:id(3),master_user_id:actor,is_locked:false,revoked_at:null};
 const proposal=pendingDeviceKeyMigration({actor,device,publicKeyPem});
 const challenge={id:id(4),actor,session,deviceId:device.id,keySha256:proposal.key_sha256,nonce:'a'.repeat(64),createdMs:1000,expiresMs:61000,consumed:false};
 const signature=sign('sha256',migrationPossessionPayload(challenge,proposal),pair.privateKey);
 return {pair,proposal,args:{actor,session,device,publicKeyPem,challenge,signature,databaseNowMs:2000}};
}
test('new key possession produces only the unchanged pending proposal',()=>{
 const {args,proposal}=fixture();
 assert.deepEqual(verifyMigrationKeyPossession(args),proposal);
 assert.equal(Object.isFrozen(verifyMigrationKeyPossession(args)),true);
 assert.equal(verifyMigrationKeyPossession(args).status,'pending');
});
test('signature cannot transfer between owner, session, device, key or challenge',()=>{
 const {args}=fixture();
 const altered=[{actor:id(9)},{session:id(9)},{device:{...args.device,id:id(9)}},
  {publicKeyPem:fixture().args.publicKeyPem},
  ...[{id:id(9)},{session:id(9)},{nonce:'b'.repeat(64)},{createdMs:999},{expiresMs:61001},{keySha256:'b'.repeat(64)}].map(change=>({challenge:{...args.challenge,...change}}))];
 for(const change of altered)assert.equal(verifyMigrationKeyPossession({...args,...change}),null);
});
test('stale proof, ineligible device, malformed interval and wrong purpose fail closed',()=>{
 const {args,pair,proposal}=fixture();
 for(const change of [{databaseNowMs:999},{databaseNowMs:61000},{databaseNowMs:NaN},
  {challenge:{...args.challenge,consumed:true}},
  {device:{...args.device,is_locked:true}},{device:{...args.device,revoked_at:'2026-01-01'}},
  {device:{...args.device,master_user_id:id(9)}},
  {signature:sign('sha256',Buffer.from('sko-master-device-approval-v1'),pair.privateKey)}])
  assert.equal(verifyMigrationKeyPossession({...args,...change}),null);
 for(const change of [{createdMs:-1},{expiresMs:1000},{expiresMs:121001},{nonce:'bad'}])
  assert.throws(()=>migrationPossessionPayload({...args.challenge,...change},proposal));
});
