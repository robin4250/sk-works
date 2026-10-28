import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign} from 'node:crypto';
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
import {migrationPossessionPayload} from './key-migration-possession.mjs';
import {storeProvenPendingDeviceKey} from './key-migration-proven-adapter.mjs';
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
function fixture({badSignature=false,consumed=false,expire=false,consumeFails=false}={}) {
 const pair=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),publicKeyPem=pair.publicKey.export({type:'spki',format:'pem'}).toString();
 const actor=id(1),session=id(2),deviceId=id(3),challengeId=id(4);
 const device={id:deviceId,master_user_id:actor,is_locked:false,revoked_at:null};
 const proposal=pendingDeviceKeyMigration({actor,device,publicKeyPem});
 const challenge={id:challengeId,actor,session,deviceId,keySha256:proposal.key_sha256,nonce:'a'.repeat(64),createdMs:1000,expiresMs:61000,consumed:false};
 const signature=sign('sha256',migrationPossessionPayload(challenge,proposal),pair.privateKey);
 if(badSignature)signature[0]^=1;
 const calls=[];let released=false;
 const client={query:async(sql,params)=>{calls.push([sql,params]);
  if(sql.includes('auth.uid() as actor'))return {rows:[{actor,session,master:true}]};
  if(sql.includes('for share'))return {rows:[device]};
  if(sql.includes('for update'))return {rows:[{...challenge,consumed,databaseNowMs:expire?61000:2000}]};
  if(sql.startsWith('insert'))return {rows:[{id:id(5),status:'pending'}]};
  if(sql.startsWith('update'))return {rows:consumeFails?[]:[{id:challengeId}]};
  return {rows:[]};},release:()=>{released=true;}};
 return {args:{pool:{connect:async()=>client},actor,session,deviceId,challengeId,publicKeyPem,signature},calls,released:()=>released};
}
test('server-owned locked proof and atomic nonce consume precede commit, without key activation',async()=>{
 const f=fixture();assert.deepEqual(await storeProvenPendingDeviceKey(f.args),{id:id(5),status:'pending'});
 assert.equal(f.calls.at(-1)[0],'commit');assert.equal(f.released(),true);
 const lock=f.calls.findIndex(([sql])=>sql.includes('for update')),insert=f.calls.findIndex(([sql])=>sql.startsWith('insert'));
 const consume=f.calls.findIndex(([sql])=>sql.startsWith('update'));
 assert.ok(lock<insert&&insert<consume);
 assert.match(f.calls[lock][0],/clock_timestamp/);assert.match(f.calls[consume][0],/require_reauthentication_session/);
 assert.equal(f.calls.filter(([sql])=>sql.startsWith('update')).length,1);
});
test('invalid signature, consumed and expired challenges cannot insert or consume',async()=>{
 for(const options of [{badSignature:true},{consumed:true},{expire:true}]) {
  const f=fixture(options);await assert.rejects(storeProvenPendingDeviceKey(f.args));
  assert.equal(f.calls.some(([sql])=>sql.startsWith('insert')||sql.startsWith('update')),false);
  assert.equal(f.calls.at(-1)[0],'rollback');assert.equal(f.released(),true);
 }
});
test('identity or expiry failure on final nonce claim rolls pending save back and never retries',async()=>{
 const f=fixture({consumeFails:true});await assert.rejects(storeProvenPendingDeviceKey(f.args));
 assert.equal(f.calls.at(-1)[0],'rollback');assert.equal(f.calls.some(([sql])=>sql==='commit'),false);
 assert.equal(f.calls.filter(([sql])=>sql.startsWith('insert')).length,1);assert.equal(f.released(),true);
});
