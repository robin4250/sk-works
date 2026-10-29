// OFF/unhosted composition. No registration/provenance API, data export, source
// release or independent custody. Caller/body metadata never authenticates ACL.
import {createServer} from 'node:https';
import {performance} from 'node:perf_hooks';
import {createManagementTransport} from '../../free-worker-candidate/issuer/management-issuer-transport.mjs';
import {createArchiveReadbackAttestorCandidate} from './archive-readback-receipt-candidate.mjs';
import {snapshotArchiveByteDescriptorCandidate} from './archive-byte-store-candidate.mjs';
const fail=()=>Error('archive readback server unavailable');
const uuid=x=>typeof x==='string'&&/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(x);
const exact=(x,keys)=>x&&typeof x==='object'&&!Array.isArray(x)&&Object.keys(x).sort().join(',')===keys;
function descriptor(row){return snapshotArchiveByteDescriptorCandidate({status:'stored_unattested',schema:1,
 company_id:row.company_id,event_id:row.event_id,revision:Number(row.revision),snapshot_sha256:row.snapshot_sha256,
 payload_sha256:row.payload_sha256,byte_length:row.byte_length,object_id:row.object_id});}
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
function material(value){if(typeof value!=='string'&&!(value instanceof Uint8Array))throw fail();const b=Buffer.from(value);if(!b.length||b.length>65536)throw fail();return b;}

// The configured pool must support pg Pool semantics, including release(true)
// destroying ONLY the checked-out connection on deadline/disconnect. A real
// least-privilege pool and authenticated registry population remain prerequisites.
export function createArchiveReadbackServerCandidate({enabled=false,endpoint,tls,auth,pool,store,
 authorityId,key,signObservation,now=Date.now,timeoutMs=5000,maxConcurrent=4}={}){
 try{
  if(!enabled||!uuid(authorityId)||!tls||!pool||typeof pool.connect!=='function'||!store||typeof store.restore!=='function'||typeof signObservation!=='function'||typeof now!=='function'||
   !Number.isSafeInteger(timeoutMs)||timeoutMs<50||timeoutMs>10000||!Number.isSafeInteger(maxConcurrent)||maxConcurrent<1||maxConcurrent>16)throw fail();
  const target=new URL(endpoint);if(target.protocol!=='https:'||target.username||target.password||target.search||target.hash)throw fail();
  // Capture trusted adapter configuration before serving. The existing Auth
  // transport verifies /user with the exact bearer, not decoded claims alone.
  const configuration=Object.freeze({url:auth?.url,publicKey:auth?.publicKey,serviceBearer:auth?.serviceBearer,fetchImpl:auth?.fetchImpl??fetch});
  const connect=pool.connect.bind(pool),restore=store.restore.bind(store),sign=signObservation;
  // Validate the pinned observation key before creating any listener.
  createArchiveReadbackAttestorCandidate({enabled:true,authorityId,key,store:{restore},signObservation:sign,now,timeoutMs});
  const pin=Object.freeze({kty:key.kty,crv:key.crv,x:key.x});let active=0;
  const small=(res,status)=>{if(!res.destroyed&&!res.headersSent){res.writeHead(status,{'content-type':'application/json','cache-control':'no-store',connection:'close'});res.end('{"error":"archive readback unavailable"}');}};
  const server=createServer({key:material(tls.key),cert:material(tls.cert),minVersion:'TLSv1.3',maxHeaderSize:8192,
   headersTimeout:timeoutMs,requestTimeout:timeoutMs},async(req,res)=>{
   const counts=new Map();for(let i=0;i<req.rawHeaders.length;i+=2){const h=req.rawHeaders[i].toLowerCase();counts.set(h,(counts.get(h)??0)+1);}
   if(req.method!=='POST'||req.url!==target.pathname||req.headers.host!==target.host||
    ['host','authorization','content-type','content-length','transfer-encoding'].some(h=>(counts.get(h)??0)>1)||
    req.headers.origin!==undefined||req.headers['content-encoding']!==undefined){small(res,404);return;}
   const authorization=req.headers.authorization;
   if(typeof authorization!=='string'||!/^Bearer [A-Za-z0-9_.-]{16,16384}$/.test(authorization)){small(res,401);return;}
   if(active>=maxConcurrent){small(res,503);return;}active++;
   const controller=new AbortController(),deadlineAt=performance.now()+timeoutMs;let leased,released=false,committed=false,timer,cleanup=()=>{};
   const discard=()=>{if(leased&&!released){released=true;try{leased.release(true);}catch{}}};
   const abort=()=>{controller.abort();discard();};
   const check=()=>{if(controller.signal.aborted||req.aborted||res.destroyed||performance.now()>=deadlineAt){abort();throw fail();}};
   const deadline=new Promise((_,reject)=>{controller.signal.addEventListener('abort',()=>reject(fail()),{once:true});});deadline.catch(()=>{});
   timer=setTimeout(abort,timeoutMs);req.on('error',()=>{});req.once('aborted',abort);
   const disconnected=()=>{if(!res.writableFinished)abort();};res.once('close',disconnected);
   const bounded=work=>Promise.race([Promise.resolve().then(()=>{check();return work();}),deadline]);
   try{
    if(typeof req.headers['content-type']!=='string'||!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(req.headers['content-type']))throw fail();
    const bearer=authorization.slice(7);
    const database=createManagementTransport({...configuration,callerBearer:bearer,now,timeoutMs:Math.min(timeoutMs,5000),signal:controller.signal});
    const caller=await bounded(()=>database.authenticate());check();
    const claims=JSON.parse(Buffer.from(bearer.split('.')[1],'base64url').toString('utf8'));
    const actor=caller.actorId,session=caller.sessionId,expires=claims.exp*1000;
    if(!uuid(actor)||!uuid(session)||claims.sub!==actor||claims.session_id!==session||!Number.isSafeInteger(expires))throw fail();
    const live=()=>{check();if(!Number.isSafeInteger(now())||now()>=expires)throw fail();};live();
    const declared=req.headers['content-length'];if(declared!==undefined&&(!/^\d+$/.test(declared)||Number(declared)>2048))throw fail();
    const bytes=await bounded(()=>new Promise((resolve,reject)=>{
     const buffer=Buffer.alloc(2048);let length=0;
     const data=chunk=>{if(chunk.length>buffer.length-length){cleanup();reject(fail());return;}chunk.copy(buffer,length);length+=chunk.length;};
     const end=()=>{cleanup();resolve(buffer.subarray(0,length));};
     const error=()=>{cleanup();reject(fail());};
     cleanup=()=>{req.off('data',data);req.off('end',end);req.off('aborted',error);req.off('error',error);req.pause();};
     req.on('data',data);req.once('end',end);req.once('aborted',error);req.once('error',error);
    }));live();
    const input=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
    if(!exact(input,'authority_id,challenge,descriptor')||input.authority_id!==authorityId||typeof input.challenge!=='string'||!/^[a-f0-9]{64}$/.test(input.challenge))throw fail();
    const expected=snapshotArchiveByteDescriptorCandidate(input.descriptor),challenge=input.challenge;
    const acquisition=Promise.resolve().then(()=>connect()).then(client=>{if(controller.signal.aborted||performance.now()>=deadlineAt){controller.abort();try{client.release(true);}catch{}throw fail();}return client;});
    leased=await bounded(()=>acquisition);check();
    if(typeof leased.query!=='function'||typeof leased.release!=='function')throw fail();
    await bounded(()=>leased.query('begin'));
    await bounded(()=>leased.query("select set_config('statement_timeout',$1,true),set_config('lock_timeout',$1,true),set_config('request.jwt.claims',$2,true)",
     [`${timeoutMs}ms`,JSON.stringify({sub:actor,session_id:session,role:'authenticated',is_anonymous:false})]));
    const selected=await bounded(()=>leased.query('select * from archive_readback_private.authority_records where object_id=$1 for share',[expected.object_id]));live();
    if(selected.rows.length!==1)throw fail();const row=selected.rows[0],saved=descriptor(row);
    if(row.authority_id!==authorityId||row.owner_id!==actor||!equal(saved,expected)||typeof row.deployment_id!=='string')throw fail();
    const savedCompany=row.company_id,savedDeployment=row.deployment_id;
    const guard=async()=>{
     live();const sid=await bounded(()=>leased.query('select private.require_reauthentication_session() as sid'));
     if(sid.rows.length!==1||sid.rows[0].sid!==session)throw fail();
     const result=await bounded(()=>leased.query('select security_management_issuer_private.binding($1,$2,$3,$4,true) as binding',[actor,session,savedCompany,savedDeployment]));
     live();if(result.rows.length!==1||!result.rows[0].binding)throw fail();
     return JSON.stringify(result.rows[0].binding);
    };
    const before=await guard();
    const attestor=createArchiveReadbackAttestorCandidate({enabled:true,authorityId,key:pin,now,timeoutMs,
     store:{restore:async d=>{live();const b=await restore(d);live();return b;}},
     signObservation:async b=>{live();const signature=await sign(b);live();return signature;}});
    const receipt=await bounded(()=>attestor.observe({authority_id:authorityId,challenge,descriptor:saved}));
    if(await guard()!==before)throw fail();live();
    await bounded(()=>leased.query('commit'));committed=true;live();
    const output=Buffer.from(JSON.stringify(receipt));if(output.length>4096)throw fail();
    live();res.writeHead(200,{'content-type':'application/json','cache-control':'no-store','content-length':output.length,connection:'close'});res.end(output);
   }catch{small(res,503);}
   finally{
    clearTimeout(timer);cleanup();req.off('aborted',abort);res.off('close',disconnected);
    if(leased&&!released){
     if(!committed){discard();}else{released=true;try{leased.release();}catch{}}
    }
    controller.abort();active--;
   }
  });
  server.maxHeadersCount=16;server.maxConnections=maxConcurrent*2;server.keepAliveTimeout=1;
  server.on('clientError',(_error,socket)=>socket.destroy());server.on('tlsClientError',()=>{});
  return server;
 }catch{throw fail();}
}
