// Review-only/default OFF. This factory does NOT start a listener, publish a
// route, grant a pool role, select a project from request input, or enable QR.
import {IncomingMessage,ServerResponse} from 'node:http';
import {TLSSocket} from 'node:tls';
import {verifyScannerRegistrationBearer} from './qr-scanner-verified-session.mjs';
import {createScannerRegistrationChallengeAdapter} from './qr-scanner-challenge-adapter.mjs';
import {createScannerRegistrationProofIssuer} from './qr-scanner-proof-issuer.mjs';
import {createRecoverableScannerRegistrationAdapter} from './qr-scanner-registration-recovery.mjs';

export const scannerRegistrationPath='/qr/scanner/registration';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const keyHex=/^302a300506032b6570032100[0-9a-f]{64}$/;
const publicError=Object.freeze({schema:1,error:'登録結果を確認できません。元の要求を照合してください。'});
class Rejected extends Error{constructor(status){super('scanner request unavailable');this.status=status;}}
const reject=status=>new Rejected(status);
const bounded=async(promise,ms,status)=>{let timer;try{return await Promise.race([promise,new Promise((_,no)=>{timer=setTimeout(()=>no(reject(status)),ms);})]);}finally{clearTimeout(timer);}};
function singleHeader(request,name){
 const values=[];for(let i=0;i<request.rawHeaders.length;i+=2){if(request.rawHeaders[i].toLowerCase()===name)values.push(request.rawHeaders[i+1]);}
 if(values.length>1)throw reject(400);return values[0];
}
function readBody(request,expectedLength,ms){
 return new Promise((resolve,no)=>{
  let size=0;const chunks=[];
  const cleanup=()=>{clearTimeout(timer);request.off('data',data);request.off('end',end);request.off('error',error);request.off('aborted',aborted);};
  const fail=status=>{cleanup();request.pause();no(reject(status));};
  const data=chunk=>{size+=chunk.length;if(size>8192){fail(413);return;}chunks.push(Buffer.from(chunk));};
  const end=()=>{cleanup();if(expectedLength!==undefined&&expectedLength!==size){no(reject(400));return;}try{
   resolve(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks))));
  }catch{no(reject(400));}};
  const error=()=>fail(400),aborted=()=>fail(400);
  const timer=setTimeout(()=>fail(408),ms);
  request.on('data',data);request.once('end',end);request.once('error',error);request.once('aborted',aborted);
 });
}
function parseBody(value){
 if(value===null||typeof value!=='object'||Array.isArray(value)||value.schema!==1||!uuid.test(value.requestId??''))throw reject(400);
 const operations={challenge:['companyId','deviceId','publicKeyHex'],challenge_result:['companyId','deviceId','publicKeyHex'],proof:['challengeId','password'],complete:['challengeId','signature','proof'],result:['challengeId','companyId','deviceId','publicKeyHex']};
 if(typeof value.operation!=='string'||!Object.hasOwn(operations,value.operation))throw reject(400);
 const fields=operations[value.operation];
 if(Object.keys(value).length!==fields.length+3||Object.keys(value).some(k=>!['schema','requestId','operation',...fields].includes(k)))throw reject(400);
 for(const name of ['companyId','deviceId','challengeId'])if(fields.includes(name)&&!uuid.test(value[name]??''))throw reject(400);
 if(fields.includes('publicKeyHex')&&(typeof value.publicKeyHex!=='string'||!keyHex.test(value.publicKeyHex)))throw reject(400);
 if(value.operation==='proof'&&(typeof value.password!=='string'||value.password.length>1024))throw reject(400);
 if(value.operation==='complete'&&(typeof value.signature!=='string'||!/^[A-Za-z0-9_-]{86}$/.test(value.signature)||
  Buffer.from(value.signature,'base64url').toString('base64url')!==value.signature||
  typeof value.proof!=='string'||!/^[0-9a-f]{64}$/.test(value.proof)))throw reject(400);
 return value;
}

export function createScannerRegistrationHttpsHandler({enabled=false,publicOrigin,projectOrigin,expectedIssuer,publicKey,
 pool,admitVerifiedRequest,fetchImpl=globalThis.fetch,requestTimeoutMs=15000,bodyTimeoutMs=2000,authTimeoutMs=5000,admissionTimeoutMs=1000}={}){
 let origin;
 if(enabled){
  try{origin=new URL(publicOrigin);}catch{throw TypeError('trusted scanner HTTPS configuration required');}
  if(origin.protocol!=='https:'||origin.username||origin.password||origin.search||origin.hash||!['','/'].includes(origin.pathname)||
   typeof pool?.connect!=='function'||typeof admitVerifiedRequest!=='function'||typeof fetchImpl!=='function'||
   !Number.isInteger(requestTimeoutMs)||requestTimeoutMs<1||requestTimeoutMs>20000||
   !Number.isInteger(bodyTimeoutMs)||bodyTimeoutMs<1||bodyTimeoutMs>10000||
   !Number.isInteger(authTimeoutMs)||authTimeoutMs<1||authTimeoutMs>10000||
   !Number.isInteger(admissionTimeoutMs)||admissionTimeoutMs<1||admissionTimeoutMs>5000)throw TypeError('trusted scanner HTTPS configuration required');
 }
 const attempts=new WeakSet();
 return async function handle(request,response){
  if(!(request instanceof IncomingMessage)||!(response instanceof ServerResponse)||response.req!==request)return false;
  let replied=false,closed=false,requestFailed=false;
  // Authentication may still be awaiting I/O when a client aborts a partial
  // body. Native stream errors must remain handled even outside readBody().
  const requestError=()=>{requestFailed=true;},responseError=()=>{closed=true;};
  request.on('error',requestError);request.once('close',()=>request.off('error',requestError));
  response.on('error',responseError);response.once('close',()=>response.off('error',responseError));
  const active=()=>{if(closed||requestFailed||request.aborted||request.socket.destroyed||response.destroyed||response.writableEnded)throw reject(503);};
  const reply=(status,value)=>{
   if(replied||closed||response.destroyed||response.headersSent||response.writableEnded)return Promise.resolve(false);
   replied=true;const bytes=Buffer.from(JSON.stringify(value));
   if(bytes.length>16384){response.destroy();return Promise.resolve(false);}
   return new Promise(resolve=>{
    const finish=ok=>{clearTimeout(timer);response.off('finish',sent);response.off('close',lost);response.off('error',lost);resolve(ok);};
    const sent=()=>finish(true),lost=()=>finish(false);
    const timer=setTimeout(()=>{finish(false);response.destroy();},2000);
    response.once('finish',sent);response.once('close',lost);response.once('error',lost);
    try{
     response.writeHead(status,{'content-type':'application/json; charset=utf-8','content-length':bytes.length,
      'cache-control':'no-store','pragma':'no-cache','vary':'Authorization','x-content-type-options':'nosniff','connection':'close'});
     response.end(bytes);
    }catch{finish(false);response.destroy();}
   });
  };
  const onClose=()=>{closed=true;};response.once('close',onClose);
  const run=async()=>{
   if(attempts.has(request))throw reject(400);
   attempts.add(request);
   if(!enabled)throw reject(404);
   if(!(request.socket instanceof TLSSocket)||request.socket.encrypted!==true||response.socket!==request.socket)throw reject(403);
   if(request.method!=='POST'||request.url!==scannerRegistrationPath)throw reject(404);
   if(request.rawHeaders.length>128||request.rawHeaders.reduce((n,v)=>n+Buffer.byteLength(v),0)>20000)throw reject(400);
   if(singleHeader(request,'host')!==origin.host)throw reject(400);
   const originHeader=singleHeader(request,'origin');if(originHeader!==undefined&&originHeader!==origin.origin)throw reject(403);
   const authorization=singleHeader(request,'authorization'),match=/^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/.exec(authorization??'');
   if(!match||match[1].length>16384)throw reject(401);
   if(!/^application\/json(?:;\s*charset=utf-8)?$/i.test(singleHeader(request,'content-type')??'')||singleHeader(request,'content-encoding')!==undefined)throw reject(400);
   const length=singleHeader(request,'content-length');
   if(length!==undefined&&(!/^\d+$/.test(length)||Number(length)>8192))throw reject(413);
   let initializeVerifiedSession;
   try{initializeVerifiedSession=await verifyScannerRegistrationBearer({enabled:true,projectOrigin,expectedIssuer,publicKey,bearer:match[1],fetchImpl,timeoutMs:authTimeoutMs});}
   catch{throw reject(401);}
   active();
   const body=parseBody(await readBody(request,length===undefined?undefined:Number(length),bodyTimeoutMs));active();
   // Token has already passed the exact-project Auth verifier. Admission gets
   // only fixed verified principal/scalar scope, never the bearer or password.
   const claims=JSON.parse(Buffer.from(match[1].split('.')[1],'base64url').toString('utf8'));
   const admission=Object.freeze({actor:claims.sub,session:claims.session_id,operation:body.operation,requestId:body.requestId});
   if(await bounded(Promise.resolve().then(()=>admitVerifiedRequest(admission)),admissionTimeoutMs,503)!==true)throw reject(429);
   active();let result;
   const requestPool={connect:async()=>{
    active();const client=await pool.connect();
    try{active();return client;}catch(error){client.release();throw error;}
   }};
   if(body.operation==='challenge'||body.operation==='challenge_result'){
    const adapter=createScannerRegistrationChallengeAdapter({pool:requestPool,initializeVerifiedSession});
    const target={companyId:body.companyId,deviceId:body.deviceId,keyHex:body.publicKeyHex};
    result={challenge:body.operation==='challenge'?await adapter.issue(target):await adapter.read(target)};
   }
   else if(body.operation==='proof')result=await createScannerRegistrationProofIssuer({pool:requestPool,initializeVerifiedSession}).issue({challengeId:body.challengeId,password:body.password});
   else {
    const adapter=createRecoverableScannerRegistrationAdapter({enabled:true,pool:requestPool,initializeVerifiedSession});
    if(body.operation==='complete')result=await adapter.complete({challengeId:body.challengeId,signature:Buffer.from(body.signature,'base64url'),reauthenticationProof:body.proof});
    else result={receipt:await adapter.read({challengeId:body.challengeId,companyId:body.companyId,deviceId:body.deviceId,keyHex:body.publicKeyHex})};
   }
   active();return reply(200,{schema:1,requestId:body.requestId,operation:body.operation,...result});
  };
  try{await bounded(run(),requestTimeoutMs,503);}
  catch(error){await reply(error instanceof Rejected?error.status:503,publicError);}
  finally{response.off('close',onClose);if(!request.complete&&replied){response.once('finish',()=>request.destroy());if(response.writableFinished)request.destroy();}}
 };
}
