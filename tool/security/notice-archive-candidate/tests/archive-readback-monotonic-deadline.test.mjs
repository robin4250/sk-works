// Actual synchronous callback stalls, valid crypto/opaque bytes, no live service.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {performance} from 'node:perf_hooks';
import {createHash,generateKeyPairSync,sign} from 'node:crypto';
import fs from 'node:fs/promises';import {join} from 'node:path';import {tmpdir} from 'node:os';
import {createArchiveByteStoreCandidate} from '../src/archive-byte-store-candidate.mjs';
import {archiveReadbackReceiptBytesCandidate,createArchiveReadbackAttestorCandidate,createArchiveReadbackVerifierCandidate} from '../src/archive-readback-receipt-candidate.mjs';
const authority='30000000-0000-4000-8000-000000000001',clock=1793200000000;
const realNow=performance.now.bind(performance);
const stall=()=>{const until=realNow()+25;while(realNow()<until){/* starve timer callbacks */}};
function isolatedStall(t){
 // Advance only the target stage's monotonic clock. An unrelated OS pause must
 // not prevent reaching the signer/transport stage whose rejection we prove.
 let elapsed=0;t.mock.method(performance,'now',()=>elapsed);
 return ()=>{stall();elapsed+=25;};
}
async function fixture(t){
 const directory=await fs.mkdtemp(join(tmpdir(),'sko-monotonic-readback-'));await fs.chmod(directory,0o700);t.after(()=>fs.rm(directory,{recursive:true,force:true}));
 const store=await createArchiveByteStoreCandidate({enabled:true,directory}),bytes=Buffer.from('synthetic opaque bytes only');
 const descriptor=await store.retain({company_id:'10000000-0000-4000-8000-000000000001',event_id:'20000000-0000-4000-8000-000000000001',revision:1,
  snapshot_sha256:'a'.repeat(64),payload_sha256:createHash('sha256').update(bytes).digest('hex'),payload:bytes});
 // Filesystem restore finishes before each timed stage: it must not accidentally
 // consume the tested callback deadline under unrelated CI I/O load.
 const restored=await store.restore(descriptor),keys=generateKeyPairSync('ed25519'),key=keys.publicKey.export({format:'jwk'});
 const config={enabled:true,authorityId:authority,key,now:()=>clock,timeoutMs:10};
 const input={authority_id:authority,challenge:'b'.repeat(64),descriptor};
 return {config,input,descriptor,restored,keys,store};
}
test('synchronously late restore cannot reach signing while timers are starved',{timeout:5000},async t=>{
 const f=await fixture(t),overrun=isolatedStall(t);let restores=0,signs=0;
 const a=createArchiveReadbackAttestorCandidate({...f.config,store:{restore(){restores++;overrun();return f.restored;}},
  signObservation:b=>{signs++;return sign(null,b,f.keys.privateKey);}});
 await assert.rejects(a.observe(f.input),/readback unavailable/);assert.equal(restores,1);assert.equal(signs,0);
 assert.deepEqual(await f.store.restore(f.descriptor),f.restored);
});
test('synchronously late valid signer result is unknown, rejected and never retried',{timeout:5000},async t=>{
 const f=await fixture(t),overrun=isolatedStall(t);let signs=0;
 const a=createArchiveReadbackAttestorCandidate({...f.config,store:{restore:()=>f.restored},signObservation:b=>{
  signs++;overrun();return sign(null,b,f.keys.privateKey);
 }});
 await assert.rejects(a.observe(f.input),/readback unavailable/);assert.equal(signs,1);
 assert.deepEqual(await f.store.restore(f.descriptor),f.restored);
});
test('verifier rejects a valid fresh signed response returned after a synchronous transport stall',{timeout:5000},async t=>{
 const f=await fixture(t),overrun=isolatedStall(t);let fetches=0;
 const v=createArchiveReadbackVerifierCandidate({...f.config,fetchObservation:i=>{
  fetches++;overrun();const payload={v:1,kind:'archive_bytes_observed',authority_id:authority,challenge:i.challenge,descriptor:i.descriptor,observed_at:clock,expires_at:clock+30000};
  return {payload,signature:sign(null,archiveReadbackReceiptBytesCandidate(payload),f.keys.privateKey).toString('hex')};
 }});
 await assert.rejects(v.verify(f.descriptor),/readback unavailable/);assert.equal(fetches,1);
});
test('deadline elapsed before the first operation microtask refuses callback work',{timeout:5000},async t=>{
 const f=await fixture(t),overrun=isolatedStall(t);let restores=0,signs=0;
 const a=createArchiveReadbackAttestorCandidate({...f.config,store:{restore:()=>{restores++;return f.restored;}},signObservation:b=>{signs++;return sign(null,b,f.keys.privateKey);}});
 const pending=a.observe(f.input),rejected=assert.rejects(pending,/readback unavailable/);overrun();await rejected;
 assert.equal(restores,0);assert.equal(signs,0);
});

test('each successful or rejected operation clears its one owned deadline timer exactly once',{timeout:5000},async t=>{
 const f=await fixture(t),overrun=isolatedStall(t),schedule=globalThis.setTimeout,clear=globalThis.clearTimeout;
 const scheduled=[],cleared=[];
 t.mock.method(globalThis,'setTimeout',(...args)=>{const timer=schedule(...args);scheduled.push(timer);return timer;});
 t.mock.method(globalThis,'clearTimeout',timer=>{cleared.push(timer);return clear(timer);});
 let signs=0;
 const a=createArchiveReadbackAttestorCandidate({...f.config,store:{restore:()=>f.restored},signObservation:b=>{
  signs++;if(signs===2)overrun();return sign(null,b,f.keys.privateKey);
 }});
 await a.observe(f.input);
 await assert.rejects(a.observe(f.input),/readback unavailable/);
 assert.equal(signs,2);assert.equal(scheduled.length,2);assert.equal(cleared.length,2);
 assert.notEqual(scheduled[0],scheduled[1]);assert.deepEqual(cleared,scheduled);
});
