// Isolated in-memory model. It provides no actual separate durable witness.
import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign,randomBytes} from 'node:crypto';
import {receiptBytes,validateWitnessReceipt} from '../src/recovery-witness-model.mjs';
const keys=()=>{const k=generateKeyPairSync('ed25519');return {private:k.privateKey,public:k.publicKey.export({format:'jwk'})}};
const token=()=>randomBytes(32).toString('hex');
function fixture(){const key=keys(),ledger=new Map();let sequence=0;return {key,async consume({scope,nonce,proposalHash,challenge,now}){
 if(ledger.has(nonce))throw Error('already consumed');
 ledger.set(nonce,proposalHash);const payload={v:1,scope,challenge,nonce,proposal_hash:proposalHash,sequence:++sequence,issued:now};
 return {payload,signature:sign(null,receiptBytes(payload),key.private).toString('hex')};
}};}
test('independent witness rejects nonce even if local history is rolled back',async()=>{
 const f=fixture(),nonce=token(),proposalHash=token(),challenge=token(),scope='synthetic',now=1000;
 const receipt=await f.consume({scope,nonce,proposalHash,challenge,now});
 const ctx={scope,nonce,proposalHash,challenge,now,minSequence:1,key:f.key.public};
 assert.equal(validateWitnessReceipt(receipt,ctx).sequence,1);
 await assert.rejects(()=>f.consume({scope,nonce,proposalHash,challenge:token(),now}),/consumed/);
 assert.throws(()=>validateWitnessReceipt(receipt,{...ctx,challenge:token()}));
 assert.throws(()=>validateWitnessReceipt(receipt,{...ctx,now:31001}));
 assert.throws(()=>validateWitnessReceipt(receipt,{...ctx,scope:'other'}));
 assert.throws(()=>validateWitnessReceipt(receipt,{...ctx,minSequence:2}));
 assert.throws(()=>validateWitnessReceipt(receipt,{...ctx,key:keys().public}));
 assert.throws(()=>validateWitnessReceipt({...receipt,payload:{...receipt.payload,proposal_hash:token()}},ctx));
});
test('lost response is not permission to repeat the action',async()=>{
 const f=fixture(),nonce=token(),proposalHash=token(),scope='synthetic',now=1000;
 await f.consume({scope,nonce,proposalHash,challenge:token(),now});
 await assert.rejects(()=>f.consume({scope,nonce,proposalHash,challenge:token(),now}),/consumed/);
 // An operator must reconcile the remote committed receipt; no recovery occurs.
});
