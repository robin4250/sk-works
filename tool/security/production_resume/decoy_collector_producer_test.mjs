import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {DecoyCollectorProducer} from './decoy_collector_producer.mjs';

const root=process.env.SKO_SECURITY_SOURCE_ROOT;
assert(root,'Set explicit reviewed security source directory');
async function reviewed(path,hash){const filename=resolve(root,path),bytes=await readFile(filename);assert.equal(createHash('sha256').update(bytes).digest('hex'),hash);return import(pathToFileURL(filename));}
const {DecoyLab}=await reviewed('decoy_lab.mjs','9f5f9058515867d7b45bc2d5286cc43f86851b499c9d197cc973bd432a5cee0f');
const {createCollectorSignedHandler,signCollectorBytes}=await reviewed('collector_signed_transport_candidate/collector_signed_transport.mjs','beb8ce3361d656d7c85e35eb77c9fb3a94ecbcb4b8f8e869474dcfeb8290d45a');
const now=1792972800000,collectorId='00000000-0000-0000-0000-000000000020',sessionId='00000000-0000-0000-0000-000000000030';
const sample={sequence:1,at:now,kind:'current_lure_touched',generation:1};
function producer(extra={}){return new DecoyCollectorProducer({collectorId,sessionId,derivationKey:Buffer.alloc(32,17),clock:()=>now,...extra});}

test('same source sequence has stable retry identity across producer replacement',()=>{
 const a=producer().build(sample),b=producer().build({...sample});assert.deepEqual(a,b);assert(Object.isFrozen(a));assert(Object.isFrozen(a.event));
 assert.equal(new Set(Object.keys(a.event)).size,7);assert.equal(a.source_tracking,'decoy_generation_only');
});
test('session restart and collector changes cannot reuse another event identity',()=>{
 const a=producer().build(sample);assert.notEqual(a.event.event_id,producer({sessionId:'00000000-0000-0000-0000-000000000031'}).build(sample).event.event_id);
 assert.notEqual(a.event.event_id,producer({collectorId:'00000000-0000-0000-0000-000000000021'}).build(sample).event.event_id);
});
test('same sequence tampering retains conflicting identity for durable sink refusal',()=>{
 const p=producer(),a=p.build(sample),b=p.build({...sample,generation:2});assert.equal(a.event.event_id,b.event.event_id);assert.notEqual(a.body,b.body);
});
test('unknown or injected metadata is rejected without reading or forwarding it',()=>{
 const p=producer();for(const patch of [{ip:'127.0.0.1'},{headers:{}},{body:'private'},{session_id:sessionId},{company_id:collectorId}])assert.throws(()=>p.build({...sample,...patch}),/Invalid decoy event/);
 assert.throws(()=>p.build({...sample,sequence:0}));assert.throws(()=>p.build({...sample,generation:0}));
});
test('clock regression, stale/future event and use after key disposal fail closed',()=>{
 let t=now;const p=producer({clock:()=>t});p.build(sample);t--;assert.throws(()=>p.build(sample),/clock/);
 for(const at of [now-600001,now+30001,NaN,Infinity])assert.throws(()=>producer().build({...sample,at}));
 p.close();assert.throws(()=>p.build(sample),/closed/);
});
test('control events are not converted into attack or contact evidence',()=>{
 for(const kind of ['rotated','restored','decoy_quarantined','decoy_released','oversized_target'])assert.equal(producer().build({...sample,kind,generation:null}),null);
});
test('generation correlation never claims a real visitor or person',()=>{
 const p=producer(),a=p.build(sample),b=p.build({...sample,sequence:2}),c=p.build({...sample,sequence:3,generation:2});
 assert.equal(a.event.correlation_key,b.event.correlation_key);assert.notEqual(a.event.correlation_key,c.event.correlation_key);assert.notEqual(a.event.event_id,b.event.event_id);
 assert.equal(a.source_tracking,'decoy_generation_only');
});
test('actual DecoyLab contacts pass unchanged reviewed signed collector handler',async()=>{
 const lab=new DecoyLab({clock:()=>now}),p=producer(),signingKey=randomBytes(32),seen=[];
 const handler=createCollectorSignedHandler({key:signingKey,collectorId,enabled:()=>true,clock:()=>now,writeEvent:async e=>{seen.push(e);return e.event_id;}});
 const old=lab.lure;await lab.handle(new Request('http://decoy.invalid'+old));lab.rotate();await lab.handle(new Request('http://decoy.invalid'+old));
 for(const source of lab.inspect()){
  const out=p.build(source);if(!out)continue;const body=Buffer.from(out.body),sig=signCollectorBytes({key:signingKey,collectorId,timestamp:now,body});
  const req=()=>new Request('http://collector.invalid/collector/events',{method:'POST',headers:{'content-type':'application/json','x-sko-collector-id':collectorId,'x-sko-collector-time':String(now),'x-sko-collector-signature':sig},body});
  assert.equal((await handler(req())).status,204);assert.equal((await handler(req())).status,204);
 }
 assert.equal(seen.length,4);assert.equal(seen[0].event_id,seen[1].event_id);assert.equal(seen[2].event_kind,'retired_lure_touched');assert.equal(seen[2].event_id,seen[3].event_id);
});
