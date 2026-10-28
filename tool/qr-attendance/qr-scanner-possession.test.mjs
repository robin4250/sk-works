import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign} from 'node:crypto';
import {scannerRegistrationSigningBytes,createScannerRegistrationPossessionAdapter} from './qr-scanner-possession.mjs';
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
function fixture(){
 const keys=generateKeyPairSync('ed25519');
 const challenge={id:id(1),company:id(2),actor:id(3),session:id(4),device:id(5),nonce:id(6),
  keyHex:keys.publicKey.export({type:'spki',format:'der'}).toString('hex'),createdMs:1000,expiresMs:91000,databaseNowMs:2000};
 const events=[];let failConsume=false,wrongActor=false;
 const client={async query(sql){events.push(sql);if(sql.includes('load_scanner_key_challenge'))return {rows:[{challenge}]};
  if(sql.includes('register_own_scanner'))return {rows:[{device:challenge.device}]};
  if(sql.includes('consume_scanner')&&failConsume)throw Error('synthetic consume failure');return {rows:[]};},release(){events.push('release');}};
 const adapter=createScannerRegistrationPossessionAdapter({pool:{connect:async()=>client},initializeVerifiedSession:async()=>({actor:wrongActor?id(9):challenge.actor,session:challenge.session})});
 const args={challengeId:challenge.id,signature:sign(null,scannerRegistrationSigningBytes(challenge),keys.privateKey),reauthenticationProof:'synthetic-proof'};
 return {challenge,keys,args,adapter,events,set failConsume(v){failConsume=v;},set wrongActor(v){wrongActor=v;}};
}
test('valid possession is checked before exact proof registration, consumption and commit',async()=>{
 const f=fixture();assert.deepEqual(await f.adapter.complete(f.args),{deviceId:f.challenge.device});
 const stages=f.events.filter(s=>/load_scanner|register_own|consume_scanner|^commit$/.test(s));
 assert.equal(stages.length,4);assert.match(stages[0],/load_scanner/);assert.match(stages[1],/register_own/);assert.match(stages[2],/consume_scanner/);assert.equal(stages[3],'commit');
});
test('signature from another key never consumes the exact operation proof',async()=>{
 const f=fixture(),other=generateKeyPairSync('ed25519');f.args.signature=sign(null,scannerRegistrationSigningBytes(f.challenge),other.privateKey);
 await assert.rejects(f.adapter.complete(f.args));assert.ok(!f.events.some(s=>s.includes('register_own')));assert.ok(f.events.includes('rollback'));
});
test('signature is bound to the authenticating session and exact company/key/device/nonce/expiry',async()=>{
 for(const field of ['session','company','device','nonce','keyHex','expiresMs']){
  const f=fixture();f.challenge[field]=field==='keyHex'?'302a300506032b6570032100'+'cd'.repeat(32):field==='expiresMs'?90000:id(8);
  await assert.rejects(f.adapter.complete(f.args));assert.ok(!f.events.some(s=>s.includes('register_own')));
 }
 const f=fixture();f.wrongActor=true;await assert.rejects(f.adapter.complete(f.args));
});
test('expired/database time missing context fails before registration',async()=>{
 for(const value of [91000,undefined,NaN]){const f=fixture();f.challenge.databaseNowMs=value;await assert.rejects(f.adapter.complete(f.args));assert.ok(!f.events.some(s=>s.includes('register_own')));}
});
test('consume failure rolls back registry, exact proof and audit rather than returning success',async()=>{
 const f=fixture();f.failConsume=true;await assert.rejects(f.adapter.complete(f.args));assert.ok(f.events.includes('rollback'));assert.ok(!f.events.includes('commit'));
});
test('signature buffer is snapshotted before waiting for a pool connection',async()=>{
 const f=fixture();let connect;
 const client={query:async sql=>sql.includes('load_scanner')?{rows:[{challenge:f.challenge}]}:sql.includes('register_own')?{rows:[{device:f.challenge.device}]}:{rows:[]},release(){}};
 const a=createScannerRegistrationPossessionAdapter({pool:{connect:()=>new Promise(r=>{connect=r;})},initializeVerifiedSession:async()=>({actor:f.challenge.actor,session:f.challenge.session})});
 const result=a.complete(f.args);f.args.signature.fill(0);connect(client);assert.deepEqual(await result,{deviceId:f.challenge.device});
});
