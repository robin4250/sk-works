import test from 'node:test';import assert from 'node:assert/strict';
import {mkdtempSync,copyFileSync,rmSync} from 'node:fs';import {join} from 'node:path';import {tmpdir} from 'node:os';import {randomBytes} from 'node:crypto';
import {AnchoredWitnessFixture} from './recovery-witness-anchor-fixture.mjs';
import {Worker} from 'node:worker_threads';
import {DatabaseSync} from 'node:sqlite';
const token=()=>randomBytes(32).toString('hex');
test('partial loss or tampering of consumed nonce history fails closed',t=>{
 for(const corruption of ['delete','nonce','hash','state']){
  const dir=mkdtempSync(join(tmpdir(),'sko-witness-corrupt-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));
  const path=join(dir,'witness.db');let witness=new AnchoredWitnessFixture(path),pin=witness.head();
  pin=witness.consume({scope:'synthetic',nonce:token(),proposalHash:token(),expected:pin});
  pin=witness.consume({scope:'synthetic',nonce:token(),proposalHash:token(),expected:pin});witness.close();
  const db=new DatabaseSync(path);
  if(corruption==='delete')db.exec('DELETE FROM ledger WHERE seq=1');
  if(corruption==='nonce')db.prepare('UPDATE ledger SET nonce=? WHERE seq=1').run(token());
  if(corruption==='hash')db.prepare('UPDATE ledger SET hash=? WHERE seq=2').run(token());
  if(corruption==='state')db.prepare('UPDATE state SET hash=? WHERE id=1').run(token());
  db.close();witness=new AnchoredWitnessFixture(path);
  assert.throws(()=>witness.consume({scope:'synthetic',nonce:token(),proposalHash:token(),expected:pin}),/witness history corrupt/);
  witness.close();
 }
});
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
test('concurrent consumers of the same checkpoint admit at most one',async t=>{
 const dir=mkdtempSync(join(tmpdir(),'sko-witness-race-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));
 const path=join(dir,'witness.db'),initial=new AnchoredWitnessFixture(path),pin=initial.head();initial.close();
 const fixture=new URL('./recovery-witness-anchor-fixture.mjs',import.meta.url).href;
 const start=new SharedArrayBuffer(4),signal=new Int32Array(start);
 const workerCode=`const {parentPort,workerData}=require('node:worker_threads'); (async()=>{const {AnchoredWitnessFixture}=await import(workerData.fixture);parentPort.postMessage('ready');Atomics.wait(new Int32Array(workerData.start),0,0);let db;try{db=new AnchoredWitnessFixture(workerData.path);parentPort.postMessage({ok:true,result:db.consume(workerData.request)});}catch(e){parentPort.postMessage({ok:false,error:String(e.message)});}finally{db?.close();}})().catch(e=>{parentPort.postMessage({ok:false,error:String(e.message)});});`;
 const requests=[0,1].map(()=>({scope:'synthetic',nonce:token(),proposalHash:token(),expected:pin}));
 const workers=requests.map(request=>new Worker(workerCode,{eval:true,workerData:{fixture,path,start,request}}));
 const results=workers.map(w=>new Promise((resolve,reject)=>{w.on('error',reject);w.on('message',m=>{if(m==='ready'){if(++ready===2){Atomics.store(signal,0,1);Atomics.notify(signal,0,2);}}else resolve(m);});}));let ready=0;
 const values=await Promise.all(results);await Promise.all(workers.map(w=>w.terminate()));
 assert.equal(values.filter(v=>v.ok).length,1);assert.match(values.find(v=>!v.ok).error,/checkpoint mismatch|locked|busy/i);
 const db=new AnchoredWitnessFixture(path);assert.equal(db.head().seq,1);assert.throws(()=>db.consume(requests[values.findIndex(v=>!v.ok)]),/checkpoint mismatch/);db.close();
});
