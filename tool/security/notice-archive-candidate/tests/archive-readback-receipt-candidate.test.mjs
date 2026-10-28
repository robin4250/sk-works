import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash,generateKeyPairSync,sign} from 'node:crypto';
import {createArchiveByteStoreCandidate} from '../src/archive-byte-store-candidate.mjs';
import {createArchiveReadbackAttestorCandidate,createArchiveReadbackVerifierCandidate} from '../src/archive-readback-receipt-candidate.mjs';

const company='10000000-0000-0000-0000-000000000001',event='20000000-0000-0000-0000-000000000001',authority='30000000-0000-0000-0000-000000000001';
const sha=x=>createHash('sha256').update(x).digest('hex');
const pair=()=>{const p=generateKeyPairSync('ed25519');return {...p,key:p.publicKey.export({format:'jwk'})};};
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function fixture(t){
 const root=await fs.mkdtemp(join(tmpdir(),'sko-signed-readback-'));await fs.chmod(root,0o700);t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const store=await createArchiveByteStoreCandidate({enabled:true,directory:root}),payload=Buffer.from('synthetic opaque bytes, not proof of encryption'),keys=pair();let clock=1793200000000,signs=0,fetches=0;
 const descriptor=await store.retain({company_id:company,event_id:event,revision:2,snapshot_sha256:'a'.repeat(64),payload_sha256:sha(payload),payload});
 const signer=async bytes=>{signs++;return sign(null,bytes,keys.privateKey);};
 const attestor=options=>createArchiveReadbackAttestorCandidate({enabled:true,authorityId:authority,store,key:keys.key,signObservation:signer,now:()=>clock,...options});
 const instance=attestor();
 const verifier=options=>createArchiveReadbackVerifierCandidate({enabled:true,authorityId:authority,key:keys.key,now:()=>clock,fetchObservation:async i=>{fetches++;return instance.observe(i);},...options});
 return {root,store,payload,keys,descriptor,attestor,verifier,observe:instance.observe,setClock:n=>clock=n,signs:()=>signs,fetches:()=>fetches};
}
test('default OFF invokes neither store nor signer nor transport',()=>{
 let called=0;const effect=()=>called++;
 assert.throws(()=>createArchiveReadbackAttestorCandidate({store:{restore:effect},signObservation:effect}));
 assert.throws(()=>createArchiveReadbackVerifierCandidate({fetchObservation:effect}));
 assert.equal(called,0);
});
test('real filesystem readback receives a domain-separated signed observation without a release permit',async t=>{
 const f=await fixture(t),result=await f.verifier().verify(f.descriptor);
 assert.equal(result.status,'readback_verified_unattested');assert.equal(result.receipt.payload.kind,'archive_bytes_observed');
 assert.deepEqual(result.receipt.payload.descriptor,f.descriptor);assert.equal(result.receipt.signature.length,128);
 assert.equal(Object.hasOwn(result,'passed'),false);assert.equal(Object.hasOwn(result,'release'),false);assert.equal(Object.hasOwn(result.receipt.payload,'retention_until'),false);
 assert.equal(f.signs(),1);assert.equal(f.fetches(),1);assert.deepEqual(await f.store.restore(f.descriptor),f.payload);
});
test('a saved valid receipt cannot answer a new fresh challenge',async t=>{
 const f=await fixture(t);let cached;
 const v=f.verifier({fetchObservation:async i=>cached??=await f.observe(i)});
 const first=await v.verify(f.descriptor);assert.equal(first.status,'readback_verified_unattested');
 await assert.rejects(v.verify(f.descriptor),/readback unavailable/);assert.equal(f.signs(),1);
});
test('the attestor has no durable nonce-consumption claim; repeated read-only observation is explicit',async t=>{
 const f=await fixture(t),i={authority_id:authority,challenge:'9'.repeat(64),descriptor:f.descriptor};
 await f.observe(i);await f.observe(i);assert.equal(f.signs(),2);
 // Only the verifier creates fresh per-operation challenges. This attestor is
 // not a nonce ledger, protected checkpoint or source-release authority.
});
test('wrong signing key, changed authority, changed descriptor or signature domain is rejected',async t=>{
 const f=await fixture(t),foreign=pair();
 await assert.rejects(f.verifier({key:foreign.key}).verify(f.descriptor));
 await assert.rejects(f.observe({authority_id:authority,challenge:'0'.repeat(64),descriptor:f.descriptor,key:foreign.key}));
 for(const mutate of [r=>r.payload.authority_id=company,r=>r.payload.descriptor.revision++,r=>r.payload.descriptor.snapshot_sha256='b'.repeat(64),r=>r.payload.descriptor.object_id='c'.repeat(64),r=>r.signature='0'.repeat(128)]){
  await assert.rejects(f.verifier({fetchObservation:async i=>{const r=structuredClone(await f.observe(i));mutate(r);return r;}}).verify(f.descriptor));
 }
 const bad=f.attestor({signObservation:async bytes=>sign(null,Buffer.from(bytes.toString().split('\n').slice(1).join('\n')),f.keys.privateKey)});
 await assert.rejects(bad.observe({authority_id:authority,challenge:'1'.repeat(64),descriptor:f.descriptor}));
});
test('expired/future responses and a post-sign clock move fail closed',async t=>{
 const f=await fixture(t),initial=1793200000000;
 for(const time of [initial-1,initial+30000]){
  f.setClock(initial);
  await assert.rejects(f.verifier({fetchObservation:async i=>{const r=await f.observe(i);f.setClock(time);return r;}}).verify(f.descriptor));
 }
 f.setClock(initial);
 await assert.rejects(f.attestor({signObservation:async bytes=>{f.setClock(initial+30000);return sign(null,bytes,f.keys.privateKey);}}).observe({authority_id:authority,challenge:'2'.repeat(64),descriptor:f.descriptor}));
});
test('missing/corrupt bytes and a lying restore callback fail before external signing',async t=>{
 const f=await fixture(t),path=join(f.root,`${f.descriptor.object_id}.archive`),i={authority_id:authority,challenge:'3'.repeat(64),descriptor:f.descriptor};
 const bad=f.attestor({store:{restore:async()=>Buffer.alloc(f.payload.length)}});await assert.rejects(bad.observe(i));
 await fs.writeFile(path,'altered');await assert.rejects(f.observe(i));
 await fs.unlink(path);await assert.rejects(f.observe(i));assert.equal(f.signs(),0);
});
test('caller metadata mutation during restore cannot rebind the signed snapshot',async t=>{
 const f=await fixture(t);let release,entered;
 const wait=new Promise(r=>release=r),seen=new Promise(r=>entered=r);
 const a=f.attestor({store:{async restore(d){entered();await wait;return f.store.restore(d);}}});
 const original=structuredClone(f.descriptor),i={authority_id:authority,challenge:'4'.repeat(64),descriptor:original};
 const pending=a.observe(i);await seen;i.challenge='5'.repeat(64);original.company_id=event;original.revision=99;release();
 const receipt=await pending;assert.equal(receipt.payload.challenge,'4'.repeat(64));assert.equal(receipt.payload.descriptor.company_id,company);assert.equal(receipt.payload.descriptor.revision,2);
});
test('verifier pins metadata before transport and rejects accessor fields without invoking them',async t=>{
 const f=await fixture(t),original=structuredClone(f.descriptor);let release,entered,getter=false;
 const wait=new Promise(r=>release=r),seen=new Promise(r=>entered=r);
 const v=f.verifier({fetchObservation:async i=>{entered();await wait;return f.observe(i);}});
 const pending=v.verify(original);await seen;original.revision=99;release();assert.equal((await pending).receipt.payload.descriptor.revision,2);
 const accessor=structuredClone(f.descriptor);Object.defineProperty(accessor,'revision',{get(){getter=true;return 2;}});
 await assert.rejects(v.verify(accessor));assert.equal(getter,false);
});
test('store methods/public key are pinned and signer buffer/signature changes cannot substitute a receipt',async t=>{
 const f=await fixture(t),key=structuredClone(f.keys.key),configStore={restore:f.store.restore};
 const a=f.attestor({key,store:configStore});configStore.restore=async()=>Buffer.alloc(2);key.x=pair().key.x;
 assert.equal((await a.observe({authority_id:authority,challenge:'6'.repeat(64),descriptor:f.descriptor})).payload.descriptor.revision,2);
 const bad=f.attestor({signObservation:async bytes=>{bytes.fill(0);return sign(null,bytes,f.keys.privateKey);}});
 await assert.rejects(bad.observe({authority_id:authority,challenge:'7'.repeat(64),descriptor:f.descriptor}));
 assert.throws(()=>f.attestor({key:f.keys.privateKey.export({format:'jwk'})}));
});
test('restore deadline prevents late signing and signing timeout never auto-retries',async t=>{
 const f=await fixture(t);let release;
 const wait=new Promise(r=>release=r),a=f.attestor({timeoutMs:5,store:{async restore(){await wait;return f.payload;}}}),i={authority_id:authority,challenge:'8'.repeat(64),descriptor:f.descriptor};
 await assert.rejects(a.observe(i),/readback unavailable/);release();await delay(10);assert.equal(f.signs(),0);
 let signs=0;
 const slow=f.attestor({timeoutMs:5,signObservation:async bytes=>{signs++;await delay(20);return sign(null,bytes,f.keys.privateKey);}});
 await assert.rejects(slow.observe(i));await delay(25);assert.equal(signs,1);
 let requests=0;const v=f.verifier({timeoutMs:5,fetchObservation:async()=>{requests++;await delay(20);throw Error('fixture token must not leak');}});
 await assert.rejects(v.verify(f.descriptor),e=>e.message==='archive readback unavailable');await delay(25);assert.equal(requests,1);
});
test('retained expected revision detects source-store rollback; rollback of both remains unproven',async t=>{
 const f=await fixture(t),newPayload=Buffer.from('new opaque bytes'),newer=await f.store.retain({company_id:company,event_id:event,revision:3,snapshot_sha256:'d'.repeat(64),payload_sha256:sha(newPayload),payload:newPayload});
 await fs.unlink(join(f.root,`${newer.object_id}.archive`)); // isolated host-rollback simulation only
 await assert.rejects(f.verifier().verify(newer));
 const old=await f.verifier().verify(f.descriptor);
 assert.equal(old.status,'readback_verified_unattested');assert.equal(old.receipt.payload.descriptor.revision,2);
 // A signer can freshly attest bytes from an old local snapshot if the caller
 // also lost its true expected descriptor. This is NOT rollback-resistant trust.
 assert.equal(Object.hasOwn(old,'rollback_protected'),false);
});
