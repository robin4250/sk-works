import {test,after} from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:https';
import * as fs from 'node:fs/promises';
import {mkdtempSync,readFileSync,rmSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash,generateKeyPairSync,sign} from 'node:crypto';
import {createArchiveByteStoreCandidate} from '../src/archive-byte-store-candidate.mjs';
import {createArchiveReadbackAttestorCandidate} from '../src/archive-readback-receipt-candidate.mjs';
import {createArchiveReadbackHTTPSVerifierCandidate} from '../src/archive-readback-https-candidate.mjs';

const secret='synthetic-readback-credential-never-log',authority='30000000-0000-0000-0000-000000000001';
const hash=x=>createHash('sha256').update(x).digest('hex'),keys=generateKeyPairSync('ed25519'),key=keys.publicKey.export({format:'jwk'});
const tlsRoot=mkdtempSync(join(tmpdir(),'sko-readback-tls-cert-'));
function certificate(name,san){
 const cert=join(tlsRoot,`${name}.crt`),privateKey=join(tlsRoot,`${name}.key`);
 execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-days','1','-keyout',privateKey,'-out',cert,'-subj',`/CN=${name}`,'-addext',`subjectAltName=${san}`],{stdio:'ignore'});
 return {cert:readFileSync(cert),key:readFileSync(privateKey)};
}
const tls=certificate('localhost','IP:127.0.0.1,DNS:localhost'),wrongHostTLS=certificate('elsewhere.local','DNS:elsewhere.local');
after(()=>rmSync(tlsRoot,{recursive:true,force:true}));
function deferred(){let resolve;return {promise:new Promise(r=>resolve=r),resolve:(...args)=>resolve(...args)};}
async function fixture(t,{handler,transportTLS=tls,tls12=false}={}){
 const root=await fs.mkdtemp(join(tmpdir(),'sko-readback-tls-bytes-'));await fs.chmod(root,0o700);
 const store=await createArchiveByteStoreCandidate({enabled:true,directory:root}),payload=Buffer.from('opaque fixture bytes without a custody claim');
 const descriptor=await store.retain({company_id:'10000000-0000-0000-0000-000000000001',event_id:'20000000-0000-0000-0000-000000000001',revision:2,snapshot_sha256:'a'.repeat(64),payload_sha256:hash(payload),payload});
 const attestor=createArchiveReadbackAttestorCandidate({enabled:true,authorityId:authority,store,key,signObservation:async raw=>sign(null,raw,keys.privateKey)});
 const calls=[];let observed=0;
 const server=createServer({...transportTLS,minVersion:tls12?'TLSv1.2':'TLSv1.3',...(tls12?{maxVersion:'TLSv1.2'}:{})},async(req,res)=>{
  req.on('error',()=>{});res.on('error',()=>{});
  const chunks=[];for await(const chunk of req)chunks.push(chunk);
  const body=Buffer.concat(chunks);calls.push({method:req.method,path:req.url,headers:{...req.headers},body});
  const json=value=>{const bytes=Buffer.from(JSON.stringify(value));res.writeHead(200,{'content-type':'application/json; charset=utf-8','cache-control':'no-store','content-length':bytes.length});res.end(bytes);};
  if(req.headers.authorization!==`Bearer ${secret}`){res.writeHead(401,{'content-type':'application/json','cache-control':'no-store'});res.end(JSON.stringify({secret}));return;}
  try{
   const input=JSON.parse(body.toString());
   const observe=async()=>{observed++;return attestor.observe(input);};
   if(handler)await handler({req,res,input,observe,json});else json(await observe());
  }catch{if(!res.destroyed){res.writeHead(503,{'content-type':'application/json','cache-control':'no-store'});res.end('{}');}}
 });
 server.on('tlsClientError',()=>{});server.on('clientError',(_error,socket)=>socket.destroy());
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
 const endpoint=`https://127.0.0.1:${server.address().port}/readback`;
 const config={enabled:true,endpoint,bearer:secret,ca:Buffer.from(transportTLS.cert),authorityId:authority,key:structuredClone(key),timeoutMs:5000,maxConcurrent:2};
 t.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));await fs.rm(root,{recursive:true,force:true});});
 return {server,calls,descriptor,config,observed:()=>observed,client:options=>createArchiveReadbackHTTPSVerifierCandidate({...config,...options})};
}
test('default OFF and request-supplied URL/key overrides cause no network work',async t=>{
 const f=await fixture(t);
 assert.throws(()=>createArchiveReadbackHTTPSVerifierCandidate({...f.config,enabled:false}));
 for(const endpoint of ['http://127.0.0.1/readback',`${f.config.endpoint}?next=x`,`${f.config.endpoint}#fragment`,'https://user:password@127.0.0.1/readback'])assert.throws(()=>f.client({endpoint}));
 await assert.rejects(f.client().verify(f.descriptor,{endpoint:'https://elsewhere.invalid'}));
 await assert.rejects(f.client().verify(f.descriptor,{key}));
 assert.equal(f.calls.length,0);
});
test('real certificate-verified TLS composes exact POST/bearer with stored-byte signature verifier',async t=>{
 const f=await fixture(t),value=await f.client().verify(f.descriptor);
 assert.equal(value.status,'readback_verified_unattested');assert.equal(value.receipt.payload.descriptor.object_id,f.descriptor.object_id);
 assert.equal(Object.hasOwn(value,'passed'),false);assert.equal(f.observed(),1);assert.equal(f.calls.length,1);
 const call=f.calls[0],body=JSON.parse(call.body.toString());
 assert.equal(call.method,'POST');assert.equal(call.path,'/readback');assert.equal(call.headers.host,new URL(f.config.endpoint).host);
 assert.equal(call.headers.authorization,`Bearer ${secret}`);assert.equal(call.body.length<=2048,true);
 assert.deepEqual(Object.keys(body),['authority_id','challenge','descriptor']);assert.equal(body.challenge.length,64);
});
test('untrusted CA, certificate hostname mismatch and TLS1.2 cannot reach the HTTP authority',async t=>{
 const good=await fixture(t);await assert.rejects(good.client({ca:undefined}).verify(good.descriptor));assert.equal(good.calls.length,0);
 const wrong=await fixture(t,{transportTLS:wrongHostTLS});await assert.rejects(wrong.client().verify(wrong.descriptor));assert.equal(wrong.calls.length,0);
 const obsolete=await fixture(t,{tls12:true});await assert.rejects(obsolete.client().verify(obsolete.descriptor));assert.equal(obsolete.calls.length,0);
});
test('redirect Location is never followed and bearer never reaches the second server',async t=>{
 let targetCalls=0;
 const target=createServer(tls,(_req,res)=>{targetCalls++;res.end('not an authority');});
 await new Promise(r=>target.listen(0,'127.0.0.1',r));t.after(async()=>{target.closeAllConnections();await new Promise(r=>target.close(r));});
 const f=await fixture(t,{handler:({res})=>{res.writeHead(307,{location:`https://127.0.0.1:${target.address().port}/capture`,'content-type':'application/json','cache-control':'no-store'});res.end('{}');}});
 await assert.rejects(f.client().verify(f.descriptor),e=>e.message==='archive HTTPS readback unavailable'&&!e.message.includes(secret));
 assert.equal(f.calls.length,1);assert.equal(targetCalls,0);assert.equal(f.observed(),0);
});
test('header, declared-byte and streamed-byte caps close the owned response without retry',{timeout:10000},async t=>{
 // A missing size cap must not pass merely because the total deadline later
 // rejects a stalled response. Keep JS deadlines paused for these real sockets.
 t.mock.timers.enable({apis:['setTimeout']});
 for(const mode of ['headers','declared','stream']){
  const closed=deferred();
  const f=await fixture(t,{handler:({res})=>{
   res.once('close',closed.resolve);
   const headers={'content-type':'application/json','cache-control':'no-store'};
   if(mode==='headers')headers['x-padding']='x'.repeat(9000);
   if(mode==='declared')headers['content-length']='4097';
   res.writeHead(200,headers);res.write(Buffer.alloc(mode==='stream'?4097:2,0x20));
  }});
  await assert.rejects(f.client().verify(f.descriptor));await closed.promise;
  assert.equal(f.calls.length,1);assert.equal(f.observed(),0);
 }
});
test('content type, compression, cache policy, malformed JSON and extra receipt fields reject',async t=>{
 for(const mode of ['type','encoding','cache','invalid','extra','signature','duplicates']){
  const f=await fixture(t,{handler:async({res,observe})=>{
   const headers={'content-type':mode==='type'?'text/plain':'application/json','cache-control':mode==='cache'?'public, max-age=30':'no-store'};
   if(mode==='encoding')headers['content-encoding']='gzip';
   let result=await observe();if(mode==='extra')result={...result,endpoint:'https://elsewhere.invalid'};
   if(mode==='signature')result={...result,signature:'0'.repeat(128)};
   res.writeHead(200,mode==='duplicates'?['content-type','application/json','content-type','application/json','cache-control','no-store']:headers);
   res.end(mode==='invalid'?'not JSON':JSON.stringify(result));
  }});
  await assert.rejects(f.client().verify(f.descriptor),e=>e.message==='archive HTTPS readback unavailable');assert.equal(f.calls.length,1);
 }
});
test('a saved signed TLS response cannot satisfy the next request challenge',async t=>{
 let cached;const f=await fixture(t,{handler:async({observe,json})=>json(cached??=await observe())}),client=f.client();
 assert.equal((await client.verify(f.descriptor)).status,'readback_verified_unattested');
 await assert.rejects(client.verify(f.descriptor));assert.equal(f.calls.length,2);assert.equal(f.observed(),1);
});
test('config mutations cannot redirect bearer, replace trusted CA/key or alter active bindings',async t=>{
 const entered=deferred(),release=deferred();
 const f=await fixture(t,{handler:async({observe,json})=>{entered.resolve();await release.promise;json(await observe());}});
 const config={...f.config},client=createArchiveReadbackHTTPSVerifierCandidate(config),expected=structuredClone(f.descriptor);
 const pending=client.verify(expected);await entered.promise;
 config.endpoint='https://elsewhere.invalid/steal';config.bearer='replacement-not-used';config.ca.fill(0);config.key.x=generateKeyPairSync('ed25519').publicKey.export({format:'jwk'}).x;
 expected.revision=99;release.resolve();const result=await pending;
 assert.equal(result.receipt.payload.descriptor.revision,2);assert.equal(f.calls[0].headers.authorization,`Bearer ${secret}`);assert.equal(f.calls.length,1);
});
test('abort closes only its own socket, admission rejects excess, and another operation survives',{timeout:10000},async t=>{
 const entered=deferred(),release=deferred(),closed=deferred();let count=0;
 const f=await fixture(t,{handler:async({res,observe,json})=>{
  const ordinal=++count;if(count===2)entered.resolve();
  if(ordinal===1)res.once('close',closed.resolve);
  await release.promise;if(!res.destroyed)json(await observe());
 }});
 const client=f.client({maxConcurrent:2}),abort=new AbortController(),first=assert.rejects(client.verify(f.descriptor,{signal:abort.signal})),second=client.verify(f.descriptor);
 await entered.promise;await assert.rejects(client.verify(f.descriptor));assert.equal(f.calls.length,2);
 abort.abort('private reason must not leak');await first;await closed.promise;release.resolve();
 assert.equal((await second).status,'readback_verified_unattested');assert.equal(f.observed(),1);
 const already=new AbortController();already.abort();await assert.rejects(client.verify(f.descriptor,{signal:already.signal}));assert.equal(f.calls.length,2);
});
test('total deadline closes stalled body and never retries; credential errors stay generic',{timeout:10000},async t=>{
 const entered=deferred(),closed=deferred();
 const f=await fixture(t,{handler:({res})=>{res.once('close',closed.resolve);entered.resolve();res.writeHead(200,{'content-type':'application/json','cache-control':'no-store'});res.write('{');}});
 // Keep actual TLS/HTTP IO, but advance the JS deadline only after the server
 // confirms the stalled-body stage. A slow CI handshake must not become the
 // deadline scenario accidentally (or leave this gate waiting after timeout).
 t.mock.timers.enable({apis:['setTimeout']});
 const failed=assert.rejects(f.client({timeoutMs:250}).verify(f.descriptor),e=>e.message==='archive HTTPS readback unavailable'&&!e.message.includes(secret));
 await entered.promise;t.mock.timers.tick(250);await failed;await closed.promise;t.mock.timers.reset();
 assert.equal(f.calls.length,1);assert.equal(f.observed(),0);
 const denied=await fixture(t);await assert.rejects(denied.client({bearer:'wrong-synthetic-bearer'}).verify(denied.descriptor),e=>e.message==='archive HTTPS readback unavailable'&&!e.message.includes(secret));
 assert.equal(denied.observed(),0);
});
