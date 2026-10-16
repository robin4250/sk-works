import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import {readFile} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {startIsolatedTransport} from './isolated_transport.mjs';
const token=randomBytes(32).toString('hex');
async function fixture(t,options={}){const f=await startIsolatedTransport({operatorToken:token,...options});t.after(()=>f.close());return f;}
const control=(f,path,auth=token)=>fetch(f.origin+path,{method:'POST',headers:{Authorization:`Bearer ${auth}`}});
test('loopback requests, authenticated rotation, retired lure, quarantine and recovery',async t=>{
 const f=await fixture(t);assert.match(f.origin,/^http:\/\/127\.0\.0\.1:\d+$/);
 const first=f.inspect().lure;assert.equal((await fetch(f.origin+first)).status,200);
 assert.equal((await fetch(f.origin+'/operator/rotate',{method:'POST'})).status,403);
 assert.equal((await control(f,'/operator/rotate','bad')).status,403);assert.equal(f.inspect().lure,first);
 assert.equal((await control(f,'/operator/rotate')).status,204);const second=f.inspect().lure;assert.notEqual(second,first);
 assert.equal((await fetch(f.origin+first)).status,200);assert.equal((await fetch(f.origin+second)).status,200);
 assert.equal((await control(f,'/operator/quarantine')).status,204);assert.equal((await fetch(f.origin+second)).status,503);
 assert.equal((await fetch(f.origin+'/normal-sko-route')).status,404);
 assert.equal((await control(f,'/operator/release')).status,204);assert.equal((await fetch(f.origin+second)).status,200);
});
test('body and target bounds reject without echo or identity/header retention',async t=>{
 const f=await fixture(t,{maxBodyBytes:8,maxUrlBytes:64});const secret='never-log-this-secret';
 const r=await fetch(f.origin+f.inspect().lure,{method:'POST',body:secret,headers:{'X-Forwarded-For':secret}});
 assert.equal(r.status,413);assert.equal(await r.text(),'');
 assert.equal((await fetch(f.origin+'/'+secret.repeat(4))).status,414);
 assert.ok(!JSON.stringify(f.inspect()).includes(secret));
});
test('chunked body limit enforced without content length',async t=>{
 const f=await fixture(t,{maxBodyBytes:8});
 const status=await new Promise((resolve,reject)=>{const req=http.request(f.origin+f.inspect().lure,{method:'POST'},r=>{r.resume();resolve(r.statusCode);});req.on('error',reject);req.write('12345');req.end('67890');});assert.equal(status,413);
});
test('bounded rate window recovers, proxy headers cannot evade global limits',async t=>{
 let time=1000;const f=await fixture(t,{rateLimit:2,clock:()=>time});
 assert.equal((await fetch(f.origin+'/a')).status,404);assert.equal((await fetch(f.origin+'/b')).status,404);
 assert.equal((await fetch(f.origin+'/c',{headers:{'X-Forwarded-For':'changed'}})).status,429);
 time+=1000;assert.equal((await fetch(f.origin+'/d')).status,404);
});
test('slow request occupies bounded concurrency then deadline releases it',async t=>{
 const f=await fixture(t,{maxConcurrent:1,deadlineMs:150});
 const pending=await new Promise(resolve=>{const req=http.request(f.origin+'/hold',{method:'POST',headers:{'Content-Length':4}},r=>{r.resume();});req.on('error',()=>{});req.write('x');
 const poll=()=>{if(f.inspect().active===1)resolve(req);else setTimeout(poll,2);};poll();});
 assert.equal((await fetch(f.origin+'/other')).status,503);
 await new Promise(resolve=>pending.once('close',resolve));
 assert.equal((await fetch(f.origin+'/after')).status,404);
});
test('incomplete headers time out and do not keep a fixture socket open',async t=>{
 const f=await fixture(t,{deadlineMs:50});await new Promise((resolve,reject)=>{
 const socket=net.connect(new URL(f.origin).port,'127.0.0.1',()=>socket.write('GET / HTTP/1.1\r\nX-Slow: '));
 socket.on('close',resolve);socket.on('error',reject);});
});
test('metadata drops and expiration explicit, copies cannot change queue, clock regression fails closed',async t=>{
 let time=1000;const f=await fixture(t,{eventCapacity:2,retentionMs:10,clock:()=>time});
 for(let i=0;i<3;i++)await fetch(f.origin+'/unrelated');
 const s=f.inspect();assert.equal(s.events.length,2);assert.equal(s.metrics.dropped,1);s.events.length=0;assert.equal(f.inspect().events.length,2);
 time+=10;assert.equal(f.inspect().events.length,0);assert.equal(f.inspect().metrics.expired,2);
 time=999;assert.equal((await fetch(f.origin+'/a')).status,503);
});
test('invalid configuration cannot bind or silently widen limits',async()=>{
 await assert.rejects(startIsolatedTransport({operatorToken:'short'}));
 await assert.rejects(startIsolatedTransport({operatorToken:token,maxConcurrent:999}));
});
test('isolation manifest keeps deployment closed and adapter has no credential or outbound integration',async()=>{
 const manifest=JSON.parse(await readFile(new URL('./isolated_transport_manifest.json',import.meta.url),'utf8'));
 assert.equal(manifest.deployment_ready,false);assert.equal(manifest.bind_address,'127.0.0.1');
 assert.deepEqual(manifest.production_routes,[]);assert.deepEqual(manifest.environment_credentials_consumed,[]);
 const source=await readFile(new URL('./isolated_transport.mjs',import.meta.url),'utf8');
 assert.ok(!/process\.env|fetch\(|http\.request|https|net\.connect|supabase|child_process/.test(source));
 assert.match(source,/server\.listen\(0,'127\.0\.0\.1'/);
});
