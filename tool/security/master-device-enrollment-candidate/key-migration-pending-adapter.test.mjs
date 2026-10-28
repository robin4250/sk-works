import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {storePendingDeviceKey} from './key-migration-pending-adapter.mjs';
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const args={actor:id(1),session:id(2),deviceId:id(3),publicKeyPem:generateKeyPairSync('ec',{namedCurve:'prime256v1'}).publicKey.export({type:'spki',format:'pem'}).toString()};
function fixture({identity={actor:id(1),session:id(2),master:true},device={id:id(3),master_user_id:id(1),is_locked:false,revoked_at:null},retry=false,commitFails=false}={}) {
 const calls=[];let released=false;
 const client={query:async(sql,params)=>{calls.push([sql,params]);if(sql.includes('auth.uid()'))return {rows:[identity]};if(sql.includes('for share'))return {rows:[device]};if(sql.startsWith('insert'))return {rows:retry?[]:[{id:id(4),status:'pending'}]};if(sql.startsWith('select id,status'))return {rows:[{id:id(4),status:'pending'}]};if(sql==='commit'&&commitFails)throw Error('unknown commit');return {rows:[]};},release:()=>{released=true;}};
 return {pool:{connect:async()=>client},calls,released:()=>released};
}
test('pending insert rechecks live owner and locks device without activating a key',async()=>{
 const f=fixture();assert.deepEqual(await storePendingDeviceKey({...args,pool:f.pool}),{id:id(4),status:'pending'});
 assert.equal(f.calls[0][0],'begin');assert.equal(f.calls.at(-1)[0],'commit');assert.equal(f.released(),true);
 assert.ok(f.calls.find(([sql])=>sql.includes('for share')));assert.equal(f.calls.some(([sql])=>/update|set_config/i.test(sql)),false);
});
test('foreign session and locked/revoked device fail before insert',async()=>{
 for(const change of [{identity:{actor:id(1),session:id(9),master:true}},{identity:{actor:id(1),session:id(2),master:false}},{device:{id:id(3),master_user_id:id(1),is_locked:true,revoked_at:null}}]){
  const f=fixture(change);await assert.rejects(storePendingDeviceKey({...args,pool:f.pool}));assert.equal(f.calls.some(([sql])=>sql.startsWith('insert')),false);assert.equal(f.calls.at(-1)[0],'rollback');assert.equal(f.released(),true);
 }
});
test('identical retry reads pending row; unknown commit is not retried',async()=>{
 const f=fixture({retry:true});assert.equal((await storePendingDeviceKey({...args,pool:f.pool})).status,'pending');
 const broken=fixture({commitFails:true});await assert.rejects(storePendingDeviceKey({...args,pool:broken.pool}),/unknown commit/);assert.equal(broken.calls.filter(([sql])=>sql.startsWith('insert')).length,1);assert.equal(broken.released(),true);
});
