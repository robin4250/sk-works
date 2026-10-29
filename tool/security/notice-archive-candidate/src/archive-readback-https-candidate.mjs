// Default OFF client only. TLS plus a signed byte observation is not independent
// custody, WORM/retention, source authenticity, or permission to release a pin.
import {request} from 'node:https';
import {X509Certificate} from 'node:crypto';
import {createArchiveReadbackVerifierCandidate} from './archive-readback-receipt-candidate.mjs';

const fail=()=>Error('archive HTTPS readback unavailable');
const MAX_RESPONSE=4096,MAX_REQUEST=2048;
function configuredCA(value){
 if(value===undefined)return undefined;
 if(typeof value!=='string'&&!(value instanceof Uint8Array))throw fail();
 const bytes=Buffer.from(value);
 if(bytes.length<1||bytes.length>16384||!/^-----BEGIN CERTIFICATE-----\r?\n[A-Za-z0-9+/=\r\n]+-----END CERTIFICATE-----\s*$/.test(bytes.toString('ascii')))throw fail();
 try{return new X509Certificate(bytes).toString();}catch{throw fail();}
}
function callerSignal(options){
 if(options===undefined)return undefined;
 if(!options||typeof options!=='object'||Object.getPrototypeOf(options)!==Object.prototype)throw fail();
 const d=Object.getOwnPropertyDescriptors(options),keys=Reflect.ownKeys(d);
 if(keys.some(k=>k!=='signal')||keys.some(k=>!Object.hasOwn(d[k],'value')))throw fail();
 const signal=d.signal?.value;
 if(signal!==undefined&&!(signal instanceof AbortSignal))throw fail();
 return signal;
}
function receive(target,credential,ca,input,{signal,timeoutMs}){
 return new Promise((resolve,reject)=>{
  let req,res,timer,settled=false;
  const buffer=Buffer.alloc(MAX_RESPONSE);let length=0,declared;
  const complete=(error,value)=>{
   if(settled)return;settled=true;clearTimeout(timer);signal.removeEventListener('abort',abort);
   if(error){res?.destroy();req?.destroy();reject(fail());}else{resolve(value);}
  };
  const abort=()=>complete(true);
  if(signal.aborted){complete(true);return;}
  signal.addEventListener('abort',abort,{once:true});
  timer=setTimeout(abort,timeoutMs);
  try{
   const body=Buffer.from(JSON.stringify(input));if(body.length>MAX_REQUEST)throw fail();
   // No caller URL/headers/agent/TLS overrides. A private one-request agent is
   // owned by this request; cancel never destroys another operation's sockets.
   req=request(target,{method:'POST',agent:false,minVersion:'TLSv1.3',rejectUnauthorized:true,
    ca,maxHeaderSize:8192,headers:{authorization:`Bearer ${credential}`,
     'content-type':'application/json; charset=utf-8',accept:'application/json',
     'content-length':body.length,'cache-control':'no-store',connection:'close'}},response=>{
    if(settled){response.destroy();return;}
    res=response;res.on('error',abort);res.once('aborted',abort);
    const counts=new Map();for(let n=0;n<res.rawHeaders.length;n+=2){const k=res.rawHeaders[n].toLowerCase();counts.set(k,(counts.get(k)??0)+1);}
    const contentType=res.headers['content-type'],cache=res.headers['cache-control'];
    declared=res.headers['content-length'];
    if(res.statusCode!==200||typeof contentType!=='string'||!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(contentType)||
       typeof cache!=='string'||!/(?:^|,)\s*no-store\s*(?:,|$)/i.test(cache)||res.headers.location!==undefined||
       res.headers['content-encoding']!==undefined||
       ['content-type','content-length','cache-control','transfer-encoding'].some(k=>(counts.get(k)??0)>1)||
       (declared!==undefined&&(typeof declared!=='string'||!/^\d+$/.test(declared)||Number(declared)>MAX_RESPONSE))){abort();return;}
    res.on('data',chunk=>{
     if(settled)return;
     if(chunk.length>buffer.length-length){abort();return;}
     chunk.copy(buffer,length);length+=chunk.length;
    });
    res.once('end',()=>{
     if(settled)return;
     if(!res.complete||(declared!==undefined&&Number(declared)!==length)){abort();return;}
     try{complete(false,JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(buffer.subarray(0,length))));}
     catch{abort();}
    });
   });
   req.on('error',abort);req.once('upgrade',(_response,socket)=>{socket.destroy();abort();});
   req.end(body);
  }catch{abort();}
 });
}

// Configuration is selected by the server/operator, never by a read request.
// endpoint/bearer/CA/key are copied before asynchronous work and never logged.
export function createArchiveReadbackHTTPSVerifierCandidate({enabled=false,endpoint,bearer,ca,
 authorityId,key,now=Date.now,timeoutMs=5000,maxConcurrent=4}={}){
 try{
  if(!enabled||typeof endpoint!=='string'||typeof bearer!=='string'||bearer.length<16||bearer.length>4096||
     !/^[\x21-\x7e]+$/.test(bearer)||!Number.isSafeInteger(maxConcurrent)||maxConcurrent<1||maxConcurrent>16)throw fail();
  const target=new URL(endpoint);
  if(target.protocol!=='https:'||target.username||target.password||target.search||target.hash||!target.hostname)throw fail();
  const certificate=configuredCA(ca),credential=bearer;
  // Reuse the existing constructor validation/public-key pin semantics. No
  // callback runs here, and later caller mutations cannot replace this key.
  createArchiveReadbackVerifierCandidate({enabled:true,authorityId,key,now,timeoutMs,fetchObservation:async()=>{throw fail();}});
  const pin=Object.freeze({kty:key.kty,crv:key.crv,x:key.x});let active=0;
  return Object.freeze({async verify(expected,options){
   let external,owned,stop;
   try{
    external=callerSignal(options);if(external?.aborted||active>=maxConcurrent)throw fail();
    owned=new AbortController();stop=()=>owned.abort();external?.addEventListener('abort',stop,{once:true});
    if(external?.aborted)throw fail();active++;
    try{
     const verifier=createArchiveReadbackVerifierCandidate({enabled:true,authorityId,key:pin,now,timeoutMs,
      fetchObservation:input=>receive(target,credential,certificate,input,{signal:owned.signal,timeoutMs})});
     const result=await verifier.verify(expected);
     if(owned.signal.aborted||external?.aborted)throw fail();
     return result;
    }finally{active--;}
   }catch{throw fail();}finally{
    // Also abort when the outer verifier deadline wins before the transport's
    // own timer. Only the request created for this explicit operation is owned.
    owned?.abort();if(stop)external?.removeEventListener('abort',stop);
   }
  }});
 }catch{throw fail();}
}
