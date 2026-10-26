import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import {createHash,createHmac} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {Miniflare,Log,LogLevel} from 'miniflare';
import {binaryHex,binarySha256,constantBody} from '../src/wasm-manifest.mjs';
const root=resolve(import.meta.dirname,'..'),collectorId='30000000-0000-0000-0000-000000000001';
const bindings={DECOY_HOST:'decoy.invalid',DECOY_ENABLED:'true',COLLECTOR_ID:collectorId,STARTUP_SESSION_ID:'50000000-0000-4000-8000-000000000001',CAPABILITY_KEY_HEX:'11'.repeat(32),DERIVATION_KEY_HEX:'22'.repeat(32)};
function make(persist,overrides={},production=false){return new Miniflare({modules:true,scriptPath:join(root,production?'src/worker.mjs':'tests/runtime-fixture.mjs'),modulesRoot:root,modulesRules:[{type:'CompiledWasm',include:['**/*.wasm']}],compatibilityDate:'2026-07-30',durableObjects:{DECOY:{className:production?'DecoyBroker':'TestBroker',useSQLite:true}},durableObjectsPersist:persist,bindings:{...bindings,...overrides},log:new Log(LogLevel.ERROR)});}
async function fixture(t){const dir=await mkdtemp(join(tmpdir(),'sko-free-worker-'));let mf=make(dir);t.after(async()=>{await mf.dispose();await rm(dir,{recursive:true,force:true});});
 const direct=async(path,data)=>{const ns=await mf.getDurableObjectNamespace('DECOY'),stub=ns.get(ns.idFromName('security-decoy-v1'));return stub.fetch('https://fixture.invalid'+path,data===undefined?{}:{method:'POST',body:JSON.stringify(data)});};
 const inspect=async()=> (await direct('/inspect')).json();
 return {get mf(){return mf;},direct,inspect,enable:async()=>{const p=(await inspect()).policy;assert.equal((await direct('/transition',{expectedRevision:p.revision,action:'enable',reason:'reviewed_test'})).status,200);},restart:async()=>{await mf.dispose();mf=make(dir);}};
}
async function capability(f){const r=await f.mf.dispatchFetch('https://decoy.invalid/synthetic-decoy/capability');assert.equal(r.status,200);return(await r.json()).capability;}
const observe=(f,token,g=1)=>f.mf.dispatchFetch(`https://decoy.invalid/synthetic-decoy/g${g}/fixture-records`,{headers:{'x-sko-decoy-capability':token}});

test('actual binary is exact, import-free, fixed exports and one bounded page',async()=>{
 const b=await readFile(join(root,'src/decoy.wasm'));assert.equal(b.toString('hex'),binaryHex);assert.equal(createHash('sha256').update(b).digest('hex'),binarySha256);
 const m=new WebAssembly.Module(b);assert.deepEqual(WebAssembly.Module.imports(m),[]);const i=new WebAssembly.Instance(m,{});assert.equal(i.exports.memory.buffer.byteLength,65536);assert.throws(()=>i.exports.memory.grow(1));assert.equal(new TextDecoder().decode(new Uint8Array(i.exports.memory.buffer,0,i.exports.response_len())),constantBody);
});
test('default OFF denies even with fixture env; management and normal routes absent',async t=>{
 const f=await fixture(t);assert.equal((await f.mf.dispatchFetch('https://decoy.invalid/synthetic-decoy/capability')).status,503);
 for(const p of ['/operator/rotate','/manager/enable','/rest/v1/workers','/auth/v1/user','/__test/enable'])assert.equal((await f.mf.dispatchFetch('https://decoy.invalid'+p)).status,404);
 assert.equal((await f.inspect()).policy.rendered,0);
});
test('actual production module graph has no fixture control/inspection or automatic activation',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'sko-production-graph-')),mf=make(dir,{},true);
 try{assert.equal((await mf.dispatchFetch('https://decoy.invalid/synthetic-decoy/capability')).status,503);for(const p of ['/inspect','/transition','/__test/enable','/operator/rotate'])assert.equal((await mf.dispatchFetch('https://decoy.invalid'+p)).status,404);}
 finally{await mf.dispose();await rm(dir,{recursive:true,force:true});}
});
test('actual workerd Wasm executes only after short capability; replay and epoch refuse before execution',async t=>{
 const f=await fixture(t);await f.enable();const token=await capability(f);const r=await observe(f,token);assert.equal(r.status,200);assert.equal(await r.text(),constantBody);
 assert.equal((await observe(f,token)).status,503);assert.equal((await f.inspect()).policy.rendered,1);
 const old=await capability(f),p=(await f.inspect()).policy;assert.equal((await f.direct('/transition',{expectedRevision:p.revision,action:'rotate',reason:'operator_review'})).status,200);
 assert.equal((await observe(f,old)).status,401);assert.equal((await f.inspect()).policy.rendered,1);
 const fresh=await capability(f);assert.equal((await observe(f,fresh,2)).status,200);assert.equal((await f.inspect()).policy.rendered,2);
});
test('real SQLite CAS, rollback and quarantine/release preserve atomic state',async t=>{
 const f=await fixture(t);await f.enable();const before=await f.inspect();assert.equal((await f.direct('/rollback',{})).status,409);assert.deepEqual(await f.inspect(),before);
 const p=before.policy;const rs=await Promise.all([1,2].map(()=>f.direct('/transition',{expectedRevision:p.revision,action:'quarantine',reason:'operator_review'})));assert.deepEqual(rs.map(x=>x.status).sort(),[200,409]);
 assert.equal((await f.mf.dispatchFetch('https://decoy.invalid/synthetic-decoy/capability')).status,503);
 const q=(await f.inspect()).policy;await f.direct('/transition',{expectedRevision:q.revision,action:'release',reason:'false_positive'});assert.equal((await f.inspect()).policy.epoch,q.epoch+1);assert.equal((await observe(f,await capability(f))).status,200);
});
test('low durable budgets fail closed and cannot grow events/outbox',async t=>{
 const f=await fixture(t);await f.enable();await f.direct('/budget',{events:1,caps:3});assert.equal((await observe(f,await capability(f))).status,200);
 assert.equal((await observe(f,await capability(f))).status,503);const a=await f.inspect();assert.equal(a.events.length,1);assert.equal(a.outbox.length,1);assert.equal(a.policy.rendered,1);
});
test('real SQLite survives workerd replacement; ambiguous delivery reclaims same immutable event bytes',async t=>{
 const f=await fixture(t);await f.enable();await observe(f,await capability(f));const original=await f.inspect(),first=await(await f.direct('/claim',{now:Date.now(),leaseMs:1})).json();
 await f.restart();const after=await f.inspect();assert.deepEqual(after.events,original.events);assert.equal(after.policy.epoch,original.policy.epoch);
 const second=await(await f.direct('/claim',{now:Date.now()+10,leaseMs:1000})).json();assert.equal(second.event_id,first.event_id);assert.equal(second.body,first.body);assert.notEqual(second.claim,first.claim);
 assert.equal((await f.direct('/ack',{eventId:first.event_id,claim:first.claim})).status,409);assert.equal((await f.direct('/ack',{eventId:second.event_id,claim:second.claim})).status,200);assert.equal((await f.inspect()).outbox[0].state,'acknowledged');
});
test('native Workers WebCrypto matches public collector v2 fixture vector exactly',async t=>{
 const f=await fixture(t),body='{"event_id":"40000000-0000-4000-8000-000000000001","collector_id":"30000000-0000-0000-0000-000000000001","occurred_at":"2026-10-26T06:00:00.000Z","event_kind":"current_lure_touched","generation":3,"correlation_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","key_epoch":"2026-10-26"}';
 const v=await(await f.direct('/v2-vector',{keyHex:'000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',collectorId,keyVersion:7,timestamp:1792994400000,body})).json();assert.equal(v.signature,'f5330cfaad0507079668113f805bfff954ba7e4514d7f3a661ce233b68c5fbdc');
});
test('native Workers producer/HMAC uses unchanged seven-field v1 body and v2 transport',async t=>{
 const f=await fixture(t),keyHex='22'.repeat(32),at=1792994400000,args={keyHex,collectorId,sessionId:bindings.STARTUP_SESSION_ID,sequence:9,at,kind:'current_lure_touched',generation:3};
 const out=await(await f.direct('/protocol',args)).json();assert.deepEqual(Object.keys(out.event),['event_id','collector_id','occurred_at','event_kind','generation','correlation_key','key_epoch']);
 for(const [v,prefix]of[['v1',`sko-collector-v1\n${collectorId}\n${at}\n`],['v2',`sko-collector-v2\n${collectorId}\n7\n${at}\n`]])assert.equal(out[v],createHmac('sha256',Buffer.from(keyHex,'hex')).update(prefix+out.body).digest('hex'));
 const raw=createHmac('sha256',Buffer.from(keyHex,'hex')).update(`sko-decoy-producer-v1\nevent-id\n${collectorId}\n${bindings.STARTUP_SESSION_ID}\n9`).digest('hex');assert.equal(out.event.event_id.slice(0,8),raw.slice(0,8));assert(!out.body.includes('keyHex'));
});
test('expired/tampered capability and public identity/header injection never expand authority',async t=>{
 const f=await fixture(t);await f.enable();const expired=(await(await f.direct('/expired',{})).json()).capability;assert.equal((await observe(f,expired)).status,401);
 const cap=await capability(f);assert.equal((await observe(f,cap.slice(0,-1)+(cap.endsWith('0')?'1':'0'))).status,401);
 const r=await f.mf.dispatchFetch('https://decoy.invalid/synthetic-decoy/g1/fixture-records',{headers:{'x-sko-decoy-capability':cap,'x-sko-collector-id':'untrusted','x-forwarded-for':'198.51.100.99','authorization':'Bearer synthetic-private'}});assert.equal(r.status,200);
 const saved=JSON.stringify(await f.inspect());assert(!saved.includes('synthetic-private'));assert(!saved.includes('198.51.100.99'));assert(!saved.includes('untrusted'));
 assert.equal((await f.mf.dispatchFetch('https://wrong.invalid/synthetic-decoy/capability')).status,404);assert.equal((await f.mf.dispatchFetch('https://decoy.invalid/synthetic-decoy/capability?ip=private')).status,404);
 assert.equal((await f.inspect()).policy.rendered,1);
});
test('existing reviewed DecoyLab state and constant response are reused without calling JS isolated',async t=>{
 assert(process.env.SKO_SECURITY_SOURCE_ROOT,'Explicit reviewed source root required');const path=resolve(process.env.SKO_SECURITY_SOURCE_ROOT,'decoy_lab.mjs'),bytes=await readFile(path);assert.equal(createHash('sha256').update(bytes).digest('hex'),'9f5f9058515867d7b45bc2d5286cc43f86851b499c9d197cc973bd432a5cee0f');
 const {DecoyLab}=await import(pathToFileURL(path)),lab=new DecoyLab(),f=await fixture(t);await f.enable();assert.equal(lab.lure,'/synthetic-decoy/g1/fixture-records');
 assert.equal(await(await lab.handle(new Request('https://lab.invalid'+lab.lure))).text(),await(await observe(f,await capability(f))).text());
 lab.rotate();const p=(await f.inspect()).policy;await f.direct('/transition',{expectedRevision:p.revision,action:'rotate',reason:'operator_review'});assert.equal(lab.checkpoint().generation,(await f.inspect()).policy.generation);
});
