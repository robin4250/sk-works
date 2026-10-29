// Disposable test helper only. No production key, listener or endpoint lives here.
import https from 'node:https';
import http from 'node:http';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {scannerRegistrationPath} from './qr-scanner-registration-https.mjs';
const run=promisify(execFile);
export async function createScannerTlsFixture(makeHandler,{plain=false,dropReply=()=>false}={}){
 const directory=await mkdtemp(join(tmpdir(),'sko-qr-registration-tls-'));let server;
 try {
  let key,cert;
  if(!plain){
   await run('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=localhost',
    '-addext','subjectAltName=DNS:localhost,IP:127.0.0.1','-keyout',join(directory,'key.pem'),'-out',join(directory,'cert.pem')]);
   key=await readFile(join(directory,'key.pem'));cert=await readFile(join(directory,'cert.pem'));
  }
  let handler;
  const listener=(request,response)=>{
   if(dropReply(request)){response.end=()=>{response.destroy();return response;};}
   void handler(request,response);
  };
  server=plain?http.createServer(listener):https.createServer({key,cert,minVersion:'TLSv1.2'},listener);
  server.on('clientError',(_,socket)=>socket.destroy());
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const origin=`${plain?'http':'https'}://127.0.0.1:${server.address().port}`;
  handler=makeHandler(origin.replace(/^http:/,'https:'));
  const call=(body,{headers={},raw,token,method='POST',path=scannerRegistrationPath,chunks,chunkPauseMs=0,abortWhen}={})=>new Promise((resolve,reject)=>{
   const bytes=raw===undefined?Buffer.from(JSON.stringify(body)):Buffer.from(raw);
   const request=(plain?http:https).request(new URL(path,origin),{method,ca:cert,agent:false,
    headers:{'content-type':'application/json',...(chunks?{}:{'content-length':bytes.length}),
     ...(token?{authorization:`Bearer ${token}`}:{ }),...headers}},response=>{
      const parts=[];let length=0;
      response.on('data',chunk=>{length+=chunk.length;if(length>32768){request.destroy();reject(Error('fixture response too large'));}else parts.push(Buffer.from(chunk));});
      response.on('error',reject);response.on('aborted',()=>reject(Error('fixture response aborted')));
      response.on('end',()=>{const text=Buffer.concat(parts).toString('utf8');let json;try{json=JSON.parse(text);}catch{json=null;}
       resolve({status:response.statusCode,headers:response.headers,text,json});});
   });request.on('error',reject);
   if(abortWhen)void Promise.resolve(abortWhen).then(()=>request.destroy(Error('fixture client abort')),()=>request.destroy(Error('fixture client abort')));
   request.setTimeout(10000,()=>request.destroy(Error('fixture HTTP timeout')));
   if(chunks){void(async()=>{try{for(const chunk of chunks){if(request.destroyed)return;request.write(chunk);if(chunkPauseMs)await new Promise(r=>setTimeout(r,chunkPauseMs));}if(!request.destroyed)request.end();}catch(error){request.destroy(error);}})();}
   else request.end(bytes);
  });
  return {origin,call,close:async()=>{
   server.closeAllConnections();await new Promise(resolve=>server.close(resolve));await rm(directory,{recursive:true,force:true});
  }};
 }catch(error){if(server){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}await rm(directory,{recursive:true,force:true});throw error;}
}
