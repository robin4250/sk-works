// Internal review-only sink. No listener, public route, Auth grant or client
// adoption. The endpoint must authenticate and reserve this exact request first.
import {IncomingMessage, ServerResponse} from 'node:http';
import {TLSSocket} from 'node:tls';
import {createHash, timingSafeEqual} from 'node:crypto';

const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const denied=()=>Error('apple_successor_delivery_unavailable');
const same=(a,b)=>typeof a==='string'&&typeof b==='string'&&timingSafeEqual(
 createHash('sha256').update(a).digest(),createHash('sha256').update(b).digest());

export function createNativeAppleSuccessorTLSResponseSink({enabled=false,request,response,
 serverOrigin,verifiedBearer,requestId,userId,originalSessionId,timeoutMs=5000}={}) {
 let origin;
 try{origin=new URL(serverOrigin);}catch{throw denied();}
 if(enabled!==true||origin.protocol!=='https:'||origin.username||origin.password||origin.search||origin.hash||origin.pathname!=='/'||
    !(request instanceof IncomingMessage)||!(response instanceof ServerResponse)||response.req!==request||
    !(request.socket instanceof TLSSocket)||request.socket.encrypted!==true||response.socket!==request.socket||
    request.method!=='POST'||request.headers.host!==origin.host||
    request.rawHeaders.filter((v,i)=>i%2===0&&v.toLowerCase()==='authorization').length!==1||
    request.rawHeaders.filter((v,i)=>i%2===0&&v.toLowerCase()==='host').length!==1||
    typeof verifiedBearer!=='string'||verifiedBearer.length<1||verifiedBearer.length>16384||/[\r\n]/.test(verifiedBearer)||
    !same(request.headers.authorization,`Bearer ${verifiedBearer}`)||
    !uuid.test(requestId??'')||!uuid.test(userId??'')||!uuid.test(originalSessionId??'')||
    !Number.isSafeInteger(timeoutMs)||timeoutMs<1||timeoutMs>30000)throw denied();
 // Scalars are captured from trusted, independently verified endpoint state.
 // Never accept a URL, user id or alternate response channel from the body.
 let attempted=false;
 return async credential=>{
  if(attempted)return false;
  attempted=true;
  let value;
  try{value={request_id:credential?.request_id,user_id:credential?.user_id,session_id:credential?.session_id,
   token_type:credential?.token_type,access_token:credential?.access_token,refresh_token:credential?.refresh_token};}catch{return false;}
  if(request.aborted||request.socket.destroyed||response.destroyed||response.headersSent||response.writableEnded||
     value.request_id!==requestId||value.user_id!==userId||
     !uuid.test(value.session_id??'')||value.session_id===originalSessionId||value.token_type!=='bearer'||
     !['access_token','refresh_token'].every(k=>typeof value[k]==='string'&&value[k].length>0&&value[k].length<=16384))return false;
  // Snapshot before awaiting; ignore all extra properties rather than serializing
  // an arbitrary object/getter/toJSON supplied by an adapter.
  const body=JSON.stringify({schema:1,request_id:requestId,user_id:userId,session_id:value.session_id,
   token_type:'bearer',access_token:value.access_token,refresh_token:value.refresh_token});
  if(Buffer.byteLength(body)>49152)return false;
  return new Promise(resolve=>{
   let settled=false;
   const finish=ok=>{if(settled)return;settled=true;clearTimeout(timer);
    response.off('finish',onFinish);response.off('close',onClose);response.off('error',onError);resolve(ok);};
   const onFinish=()=>finish(true),onClose=()=>finish(false),onError=()=>finish(false);
   const timer=setTimeout(()=>{finish(false);response.destroy();},timeoutMs);
   response.once('finish',onFinish);response.once('close',onClose);response.once('error',onError);
   try{
    response.writeHead(200,{'content-type':'application/json; charset=utf-8','content-length':Buffer.byteLength(body),
     'cache-control':'no-store, private','pragma':'no-cache','vary':'Authorization',
     'x-content-type-options':'nosniff','referrer-policy':'no-referrer'});
    response.end(body);
   }catch{finish(false);response.destroy();}
  });
 };
}

// true means Node flushed this response to its transport, NOT that the device
// received/adopted it. A lost response is unknown; never relink or resend blindly.
