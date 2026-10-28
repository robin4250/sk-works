import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash,createHmac,randomBytes} from 'node:crypto';
import {createArchiveByteStoreCandidate} from '../src/archive-byte-store-candidate.mjs';
import {encryptFixtureEvidence,decryptFixtureEvidence,verifyFixtureSource} from '../src/source-evidence-fixture.mjs';

const company='10000000-0000-0000-0000-000000000001',event='20000000-0000-0000-0000-000000000001';
const sha=x=>createHash('sha256').update(x).digest('hex');
const request=(payload=Buffer.from('synthetic opaque encrypted bytes'))=>({company_id:company,event_id:event,revision:2,snapshot_sha256:'a'.repeat(64),payload_sha256:sha(payload),payload});
async function fixture(t){
 const root=await fs.mkdtemp(join(tmpdir(),'sko-byte-custody-'));await fs.chmod(root,0o700);
 t.after(()=>fs.rm(root,{recursive:true,force:true}));
 return {root,open:(io=fs)=>createArchiveByteStoreCandidate({enabled:true,directory:root,io})};
}
test('default OFF does not inspect a directory or invoke an IO callback',async()=>{
 let called=false;
 await assert.rejects(createArchiveByteStoreCandidate({directory:'/not-selected',io:{open(){called=true;}}}),/custody unavailable/);
 assert.equal(called,false);
});
test('full encrypted original survives reopening; reverified source needs separate fixture keys',async t=>{
 const {open}=await fixture(t),store=await open(),key=randomBytes(32),archiveKey=randomBytes(32);
 const meta={collector_id:'30000000-0000-0000-0000-000000000001',correlation_key:'b'.repeat(64),event_id:event,event_kind:'current_lure_touched',generation:1,key_epoch:'2026-10-28',occurred_at:'2026-10-28T12:30:00.000Z'};
 const raw=Buffer.from(JSON.stringify(meta)),timestamp=1793190600000;
 const source={collector_id:meta.collector_id,key_version:1,timestamp,body_base64:raw.toString('base64'),signature:createHmac('sha256',key).update(`sko-collector-v2\n${meta.collector_id}\n1\n${timestamp}\n`).update(raw).digest('hex')};
 const box=encryptFixtureEvidence(source,meta,key,archiveKey,company),bytes=Buffer.from(JSON.stringify(box));
 const receipt=await store.retain(request(bytes));assert.equal(receipt.status,'stored_unattested');assert.equal(Object.hasOwn(receipt,'passed'),false);
 const reopened=await open(),restored=await reopened.restore(receipt);
 assert.deepEqual(restored,bytes);
 const original=decryptFixtureEvidence(JSON.parse(restored.toString()),company,archiveKey);
 assert.deepEqual(original,source);assert.equal(verifyFixtureSource(original,meta,key).event_id,event);
 assert.throws(()=>verifyFixtureSource(original,meta,randomBytes(32)));
 await assert.rejects(reopened.restore({...receipt,company_id:'10000000-0000-0000-0000-000000000002'}));
 await assert.rejects(reopened.restore({...receipt,revision:3}));
});
test('parallel replay creates one exact object and a changed revision preserves the original',async t=>{
 const {root,open}=await fixture(t),store=await open(),input=request();
 const results=await Promise.all(Array.from({length:12},()=>store.retain(input)));
 for(const result of results)assert.deepEqual(result,results[0]);
 assert.equal((await fs.readdir(root)).length,1);
 const oldBytes=await fs.readFile(join(root,`${results[0].object_id}.archive`));
 const next=await store.retain({...input,revision:3,snapshot_sha256:'c'.repeat(64)});
 assert.notEqual(next.object_id,results[0].object_id);
 assert.deepEqual(await fs.readFile(join(root,`${results[0].object_id}.archive`)),oldBytes);
 assert.deepEqual(await store.restore(results[0]),input.payload);
 assert.deepEqual(await store.restore(next),input.payload);
});
test('metadata and payload are copied before asynchronous file work',async t=>{
 const {root}=await fixture(t);let release,entered;
 const wait=new Promise(r=>release=r),seen=new Promise(r=>entered=r);
 const io={...fs,async open(path,...args){if(path.includes('.pending-')){entered();await wait;}return fs.open(path,...args);}};
 const store=await createArchiveByteStoreCandidate({enabled:true,directory:root,io}),input=request(),before=Buffer.from(input.payload);
 const pending=store.retain(input);await seen;
 input.company_id='10000000-0000-0000-0000-000000000002';input.revision=99;input.payload.fill(0);input.payload_sha256=sha(input.payload);
 release();const receipt=await pending;
 assert.equal(receipt.company_id,company);assert.equal(receipt.revision,2);assert.deepEqual(await store.restore(receipt),before);
});
test('missing, changed and oversized objects fail closed without repairing or deleting them',async t=>{
 const {root,open}=await fixture(t),store=await open(),input=request(),receipt=await store.retain(input),path=join(root,`${receipt.object_id}.archive`);
 await fs.writeFile(path,'altered');
 await assert.rejects(store.restore(receipt),/custody unavailable/);
 await assert.rejects(store.retain(input),/custody unavailable/);
 assert.equal(await fs.readFile(path,'utf8'),'altered');
 await fs.truncate(path,100*1024);await assert.rejects(store.restore(receipt));
 assert.equal((await fs.stat(path)).size,100*1024);
 await fs.unlink(path);await assert.rejects(store.restore(receipt));
});
test('symlink objects are rejected without following or changing their target',async t=>{
 const {root,open}=await fixture(t),store=await open(),input=request(),receipt=await store.retain(input),path=join(root,`${receipt.object_id}.archive`),target=join(root,'target');
 await fs.writeFile(target,'private fixture target',{mode:0o600});await fs.unlink(path);await fs.symlink(target,path);
 await assert.rejects(store.restore(receipt));await assert.rejects(store.retain(input));
 assert.equal(await fs.readFile(target,'utf8'),'private fixture target');assert.equal((await fs.lstat(path)).isSymbolicLink(),true);
});
test('partial write and failed publication leave no published object',async t=>{
 const {root}=await fixture(t);
 for(const stage of ['write','publish']){
  const io={...fs,async open(path,...args){const h=await fs.open(path,...args);if(stage==='write'&&path.includes('.pending-'))return {async writeFile(bytes){await h.writeFile(bytes.subarray(0,5));throw Error('fixture write loss');},close:h.close.bind(h)};return h;},async link(...args){if(stage==='publish')throw Error('fixture publish loss');return fs.link(...args);}};
  const store=await createArchiveByteStoreCandidate({enabled:true,directory:root,io});await assert.rejects(store.retain(request()),/custody unavailable/);
  assert.deepEqual(await fs.readdir(root),[]);
 }
});
test('lost directory sync leaves original intact and explicit retry rechecks exact bytes',async t=>{
 const {root,open}=await fixture(t);
 const io={...fs,async open(path,...args){const h=await fs.open(path,...args);return path===root?{async sync(){throw Error('fixture directory sync loss');},close:h.close.bind(h)}:h;}};
 const uncertain=await createArchiveByteStoreCandidate({enabled:true,directory:root,io}),input=request();
 await assert.rejects(uncertain.retain(input),/custody unavailable/);
 const names=await fs.readdir(root);assert.equal(names.length,1);const path=join(root,names[0]),before=await fs.readFile(path),inode=(await fs.stat(path)).ino;
 const resumed=await open(),receipt=await resumed.retain(input);
 assert.deepEqual(await fs.readFile(path),before);assert.equal((await fs.stat(path)).ino,inode);
 assert.deepEqual(await resumed.restore(receipt),input.payload);
});
test('unbounded, malformed, inherited and accessor input is refused before any object is written',async t=>{
 const {root,open}=await fixture(t),store=await open();let getter=false;
 const accessor=request();Object.defineProperty(accessor,'payload',{get(){getter=true;return Buffer.from('secret');},enumerable:true});
 for(const value of [request(Buffer.alloc(0)),request(Buffer.alloc(64*1024+1)),{...request(),payload_sha256:'0'.repeat(64)},{...request(),extra:true},Object.assign(Object.create({inherited:true}),request()),accessor])await assert.rejects(store.retain(value));
 assert.equal(getter,false);assert.deepEqual(await fs.readdir(root),[]);
});
test('an unsafe or symlink configuration directory is rejected',async t=>{
 const {root}=await fixture(t),alias=`${root}-alias`;t.after(()=>fs.unlink(alias).catch(()=>{}));
 await fs.symlink(root,alias);await assert.rejects(createArchiveByteStoreCandidate({enabled:true,directory:alias}));
 await fs.chmod(root,0o755);await assert.rejects(createArchiveByteStoreCandidate({enabled:true,directory:root}));
});
