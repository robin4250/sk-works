import test from 'node:test';import assert from 'node:assert/strict';import http from 'node:http';
import {platformQuery,sanitizePlatformRows,collectPlatformWindow} from './platform_log_adapter.mjs';
const base={source:'edge_logs',from:'2026-10-16T10:00:00.000Z',to:'2026-10-16T10:05:00.000Z',hmacKey:Buffer.alloc(32,7),keyEpoch:1};
const row={id:'fixture-event',timestamp:'2026-10-16T10:01:00.123456',status:'403',target:'/rest/v1/private?token=secret',headers:{authorization:'secret'},ip:'192.0.2.1',body:'private',event_message:'secret'};
test('strict sanitized projection, HMAC identity/target, conservative outcome',()=>{
 const out=sanitizePlatformRows({...base,rows:[row]});assert.equal(out.events[0].result,'forbidden');assert.equal(out.events[0].occurred_at,'2026-10-16T10:01:00.123Z');
 assert.doesNotMatch(JSON.stringify(out),/secret|192\.0|private|authorization|headers|body|event_message/);
 assert.equal(out.events[0].event_key,sanitizePlatformRows({...base,rows:[{...row,status:200}]}).events[0].event_key);
 assert.notEqual(out.events[0].event_key,sanitizePlatformRows({...base,keyEpoch:2,rows:[row]}).events[0].event_key);
 assert.equal(sanitizePlatformRows({...base,rows:[{...row,status:200}]}).events[0].result,'http_success');
 assert.equal(sanitizePlatformRows({...base,source:'auth_audit_logs',rows:[row]}).events[0].result,'unknown');
 assert.equal(sanitizePlatformRows({...base,source:'postgres_logs',rows:[{...row,sqlstate:'42501'}]}).events[0].result,'permission_denied');
});
test('bad source/window, duplicate, outside-window fail closed; capacity explicit',()=>{
 assert.throws(()=>platformQuery("edge_logs' union select"));assert.throws(()=>sanitizePlatformRows({...base,rows:[row,row]}));
 assert.throws(()=>sanitizePlatformRows({...base,rows:[{...row,timestamp:base.to}]}));
 const rows=Array.from({length:1001},(_,i)=>({...row,id:`id-${i}`}));const out=sanitizePlatformRows({...base,rows});assert.equal(out.coverage,'capacity_limited');assert.equal(out.events.length,1000);
});
test('actual loopback HTTP response traverses fixed production-shaped GET adapter; failures redact errors',async()=>{
 let request;const server=http.createServer((req,res)=>{request=req;res.setHeader('content-type','application/json');res.end(JSON.stringify({result:[row]}));});await new Promise(r=>server.listen(0,'127.0.0.1',r));
 try{const fetchImpl=async(url,options)=>{
  assert.equal(url.origin,'https://api.supabase.com');assert.equal(options.redirect,'error');assert.equal(url.searchParams.get('iso_timestamp_start'),base.from);assert.doesNotMatch(url.searchParams.get('sql'),/event_message|headers|select \*/);return fetch(`http://127.0.0.1:${server.address().port}${url.pathname}${url.search}`,options);
 };
 const out=await collectPlatformWindow({...base,projectRef:'abcdefghijklmnopqrst',managementToken:'fixture-token-not-production',fetchImpl});assert.equal(out.events[0].result,'forbidden');assert.equal(request.headers.authorization,'Bearer fixture-token-not-production');
 await assert.rejects(collectPlatformWindow({...base,projectRef:'abcdefghijklmnopqrst',managementToken:'fixture-token-not-production',fetchImpl:async()=>{throw Error('secret token');}}),/^Error: Platform log collection unavailable$/);
 }finally{await new Promise(r=>server.close(r));}
});
