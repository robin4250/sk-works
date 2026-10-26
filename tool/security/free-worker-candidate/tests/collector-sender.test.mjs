import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {Miniflare,Log,LogLevel} from 'miniflare';
const root=resolve(import.meta.dirname,'..'),collectorId='30000000-0000-0000-0000-000000000001';
const sourcePath=process.env.SKO_COLLECTOR_HANDLER_SOURCE;
assert(sourcePath,'Explicit pinned collector handler fixture source required');
const source=await readFile(sourcePath);
assert.equal(createHash('sha256').update(source).digest('hex'),'a893415c6cbbfb29df061c101fae1b802a25cabe343c8958c62916b423f75cda');
const {createSecurityCollectorHandler}=await import(pathToFileURL(resolve(sourcePath)));
const endpoint='https://ztktgquxvcxcjxtluspu.supabase.co/functions/v1/security-collector-ingest';
const serviceKey='e30.'+Buffer.from(JSON.stringify({role:'service_role'})).toString('base64url')+'.fixture';
async function fixture(t){
 const dir=await mkdtemp(join(tmpdir(),'sko-collector-sender-'));let mode='ok',mf,seen=[],committed=new Map(),dbCalls=0,errors=[];
 const handler=createSecurityCollectorHandler({baseUrl:'https://ztktgquxvcxcjxtluspu.supabase.co',serviceKey,enabled:()=>true,
  keys:[{collector_id:collectorId,key_version:7,key_hex:'33'.repeat(32)}],
  fetcher:async(url,init)=>{
   assert.equal(String(url),'https://ztktgquxvcxcjxtluspu.supabase.co/rest/v1/rpc/ingest_signed_security_collector_event');
   assert.equal(init.headers.apikey,serviceKey);assert.equal(init.headers.Authorization,'Bearer '+serviceKey);
   const envelope=JSON.parse(init.body).p_envelope,event=JSON.parse(Buffer.from(envelope.body_base64,'base64').toString());dbCalls++;
   const previous=committed.get(event.event_id);if(previous)assert.equal(previous,envelope.body_base64);else committed.set(event.event_id,envelope.body_base64);
   if(mode==='wrong_id')return Response.json('40000000-0000-4000-8000-000000000099');
   return Response.json(event.event_id);
  }});
 function make(){return new Miniflare({modules:true,scriptPath:join(root,'tests/collector-sender-fixture.mjs'),modulesRoot:root,
  modulesRules:[{type:'CompiledWasm',include:['**/*.wasm']}],compatibilityDate:'2026-07-30',
  durableObjects:{DECOY:{className:'SenderFixtureBroker',useSQLite:true}},durableObjectsPersist:dir,
  bindings:{DECOY_HOST:'decoy.invalid',DECOY_ENABLED:'true',COLLECTOR_ID:collectorId,STARTUP_SESSION_ID:'50000000-0000-4000-8000-000000000001',CAPABILITY_KEY_HEX:'11'.repeat(32),DERIVATION_KEY_HEX:'22'.repeat(32)},
  serviceBindings:{COLLECTOR:async request=>{
   try{
   assert.equal(request.url,endpoint);assert.equal(request.method,'POST');assert.equal(request.headers.get('authorization'),null);assert.equal(request.headers.get('apikey'),null);
   const raw=await request.clone().text();seen.push({body:raw,headers:Object.fromEntries(request.headers)});
   assert(!raw.includes(serviceKey));
   if(mode==='unavailable')return new Response(null,{status:503});
   if(mode==='unauthorized')return new Response(null,{status:401});
   if(mode==='redirect')return new Response(null,{status:302,headers:{location:'https://unreviewed.invalid/collector'}});
   const result=await handler(request);
   if(mode==='lost_ack')return new Response(null,{status:503});
   return result;
   }catch(error){errors.push(String(error));throw error;}
  }},log:new Log(LogLevel.ERROR)});}
 mf=make();t.after(async()=>{await mf.dispose();await rm(dir,{recursive:true,force:true});});
 const direct=async(path,body={})=>{const ns=await mf.getDurableObjectNamespace('DECOY'),stub=ns.get(ns.idFromName('security-decoy-v1'));return stub.fetch('https://fixture.invalid'+path,{method:'POST',body:JSON.stringify(body)});};
 const inspect=async()=>{const ns=await mf.getDurableObjectNamespace('DECOY');return(await ns.get(ns.idFromName('security-decoy-v1')).fetch('https://fixture.invalid/inspect')).json();};
 const observe=async()=>{await direct('/enable');const cap=await(await mf.dispatchFetch('https://decoy.invalid/synthetic-decoy/capability')).json();assert.equal((await mf.dispatchFetch('https://decoy.invalid/synthetic-decoy/g1/fixture-records',{headers:{'x-sko-decoy-capability':cap.capability}})).status,200);};
 return {direct,inspect,observe,seen,committed,errors,get dbCalls(){return dbCalls;},mode:value=>{mode=value;},restart:async()=>{await mf.dispose();mf=make();}};
}
test('OFF sender and reused keys cause no network, claim or receipt schema writes',async t=>{
 const f=await fixture(t);await f.observe();const before=await f.inspect();
 assert.equal((await(await f.direct('/deliver',{enabled:false})).json()).state,'disabled');
 assert.equal((await f.direct('/deliver',{reusedKey:true})).status,409);assert.equal(f.seen.length,0);assert.deepEqual(await f.inspect(),before);
});
test('actual workerd sender connects exact v2 bytes through the existing collector handler',async t=>{
 const f=await fixture(t);await f.observe();const before=await f.inspect();
 const result=await(await f.direct('/deliver')).json();assert.equal(result.state,'acknowledged',JSON.stringify({errors:f.errors,deliveryError:(await f.inspect()).deliveryError}));assert.equal(result.event_id,before.events[0].event_id);
 const after=await f.inspect();assert.deepEqual(after.events,before.events);assert.equal(after.outbox[0].state,'acknowledged');assert.equal(after.receipts[0].last_result,'acknowledged');
 assert.equal(f.committed.size,1);assert.equal(f.seen[0].body,before.events[0].body);assert.equal(f.seen[0].headers['x-sko-collector-key-version'],'7');assert.equal(f.dbCalls,1);
 assert.equal((await(await f.direct('/deliver')).json()).state,'idle');
});
test('unknown committed ACK retries identical event after restart and stores it once',async t=>{
 const f=await fixture(t);await f.observe();f.mode('lost_ack');assert.equal((await(await f.direct('/deliver')).json()).state,'pending');
 const original=(await f.inspect()).events[0];await f.restart();f.mode('ok');
 assert.equal((await(await f.direct('/deliver',{offset:1100})).json()).state,'acknowledged');
 assert.equal(f.committed.size,1);assert.equal(f.dbCalls,2);assert.equal(f.seen[0].body,f.seen[1].body);assert.equal((await f.inspect()).events[0].body,original.body);
});
test('fixed attempt/backoff limits hold a failed event without deleting evidence',async t=>{
 const f=await fixture(t);await f.observe();f.mode('unavailable');
 assert.equal((await(await f.direct('/deliver')).json()).state,'pending');assert.equal((await(await f.direct('/deliver')).json()).state,'idle');
 assert.equal((await(await f.direct('/deliver',{offset:1100})).json()).state,'pending');
 assert.equal((await(await f.direct('/deliver',{offset:6200})).json()).state,'held_attempts');
 assert.equal((await(await f.direct('/deliver',{offset:10000})).json()).state,'idle');assert.equal(f.seen.length,3);assert.equal((await f.inspect()).events.length,1);
});
test('expired, corrupted and unauthorized evidence is held without retiming or deleting it',async t=>{
 for(const kind of ['expired','corrupt','unauthorized']){
  const f=await fixture(t);await f.observe();const before=(await f.inspect()).events;
  if(kind==='corrupt')await f.direct('/corrupt');if(kind==='unauthorized')f.mode('unauthorized');
  const result=await(await f.direct('/deliver',kind==='expired'?{offset:600001}:{})).json();
  assert.equal(result.state,kind==='expired'?'held_expired':kind==='corrupt'?'held_invalid':'held_auth');
  assert.deepEqual((await f.inspect()).events,before);assert.equal(f.seen.length,kind==='unauthorized'?1:0);
 }
});
test('hard deadline works even when a fetch adapter ignores AbortSignal',async t=>{
 const f=await fixture(t);await f.observe();const start=Date.now();
 const result=await(await f.direct('/deliver',{ignoreAbort:true,timeoutMs:20})).json();
 assert.equal(result.state,'pending');assert(Date.now()-start<2000);assert.equal(f.seen.length,0);assert.equal((await f.inspect()).events.length,1);
});
test('actual edge fetch refuses redirects without exposing a signed event to another origin',async t=>{
 const f=await fixture(t);await f.observe();f.mode('redirect');
 assert.equal((await(await f.direct('/deliver')).json()).state,'held_redirect');
 assert.equal(f.seen.length,1);assert.equal(f.dbCalls,0);assert.equal((await f.inspect()).events.length,1);
});
test('concurrent calls claim once and a wrong collector ACK remains pending',async t=>{
 const f=await fixture(t);await f.observe();f.mode('wrong_id');
 const results=await Promise.all([f.direct('/deliver'),f.direct('/deliver')]);const states=await Promise.all(results.map(r=>r.json()));
 assert.deepEqual(states.map(x=>x.state).sort(),['idle','pending']);assert.equal(f.seen.length,1);
 assert.equal((await f.inspect()).outbox[0].state,'pending');
});
test('local receipt-write failure rolls back ACK and recovery retries the same committed event',async t=>{
 const f=await fixture(t);await f.observe();f.mode('unavailable');await f.direct('/deliver');await f.direct('/receipt-failure');
 f.mode('ok');assert.equal((await f.direct('/deliver',{offset:1100})).status,409);
 const held=await f.inspect();assert.equal(held.outbox[0].state,'inflight');assert.equal(held.receipts[0].last_result,'inflight');
 await f.direct('/remove-failure');assert.equal((await(await f.direct('/deliver',{offset:12000})).json()).state,'acknowledged');
 assert.equal(f.committed.size,1);assert.equal(f.seen[1].body,f.seen[2].body);
});
