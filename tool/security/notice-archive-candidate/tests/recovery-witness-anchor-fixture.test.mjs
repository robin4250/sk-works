import test from 'node:test';import assert from 'node:assert/strict';
import {mkdtempSync,copyFileSync,rmSync} from 'node:fs';import {join} from 'node:path';import {tmpdir} from 'node:os';import {randomBytes} from 'node:crypto';
import {AnchoredWitnessFixture} from './recovery-witness-anchor-fixture.mjs';
const token=()=>randomBytes(32).toString('hex');
test('separately pinned checkpoint refuses stale restored witness and same-height fork',t=>{
 const dir=mkdtempSync(join(tmpdir(),'sko-witness-anchor-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));const path=join(dir,'witness.db'),snapshot=join(dir,'old.db');
 let witness=new AnchoredWitnessFixture(path);let pin=witness.head();
 pin=witness.consume({scope:'synthetic',nonce:token(),proposalHash:token(),expected:pin});witness.close();copyFileSync(path,snapshot);
 witness=new AnchoredWitnessFixture(path);pin=witness.consume({scope:'synthetic',nonce:token(),proposalHash:token(),expected:pin});witness.close();
 // A separately retained checkpoint sees the witness restored to an old state.
 copyFileSync(snapshot,path);witness=new AnchoredWitnessFixture(path);
 assert.throws(()=>witness.consume({scope:'synthetic',nonce:token(),proposalHash:token(),expected:pin}),/checkpoint mismatch/);
 const old=witness.head(),fork=witness.consume({scope:'synthetic',nonce:token(),proposalHash:token(),expected:old});
 assert.equal(fork.seq,pin.seq);assert.notEqual(fork.hash,pin.hash);
 assert.throws(()=>witness.consume({scope:'synthetic',nonce:token(),proposalHash:token(),expected:pin}),/checkpoint mismatch/);
 witness.close();
});
