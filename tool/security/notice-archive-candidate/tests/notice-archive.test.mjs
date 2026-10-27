import test from 'node:test';import assert from 'node:assert/strict';
import {createHash,createHmac,generateKeyPairSync,randomBytes,sign,randomUUID} from 'node:crypto';
import {verifyFixtureSource,encryptFixtureEvidence,decryptFixtureEvidence} from '../src/source-evidence-fixture.mjs';
import {mkdtemp,rm,mkdir,copyFile,readFile,writeFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';import {tmpdir} from 'node:os';import {createRequire} from 'node:module';
const require=createRequire(resolve(process.env.SKO_WORKER_TEST_ROOT??'../security-free-worker-candidate','package.json'));
const {Miniflare,Log,LogLevel}=require('miniflare');
const source=resolve(process.env.SKO_AUDIT_CORE??'../security-free-worker-candidate/src/security-audit.mjs');
const bytes=await readFile(source);if(createHash('sha256').update(bytes).digest('hex')!=='c52da32183a947cfac8e37470dd777e9c5de24acf224b9ee445376a82a3d5e58')throw Error('Existing security audit core differs');
const anchorSource=resolve(process.env.SKO_ANCHOR_CORE??'../security-off-finish/remaining-defense/src/anchor-authority.mjs');
if(createHash('sha256').update(await readFile(anchorSource)).digest('hex')!=='7b9425407013d9441486e9a1c8d8538f260a0176da79fc9d8333ed9636623ec4')throw Error('Existing anchor authority differs');
const sha=x=>createHash('sha256').update(x).digest('hex');const key=()=>{const x=generateKeyPairSync('ed25519');return{priv:x.privateKey,pub:x.publicKey.export({format:'jwk'}),privateJwk:x.privateKey.export({format:'jwk'})}};
const signature=(key,domain,body)=>sign(null,Buffer.from(domain+'\n'+body),key).toString('hex');
const now=Date.UTC(2026,9,27),day=86400000,zero='0'.repeat(64),owner='owner_1',company='10000000-0000-0000-0000-000000000001',deployment='notice_archive_1';
async function fixture(t){
 const dir=await mkdtemp(join(tmpdir(),'sko-notice-archive-')),src=join(dir,'src'),tests=join(dir,'tests');await mkdir(src);await mkdir(tests);
 await copyFile(source,join(src,'security-audit.mjs'));await copyFile(anchorSource,join(src,'anchor-authority.mjs'));await copyFile(new URL('../src/notice-archive.mjs', import.meta.url),join(src,'notice-archive.mjs'));await copyFile(new URL('./notice-archive-fixture.mjs', import.meta.url),join(tests,'notice-archive-fixture.mjs'));
 const audit=key(),anchor=key(),config={deploymentId:deployment,companyId:company,ownerId:owner,auditKeyId:'archive_audit_1',anchorKeyId:'archive_anchor_1',auditJwk:audit.pub,anchorJwk:anchor.pub,retentionMs:7*day};
 const options={modules:true,scriptPath:join(tests,'notice-archive-fixture.mjs'),modulesRoot:dir,compatibilityDate:'2026-07-30',durableObjects:{ARCHIVE:{className:'ArchiveFixture',useSQLite:true},AUTHORITY:{className:'AuthorityFixture',useSQLite:true}},bindings:{FIXTURE_ANCHOR_PRIVATE:JSON.stringify(anchor.privateJwk)},durableObjectsPersist:join(dir,'state'),log:new Log(LogLevel.ERROR)};
 let mf=new Miniflare(options);t.after(async()=>{await mf.dispose();await rm(dir,{recursive:true,force:true});});
 const call=async(route,data={},namespace='ARCHIVE')=>{const ns=await mf.getDurableObjectNamespace(namespace);return ns.get(ns.idFromName('fixture')).fetch('https://fixture.invalid/'+route,{method:'POST',body:JSON.stringify(data)});};
 assert.equal((await call('initialize',config)).status,200);const {retentionMs,...authorityConfig}=config;assert.equal((await call('initialize',authorityConfig,'AUTHORITY')).status,200);
 return{call,audit,anchor,config,restart:async()=>{await mf.dispose();mf=new Miniflare(options)}};
}
function createBatch(f,{seq=1,previous=zero,anchorSeq=1,previousAudit=zero,eventId=randomUUID(),reviewed=now-8*day,evidenceDigest=sha('synthetic signed event')}={}){
 const m={v:1,deployment_id:deployment,company_id:company,batch_sequence:seq,previous_hash:previous,archived_at:now,events:[{event_id:eventId,event_kind:'current_lure_touched',evidence_digest:evidenceDigest,generation:1,occurred_at:reviewed-1000,review_state:'resolved',reviewed_at:reviewed,history:[{action:'resolved',actor_id:owner,occurred_at:reviewed,reason:'fixture reviewed'}]}]};
 const body=JSON.stringify({v:1,deployment_id:deployment,sequence:anchorSeq,previous_hash:previousAudit,kind:'retention',action:'archive_notice_batch',reason:'retention_expired',actor_id:'system_retention',company_id:company,occurred_at:now,before:{},after:{manifest_sha256:sha(JSON.stringify(m)),batch_sequence:seq,event_count:m.events.length}});
 const audit={sequence:anchorSeq,previous_hash:previousAudit,hash:sha(body),body,signature:signature(f.audit.priv,'sko-decoy-audit-v1',body),key_id:'archive_audit_1',occurred_at:now};
 const payload={v:1,deployment_id:deployment,sequence:anchorSeq,hash:audit.hash,issued_at:now,key_id:'archive_anchor_1'},anchor={payload,signature:signature(f.anchor.priv,'sko-decoy-anchor-v1',JSON.stringify(payload))};
 return{manifest:m,audit,anchor,latestIndependentAnchor:anchor,now};
}
test('signed closed evidence is retained separately; exact retry and restart are stable',async t=>{
 const f=await fixture(t),batch=createBatch(f),saved=await f.call('store',batch);assert.equal(saved.status,200);const receipt=await saved.json();assert.equal(receipt.replayed,false);assert.equal((await(await f.call('store',batch)).json()).replayed,true);
 await f.restart();const read=await f.call('read',{batchSequence:1,latestIndependentAnchor:batch.anchor,now});assert.equal(read.status,200);assert.deepEqual(await read.json(),batch.manifest);assert.equal((await(await f.call('snapshot')).json()).rows.length,1);
});
test('unresolved, too recent, wrong source or wrong signature never changes archive',async t=>{
 const f=await fixture(t),batch=createBatch(f),before=await(await f.call('snapshot')).json();
 for(const mutate of [x=>x.manifest.events[0].review_state='investigating',x=>x.manifest.events[0].reviewed_at=now,x=>x.manifest.events[0].ip='127.0.0.1',x=>x.audit.signature='0'.repeat(128),x=>x.anchor.signature='0'.repeat(128),x=>x.latestIndependentAnchor=null,x=>x.manifest.company_id='other']){const x=structuredClone(batch);mutate(x);assert.equal((await f.call('store',x)).status,409);assert.deepEqual(await(await f.call('snapshot')).json(),before);}
});
test('lost head, stored-body corruption and database insertion failure refuse without partial write',async t=>{
 const f=await fixture(t),batch=createBatch(f);assert.equal((await f.call('store',batch)).status,200);const before=await(await f.call('snapshot')).json();
 await f.call('tamper',{sequence:1,manifest:before.rows[0].manifest.replace('fixture reviewed','changed')});assert.equal((await f.call('read',{batchSequence:1,latestIndependentAnchor:batch.anchor,now})).status,409);
 const g=await fixture(t),other=createBatch(g);await g.call('fail');assert.equal((await g.call('store',other)).status,409);const state=await(await g.call('snapshot')).json();assert.equal(state.rows.length,0);assert.equal(state.state[0].batch_sequence,0);
});
test('concurrent same batch, new signed head and deleted historical batch are detected',async t=>{
 const f=await fixture(t),first=createBatch(f);const rs=await Promise.all([f.call('store',first),f.call('store',first)]);assert.ok(rs.some(x=>x.status===200));const firstHash=sha(JSON.stringify(first.manifest));
 const second=createBatch(f,{seq:2,previous:firstHash,anchorSeq:2,previousAudit:first.audit.hash});assert.equal((await f.call('store',second)).status,200);
 assert.equal((await f.call('read',{batchSequence:1,latestIndependentAnchor:first.anchor,now})).status,409);
 assert.equal((await f.call('read',{batchSequence:1,latestIndependentAnchor:second.anchor,now})).status,200);
 await f.call('delete',{sequence:1});assert.equal((await f.call('read',{batchSequence:2,latestIndependentAnchor:second.anchor,now})).status,409);
});

test('existing independent authority anchors archive audit before immutable storage',async t=>{
 const f=await fixture(t),batch=createBatch(f);
 const publication={expected_sequence:0,expected_hash:zero,records:[batch.audit]};
 const anchored=await f.call('publish',{publication,now},'AUTHORITY');assert.equal(anchored.status,200);
 const authorityReceipt=await anchored.json();assert.equal(authorityReceipt.payload.hash,batch.audit.hash);
 batch.anchor=authorityReceipt;batch.latestIndependentAnchor=await(await f.call('latest',{},'AUTHORITY')).json();
 assert.equal((await f.call('store',batch)).status,200);await f.restart();
 batch.latestIndependentAnchor=await(await f.call('latest',{},'AUTHORITY')).json();
 assert.equal((await f.call('read',{batchSequence:1,latestIndependentAnchor:batch.latestIndependentAnchor,now})).status,200);
});

test('archive alone cannot establish ancestry of a higher signed anchor; authority rejects fork',async t=>{
 const f=await fixture(t), first=createBatch(f);
 assert.equal((await f.call('publish',{publication:{expected_sequence:0,expected_hash:zero,records:[first.audit]},now},'AUTHORITY')).status,200);
 first.anchor=await(await f.call('latest',{},'AUTHORITY')).json();first.latestIndependentAnchor=first.anchor;
 assert.equal((await f.call('store',first)).status,200);
 const fork=createBatch(f,{seq:2,previous:sha(JSON.stringify(first.manifest)),anchorSeq:2,previousAudit:'f'.repeat(64)});
 const rejected=await f.call('publish',{publication:{expected_sequence:1,expected_hash:first.audit.hash,records:[fork.audit]},now},'AUTHORITY');
 assert.equal(rejected.status,409);
 // Deliberately model a trusted anchor key issuing an inconsistent head. The
 // archive checks signatures and increasing sequence, not intervening ancestry.
 // Acceptance here is a counterexample, not a claim that the real authority
 // issues such a receipt, nor permission to connect this fixture to production.
 assert.equal((await f.call('store',fork)).status,200);
});

test('strict archive checks signed continuity, rejects forks and allows exact retry',async t=>{
 const f=await fixture(t),first=createBatch(f);
 first.auditExtension=[first.audit];
 assert.equal((await f.call('store-strict',first)).status,200);
 const firstHash=sha(JSON.stringify(first.manifest));
 const fork=createBatch(f,{seq:2,previous:firstHash,anchorSeq:2,previousAudit:'f'.repeat(64)});
 fork.auditExtension=[fork.audit];
 const before=await(await f.call('snapshot')).json();
 assert.equal((await f.call('store-strict',fork)).status,409);
 assert.deepEqual(await(await f.call('snapshot')).json(),before);
 const next=createBatch(f,{seq:2,previous:firstHash,anchorSeq:2,previousAudit:first.audit.hash});
 assert.equal((await f.call('store-strict',{...next,auditExtension:[]})).status,409);
 const changed=structuredClone(next.audit);changed.body=changed.body.replace('retention_expired','changed');
 assert.equal((await f.call('store-strict',{...next,auditExtension:[changed]})).status,409);
 assert.equal((await f.call('store-strict',{...next,auditExtension:[next.audit]})).status,200);
 assert.equal((await(await f.call('store-strict',{...next,auditExtension:[]})).json()).replayed,true);
});

test('strict archive accepts complete intermediate history but rejects missing or reordered rows',async t=>{
 const f=await fixture(t),first=createBatch(f);assert.equal((await f.call('store-strict',{...first,auditExtension:[first.audit]})).status,200);
 const previous=sha(JSON.stringify(first.manifest));
 const intermediate=createBatch(f,{seq:2,previous,anchorSeq:2,previousAudit:first.audit.hash});
 const last=createBatch(f,{seq:2,previous,anchorSeq:3,previousAudit:intermediate.audit.hash});
 for(const rows of [[last.audit],[last.audit,intermediate.audit],[intermediate.audit]]){
  assert.equal((await f.call('store-strict',{...last,auditExtension:rows})).status,409);
 }
 const results=await Promise.all([f.call('store-strict',{...last,auditExtension:[intermediate.audit,last.audit]}),f.call('store-strict',{...last,auditExtension:[intermediate.audit,last.audit]})]);
 assert.ok(results.some(r=>r.status===200));
 const state=await(await f.call('snapshot')).json();assert.equal(state.rows.length,2);assert.equal(state.state[0].anchor_sequence,3);
});

test('stale signed authority receipt is not evidence of a fresh head',async t=>{
 const f=await fixture(t),first=createBatch(f);
 assert.equal((await f.call('publish',{publication:{expected_sequence:0,expected_hash:zero,records:[first.audit]},now},'AUTHORITY')).status,200);
 first.anchor=await(await f.call('latest',{},'AUTHORITY')).json();first.latestIndependentAnchor=first.anchor;
 assert.equal((await f.call('store',first)).status,200);
 const second=createBatch(f,{seq:2,previous:sha(JSON.stringify(first.manifest)),anchorSeq:2,previousAudit:first.audit.hash});
 assert.equal((await f.call('publish',{publication:{expected_sequence:1,expected_hash:first.audit.hash,records:[second.audit]},now},'AUTHORITY')).status,200);
 const actualHead=await(await f.call('latest',{},'AUTHORITY')).json();
 assert.equal((await f.call('read',{batchSequence:1,latestIndependentAnchor:actualHead,now})).status,409);
 // A legitimate but stale signed receipt matches the old archive and is accepted.
 // This intentionally exposes why external fresh, authenticated head retrieval
 // is a mandatory prerequisite; the fixture is not rollback protection.
 assert.equal((await f.call('read',{batchSequence:1,latestIndependentAnchor:first.anchor,now})).status,200);
});

// Integration experiment: real existing signed audit/anchor and workerd archive,
// fixture source HMAC and encrypted copy on a separate local file. Not a real
// DB export or authenticated independent-host / key custody implementation.
test('fixture source MAC and encrypted original match independently anchored manifest after restart',async t=>{
 const f=await fixture(t),eventId=randomUUID(),collector=randomUUID(),sourceKey=randomBytes(32),archiveKey=randomBytes(32),reviewed=now-8*day,occurred=reviewed-1000;
 const metadata={event_id:eventId,collector_id:collector,occurred_at:new Date(occurred).toISOString(),event_kind:'current_lure_touched',generation:1,correlation_key:sha('synthetic correlation'),key_epoch:new Date(occurred).toISOString().slice(0,10)};
 const raw=Buffer.from(JSON.stringify(metadata)),timestamp=now,source={collector_id:collector,key_version:1,timestamp,body_base64:raw.toString('base64'),signature:createHmac('sha256',sourceKey).update(`sko-collector-v2\n${collector}\n1\n${timestamp}\n`).update(raw).digest('hex')};
 const proof=verifyFixtureSource(source,metadata,sourceKey),box=encryptFixtureEvidence(source,metadata,sourceKey,archiveKey,company),batch=createBatch(f,{eventId,reviewed,evidenceDigest:proof.raw_sha256});
 const dir=await mkdtemp(join(tmpdir(),'sko-fixture-envelope-'));t.after(()=>rm(dir,{recursive:true,force:true}));const file=join(dir,'encrypted-fixture.json');await writeFile(file,JSON.stringify(box));
 const publication={expected_sequence:0,expected_hash:zero,records:[batch.audit]},anchored=await f.call('publish',{publication,now},'AUTHORITY');assert.equal(anchored.status,200);
 batch.anchor=await anchored.json();batch.latestIndependentAnchor=await(await f.call('latest',{},'AUTHORITY')).json();assert.equal((await f.call('store',batch)).status,200);await f.restart();
 const latest=await(await f.call('latest',{},'AUTHORITY')).json(),saved=await f.call('read',{batchSequence:1,latestIndependentAnchor:latest,now});assert.equal(saved.status,200);const manifest=await saved.json();
 const restored=decryptFixtureEvidence(JSON.parse(await readFile(file,'utf8')),company,archiveKey),verified=verifyFixtureSource(restored,metadata,sourceKey);assert.equal(manifest.events[0].event_id,verified.event_id);assert.equal(manifest.events[0].evidence_digest,verified.raw_sha256);assert.equal(manifest.events[0].occurred_at,occurred);
 assert.throws(()=>verifyFixtureSource({...restored,signature:'0'.repeat(64)},metadata,sourceKey));assert.throws(()=>decryptFixtureEvidence({...box,tag:Buffer.alloc(16).toString('base64')},company,archiveKey));
});
