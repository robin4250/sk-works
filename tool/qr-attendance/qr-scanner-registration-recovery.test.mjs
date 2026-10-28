import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign} from 'node:crypto';
import {scannerRegistrationSigningBytes} from './qr-scanner-possession.mjs';
import {createRecoverableScannerRegistrationAdapter} from './qr-scanner-registration-recovery.mjs';
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const keys=generateKeyPairSync('ed25519'),keyHex=keys.publicKey.export({format:'der',type:'spki'}).toString('hex');
function fixture(options={}) {
 const calls=[],challenge={id:id(1),company:id(2),actor:id(3),session:id(4),device:id(5),keyHex,nonce:id(6),createdMs:100,expiresMs:90100,databaseNowMs:200};
 const receipt={challengeId:challenge.id,companyId:challenge.company,actor:challenge.actor,session:challenge.session,
  deviceId:challenge.device,keyHex,registrationEventId:'9223372036854775807',...options.change};
 const client={async query(sql,args){calls.push({sql,args});
  if(sql.includes('load_scanner_key_challenge'))return {rows:[{challenge}]};
  if(sql.includes('complete_own_scanner_key_registration')||sql.includes('read_own_scanner_key_registration'))return {rows:[{receipt:options.empty?null:receipt}]};
  if(sql==='commit'){options.mutate?.(receipt);if(options.commitError)throw Error('private DB detail');}
  return {rows:[]};},release(discard){calls.push({sql:'release',discard});}};
 const pool={connect:async()=>{calls.push({sql:'connect'});await options.beforeConnect?.();return client;}};
 return {calls,challenge,receipt,pool,initializeVerifiedSession:async()=>({actor:id(3),session:id(4)}),
  payload:{challengeId:challenge.id,signature:sign(null,scannerRegistrationSigningBytes(challenge),keys.privateKey),reauthenticationProof:'synthetic-exact-proof'},
  target:{challengeId:challenge.id,companyId:challenge.company,deviceId:challenge.device,keyHex}};
}
const adapter=f=>createRecoverableScannerRegistrationAdapter({enabled:true,pool:f.pool,initializeVerifiedSession:f.initializeVerifiedSession});
test('default OFF does not acquire a pool or expose a receipt',async()=>{
 const f=fixture();const a=createRecoverableScannerRegistrationAdapter(f);
 await assert.rejects(a.complete(f.payload));await assert.rejects(a.read(f.target));assert.equal(f.calls.length,0);
});
test('verified signature uses atomic SQL completion and commits before acknowledgement',async()=>{
 const f=fixture();assert.deepEqual(await adapter(f).complete(f.payload),{deviceId:id(5)});
 assert.equal(f.calls.filter(x=>x.sql.includes('complete_own_scanner_key_registration')).length,1);
 assert.equal(f.calls.at(-2).sql,'commit');
 assert.equal(f.calls.some(x=>x.sql.includes('register_own_scanner_with_proof(')),false);
});
test('explicit read only recovers exact receipt and snapshots before COMMIT',async()=>{
 const f=fixture({mutate:r=>{r.deviceId=id(99);r.registrationEventId='999';}});
 assert.deepEqual(await adapter(f).read(f.target),{challengeId:id(1),deviceId:id(5),registrationEventId:'9223372036854775807'});
 assert.equal(f.calls.some(x=>/issue_|complete_own|consume_/.test(x.sql)),false);
 assert.equal(f.calls.at(-2).sql,'commit');
 const absent=fixture({empty:true});assert.equal(await adapter(absent).read(absent.target),null);
});
test('unknown COMMIT result returns no receipt and cannot retry or reconcile on same request',async()=>{
 const f=fixture({commitError:true}),a=adapter(f);
 await assert.rejects(a.complete(f.payload),e=>!e.message.includes('private DB detail'));
 await assert.rejects(a.complete(f.payload));await assert.rejects(a.read(f.target));
 assert.equal(f.calls.filter(x=>x.sql.includes('complete_own_scanner_key_registration')).length,1);
});
test('wrong signature or server scope never reaches completion SQL',async()=>{
 const f=fixture();f.payload.signature.fill(0);await assert.rejects(adapter(f).complete(f.payload));
 assert.equal(f.calls.some(x=>x.sql.includes('complete_own_scanner_key_registration')),false);
 const other=fixture();other.challenge.actor=id(99);await assert.rejects(adapter(other).complete(other.payload));
 assert.equal(other.calls.some(x=>x.sql==='commit'),false);
});
test('foreign receipt fields and invalid event IDs reject before commit',async()=>{
 for(const change of [{challengeId:id(99)},{companyId:id(99)},{deviceId:id(99)},{actor:id(99)},{session:id(99)},
  {keyHex:'302a300506032b6570032100'+'ab'.repeat(32)},{registrationEventId:1},{registrationEventId:'0'},{registrationEventId:'9223372036854775808'}]){
  const f=fixture({change});await assert.rejects(adapter(f).read(f.target));assert.equal(f.calls.some(x=>x.sql==='commit'),false);
 }
});
test('caller signature and target mutation during pool wait cannot redirect command or read',async()=>{
 let resume;const pending=new Promise(r=>{resume=r;});const f=fixture({beforeConnect:()=>pending});const a=adapter(f),result=a.complete(f.payload);
 f.payload.signature.fill(0);f.payload.challengeId=id(99);f.payload.reauthenticationProof='replaced';resume();
 assert.deepEqual(await result,{deviceId:id(5)});
 const command=f.calls.find(x=>x.sql.includes('complete_own_scanner_key_registration'));assert.deepEqual(command.args,[id(1),'synthetic-exact-proof']);
});
