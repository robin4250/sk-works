// Unconfigured server adapters only. Never install a listener or discover keys.
import {createManagementIssuer} from './management-issuer.mjs';
const uuid=x=>typeof x==='string'&&/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(x);
const exact=(x,keys)=>x&&typeof x==='object'&&!Array.isArray(x)&&Object.keys(x).sort().join(',')===keys;
const token=x=>typeof x==='string'&&x.length<=16384&&/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(x);
function configuration(url,publicKey,serviceBearer,fetchImpl,timeoutMs){
 const u=new URL(url);
 if(u.protocol!=='https:'||u.username||u.password||u.search||u.hash||u.pathname!=='/'||
  typeof publicKey!=='string'||publicKey.length<1||publicKey.length>16384||/[\r\n]/.test(publicKey)||
  !token(serviceBearer)||typeof fetchImpl!=='function'||!Number.isSafeInteger(timeoutMs)||timeoutMs<10||timeoutMs>5000)throw Error('Management transport configuration rejected');
 return u.origin;
}
export async function boundedJson(body,maxBytes=8192,signal){
 if(!body)throw Error('JSON body unavailable');
 const reader=body.getReader(),chunks=[];let total=0;
 const abort=()=>{reader.cancel().catch(()=>{});};signal?.addEventListener('abort',abort,{once:true});
 try{if(signal?.aborted)throw Error('JSON body cancelled');while(true){const {done,value}=await reader.read();if(signal?.aborted)throw Error('JSON body cancelled');if(done)break;total+=value.byteLength;if(total>maxBytes)throw Error('JSON body bound');chunks.push(value);}}
 finally{signal?.removeEventListener('abort',abort);await reader.cancel().catch(()=>{});}
 const bytes=new Uint8Array(total);let offset=0;for(const b of chunks){bytes.set(b,offset);offset+=b.length;}
 return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
}
function jwtClaims(bearer,now){
 if(!token(bearer))throw Error('Authenticated bearer required');
 const part=bearer.split('.')[1],decoded=atob(part.replace(/-/g,'+').replace(/_/g,'/'));
 const claims=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Uint8Array.from(decoded,c=>c.charCodeAt(0))));
 if(!uuid(claims.sub)||!uuid(claims.session_id)||claims.role!=='authenticated'||claims.is_anonymous===true||
  !Number.isFinite(claims.exp)||claims.exp*1000<=now||!Number.isFinite(claims.iat)||claims.iat*1000>now+30000)throw Error('Authenticated bearer binding rejected');
 // Parsing is not authentication: /auth/v1/user must verify this exact token,
 // and each RPC checks the live SID, membership and Master state independently.
 return claims;
}
export function createManagementTransport({url,publicKey,serviceBearer,callerBearer,fetchImpl=fetch,timeoutMs=2500,now=()=>Date.now(),signal}={}){
 const origin=configuration(url,publicKey,serviceBearer,fetchImpl,timeoutMs);
 const claims=jwtClaims(callerBearer,now());
 async function request(path,bearer,key,body,{signal:operationSignal}={}){
  const local=new AbortController();let timer,cancelReject;
  const abort=()=>{local.abort();cancelReject?.(Error('Management transport cancelled'));};
  if(signal?.aborted||operationSignal?.aborted)throw Error('Management transport cancelled');
  signal?.addEventListener('abort',abort,{once:true});operationSignal?.addEventListener('abort',abort,{once:true});
  const work=(async()=>{
   const response=await fetchImpl(origin+path,{method:body===undefined?'GET':'POST',redirect:'manual',signal:local.signal,
    headers:{apikey:key,Authorization:'Bearer '+bearer,...(body===undefined?{}:{'Content-Type':'application/json'})},
    ...(body===undefined?{}:{body:JSON.stringify(body)})});
   if(local.signal.aborted)throw Error('Management transport cancelled');
   if(!response.ok||response.status>=300||!/^application\/json(?:;|$)/i.test(response.headers.get('content-type')??''))throw Error('Management transport rejected');
   const value=await boundedJson(response.body,32768,local.signal);if(local.signal.aborted)throw Error('Management transport cancelled');return value;
  })();
  try{return await Promise.race([work,new Promise((_,reject)=>{cancelReject=reject;timer=setTimeout(()=>{local.abort();reject(Error('Management transport deadline'));},timeoutMs);})]);}
  finally{clearTimeout(timer);local.abort();signal?.removeEventListener('abort',abort);operationSignal?.removeEventListener('abort',abort);}
 }
 const caller=(name,body,options)=>request('/rest/v1/rpc/'+name,callerBearer,publicKey,body,options);
 const server=(name,body,options)=>request('/rest/v1/rpc/'+name,serviceBearer,serviceBearer,body,options);
 return Object.freeze({
  async authenticate(){const user=await request('/auth/v1/user',callerBearer,publicKey);if(!user||user.id!==claims.sub||user.is_anonymous===true)throw Error('Management caller rejected');return Object.freeze({actorId:claims.sub,sessionId:claims.session_id});},
  prepare:(companyId,command,password,options)=>caller('prepare_decoy_management_proof',{p_company_id:companyId,p_command:command,p_secondary_password:password},options),
  claim:(proof,options)=>caller('claim_decoy_management_command',{p_proof:proof},options),
  complete:(c,options)=>server('complete_decoy_management_command',{p_command_id:c.command_id,p_lease_id:c.lease_id,p_payload_hash:c.payload_hash,p_signature:c.signature},options),
  fail:(c,options)=>server('fail_decoy_management_command',{p_command_id:c.command_id,p_lease_id:c.lease_id,p_failure:c.failure},options),
 });
}
const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
export function createManagementRequestHandler({enabled=false,url,publicKey,serviceBearer,fetchImpl=fetch,resolveSigningKey,limitAttempt,now=()=>Date.now(),timeoutMs=2500,deadlineMs=9000,allowedOrigin=null}={}){
 if(typeof enabled!=='boolean')throw Error('Management handler configuration rejected');
 if(enabled){configuration(url,publicKey,serviceBearer,fetchImpl,timeoutMs);if(typeof resolveSigningKey!=='function'||typeof limitAttempt!=='function'||!Number.isSafeInteger(deadlineMs)||deadlineMs<50||deadlineMs>15000)throw Error('Management handler ports unavailable');}
 return async request=>{
  if(!enabled)return json({state:'disabled'},503);
  if(request.method!=='POST')return json({state:'rejected'},405);
  if(request.headers.has('origin')&&request.headers.get('origin')!==allowedOrigin)return json({state:'rejected'},403);
  const bearer=request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_.-]+)$/)?.[1];
  if(!token(bearer))return json({state:'rejected'},401);
  const controller=new AbortController();let timer,active=true;
  const work=(async()=>{
   const body=await boundedJson(request.body,8192,controller.signal);
   if(!exact(body,'operation,proof')&&!exact(body,'command,company_id,operation,secondary_password'))return json({state:'rejected'},400);
   if(body.operation==='issue'&&!exact(body,'operation,proof')||body.operation==='prepare'&&!exact(body,'command,company_id,operation,secondary_password')||!['prepare','issue'].includes(body.operation))return json({state:'rejected'},400);
   if(body.operation==='issue'&&(typeof body.proof!=='string'||!/^[a-f0-9]{64}$/.test(body.proof)))return json({state:'rejected'},400);
   if(body.operation==='prepare'&&(!uuid(body.company_id)||typeof body.secondary_password!=='string'||body.secondary_password.length<1||body.secondary_password.length>1024||!exact(body.command,'action,deployment_id,expected_policy_revision,expected_trust_revision,reason')))return json({state:'rejected'},400);
   const database=createManagementTransport({url,publicKey,serviceBearer,callerBearer:bearer,fetchImpl,timeoutMs,now,signal:controller.signal});
   const caller=await database.authenticate();
   if(!active)throw Error('Management request cancelled');
   const limited=await Promise.race([Promise.resolve().then(()=>limitAttempt({actorId:caller.actorId,sessionId:caller.sessionId,operation:body.operation},{signal:controller.signal})),new Promise((_,reject)=>controller.signal.addEventListener('abort',()=>reject(Error('Management limiter cancelled')),{once:true}))]);
   if(!active||controller.signal.aborted)throw Error('Management request cancelled');
   if(limited!==true)return json({state:'rate_limited'},429);
   if(body.operation==='prepare'){
    const p=await database.prepare(body.company_id,body.command,body.secondary_password,{signal:controller.signal});
    if(!active)throw Error('Management request cancelled');
    if(exact(p,'reason,verified')&&p.verified===false&&p.reason==='secondary_password_rejected')return json(p);
    if(!exact(p,'command_id,expires_at,operation,payload_hash,proof,verified')||p.verified!==true||p.operation!=='master.security_decoy.manage'||!uuid(p.command_id)||typeof p.proof!=='string'||!/^[a-f0-9]{64}$/.test(p.proof)||typeof p.payload_hash!=='string'||!/^[a-f0-9]{64}$/.test(p.payload_hash)||!Number.isSafeInteger(p.expires_at)||p.expires_at<=now()||p.expires_at>now()+60000)throw Error('Management preparation response rejected');
    return json(p);
   }
   const resolver=async(args,options)=>{if(!active||controller.signal.aborted)throw Error('Management request cancelled');const key=await resolveSigningKey(args,{signal:AbortSignal.any([options.signal,controller.signal])});if(!active||controller.signal.aborted||options.signal.aborted)throw Error('Management request cancelled');return key;};
   const result=await createManagementIssuer({enabled:true,database,resolveSigningKey:resolver,now,deadlineMs:Math.min(timeoutMs,5000)}).issue({proof:body.proof});
   if(!active)throw Error('Management request cancelled');return json(result);
  })();
  try{return await Promise.race([work,new Promise(resolve=>{timer=setTimeout(()=>{active=false;controller.abort();resolve(json({state:'pending'},503));},deadlineMs);})]);}
  catch{return json({state:'unavailable'},503);}
  finally{active=false;clearTimeout(timer);controller.abort();}
 };
}
