import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createScannerRegistrationProofIssuer} from './qr-scanner-proof-issuer.mjs';
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
function fixture(result){const calls=[];let hash;
 const client={async query(sql,args){calls.push(sql);if(sql.includes('load_scanner'))return {rows:[{challenge:{id:id(1),actor:id(2),session:id(3)}}]};
  if(sql.includes('issue_registration')){hash=args[2];if(result instanceof Error)throw result;return {rows:[{expires_at:result}]};}return {rows:[]};},release(){}};
 return {calls,get hash(){return hash;},issuer:createScannerRegistrationProofIssuer({pool:{connect:async()=>client},initializeVerifiedSession:async()=>({actor:id(2),session:id(3)})})};
}
test('successful proof is generated internally and only its hash reaches the ledger',async()=>{
 const f=fixture(new Date('2030-01-01'));const r=await f.issuer.issue({challengeId:id(1),password:'synthetic-correct'});
 assert.equal(r.accepted,true);assert.match(r.proof,/^[a-f0-9]{64}$/);assert.equal(createHash('sha256').update(r.proof).digest('hex'),f.hash);
 assert.equal(f.calls.at(-1),'commit');await assert.rejects(f.issuer.issue({challengeId:id(1),password:'synthetic-correct'}));
});
test('wrong password commits failure counters and exposes no proof',async()=>{
 const f=fixture(null);assert.deepEqual(await f.issuer.issue({challengeId:id(1),password:'synthetic-wrong'}),{accepted:false});
 assert.equal(f.calls.at(-1),'commit');assert.ok(!f.calls.includes('rollback'));
});
test('unknown outcome is generic, rolled back if possible, and never automatically retried',async()=>{
 const f=fixture(Error('synthetic-secret-password'));await assert.rejects(f.issuer.issue({challengeId:id(1),password:'synthetic-secret-password'}),e=>!e.message.includes('synthetic-secret-password'));
 assert.equal(f.calls.at(-1),'rollback');await assert.rejects(f.issuer.issue({challengeId:id(1),password:'synthetic-correct'}));
 assert.equal(f.calls.filter(s=>s.includes('issue_registration')).length,1);
});
