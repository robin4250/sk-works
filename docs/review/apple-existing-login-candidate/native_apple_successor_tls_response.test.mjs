import {test} from 'node:test';
import assert from 'node:assert/strict';
import https from 'node:https';
import http from 'node:http';
import {mkdtempSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {createNativeAppleSuccessorTLSResponseSink} from './native_apple_successor_tls_response.mjs';

const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const bearer='synthetic-owner-request-bearer';
const credential=()=>({request_id:id(1),user_id:id(2),session_id:id(4),token_type:'bearer',
 access_token:'synthetic-access-only',refresh_token:'synthetic-refresh-only'});

async function fixture(t,listener,{plain=false}={}){
 const directory=mkdtempSync(join(tmpdir(),'sko-apple-tls-fixture-'));
 t.after(()=>rmSync(directory,{recursive:true,force:true}));
 let cert,key;
 if(!plain){
  execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-days','1',
   '-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1',
   '-keyout',join(directory,'key.pem'),'-out',join(directory,'cert.pem')],{stdio:'ignore'});
  cert=readFileSync(join(directory,'cert.pem'));key=readFileSync(join(directory,'key.pem'));
 }
 const server=plain?http.createServer(listener):https.createServer({key,cert,minVersion:'TLSv1.2'},listener);
 server.on('clientError',(_,socket)=>socket.destroy());
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 t.after(()=>new Promise(resolve=>{server.closeAllConnections();server.close(resolve);}));
 const origin=`${plain?'http':'https'}://127.0.0.1:${server.address().port}`;
 return {origin,call:(headers={})=>new Promise((resolve,reject)=>{
  const req=(plain?http:https).request(origin,{method:'POST',ca:cert,agent:false,
   headers:{authorization:`Bearer ${bearer}`,...headers}},res=>{
    let text='';res.setEncoding('utf8');res.on('data',chunk=>{text+=chunk;});
    res.on('end',()=>resolve({status:res.statusCode,headers:res.headers,text}));
   });req.on('error',reject);req.end();
 })};
}
const sink=(request,response,origin,extra={})=>createNativeAppleSuccessorTLSResponseSink({enabled:true,
 request,response,serverOrigin:origin,verifiedBearer:bearer,requestId:id(1),userId:id(2),originalSessionId:id(3),...extra});

test('same authenticated TLS response receives one bounded no-store envelope',async t=>{
 let origin,finished;
 const done=new Promise(resolve=>{finished=resolve;});
 const f=await fixture(t,async(req,res)=>{
  const deliver=sink(req,res,origin);
  const value=credential();value.toJSON=()=>{throw Error('must not serialize arbitrary adapter');};
  const first=await deliver(value),second=await deliver(value);finished({first,second});
 });origin=f.origin;
 const result=await f.call();assert.equal(result.status,200);
 assert.deepEqual(JSON.parse(result.text),{schema:1,...credential()});
 assert.match(result.headers['cache-control'],/no-store/);assert.equal(result.headers['vary'],'Authorization');
 assert.equal(result.headers['access-control-allow-origin'],undefined);
 assert.deepEqual(await done,{first:true,second:false});
});

test('foreign request/actor/SID consumes the local attempt without sending credentials',async t=>{
 let origin;
 const f=await fixture(t,async(req,res)=>{
  const deliver=sink(req,res,origin),type=req.headers['x-fixture-case'];
  const wrong=credential();if(type==='request')wrong.request_id=id(9);
  if(type==='actor')wrong.user_id=id(9);if(type==='session')wrong.session_id=id(3);
  assert.equal(await deliver(wrong),false);assert.equal(await deliver(credential()),false);
  res.writeHead(409,{'cache-control':'no-store'});res.end('unavailable');
 });origin=f.origin;
 for(const type of ['request','actor','session']){
  const result=await f.call({'x-fixture-case':type});assert.equal(result.status,409);
  assert.equal(result.text,'unavailable');assert.ok(!result.text.includes('synthetic-refresh'));
 }
});

test('plaintext with forwarded TLS headers and a different bearer are rejected',async t=>{
 let plainOrigin,tlsOrigin;
 const plain=await fixture(t,(req,res)=>{
  assert.throws(()=>sink(req,res,plainOrigin.replace('http:','https:')),/delivery_unavailable/);
  res.writeHead(403);res.end('unavailable');
 },{plain:true});plainOrigin=plain.origin;
 assert.equal((await plain.call({'x-forwarded-proto':'https'})).status,403);
 const tls=await fixture(t,(req,res)=>{
  assert.throws(()=>sink(req,res,tlsOrigin),/delivery_unavailable/);res.writeHead(403);res.end('unavailable');
 });tlsOrigin=tls.origin;
 assert.equal((await tls.call({authorization:'Bearer different-synthetic-user'})).status,403);
 assert.equal((await tls.call({authorization:[`Bearer ${bearer}`,'Bearer another-user']})).status,403);
});

test('a closed original TLS response cannot be reused as another delivery channel',async t=>{
 let origin,finished;
 const done=new Promise(resolve=>{finished=resolve;});
 const f=await fixture(t,async(req,res)=>{
  const deliver=sink(req,res,origin);res.end('closed');
  finished(await deliver(credential()));
 });origin=f.origin;
 assert.equal((await f.call()).text,'closed');assert.equal(await done,false);
});

test('unfinished response times out and cannot be retried',async t=>{
 let origin,finished;
 const done=new Promise(resolve=>{finished=resolve;});
 const f=await fixture(t,async(req,res)=>{
  const deliver=sink(req,res,origin,{timeoutMs:20});
  // Real TLS socket/response, but simulate an output stream that never finishes.
  res.end=()=>res;
  const first=await deliver(credential()),second=await deliver(credential());finished({first,second});
 });origin=f.origin;
 await assert.rejects(f.call());assert.deepEqual(await done,{first:false,second:false});
});
