// Internal OFF adapters. Only a server-authenticated exact bearer can select
// the UID/SID; no caller-selected identity, SQL table access or session adoption.
const origin='https://ztktgquxvcxcjxtluspu.supabase.co';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const denied=()=>Error('apple_native_enrollment_unavailable');
async function body(response,signal){
 if(!response.body)throw denied();
 const length=response.headers.get('content-length');
 if(length!==null&&(!/^[0-9]+$/.test(length)||Number(length)>32768)){void response.body.cancel().catch(()=>{});throw denied();}
 const reader=response.body.getReader(),chunks=[];let size=0;
 const abort=()=>{void reader.cancel().catch(()=>{});};signal.addEventListener('abort',abort,{once:true});
 try{for(;;){const r=await reader.read();if(r.done)break;size+=r.value.byteLength;if(size>32768){abort();throw denied();}chunks.push(r.value);}}
 finally{signal.removeEventListener('abort',abort);reader.releaseLock();}
 const bytes=new Uint8Array(size);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.byteLength;}
 return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
}
export function createNativeAppleEnrollmentSQLPorts({enabled=false,baseUrl,serviceKey,authenticateExactBearer,fetcher=fetch,now=()=>Math.floor(Date.now()/1000),timeoutMs=10000}={}){
 if(!Number.isInteger(timeoutMs)||timeoutMs<1||timeoutMs>10000)throw denied();
 const ready=enabled===true&&baseUrl===origin&&typeof serviceKey==='string'&&!!serviceKey&&typeof authenticateExactBearer==='function';
 let binding=null;
 async function rpc(name,args){
  if(!ready)throw denied();const controller=new AbortController();let timer;
  const headers={apikey:serviceKey,'Content-Type':'application/json'};
  if(!serviceKey.startsWith('sb_secret_'))headers.Authorization='Bearer '+serviceKey;
  const work=(async()=>{const r=await fetcher(origin+'/rest/v1/rpc/'+name,{method:'POST',headers,redirect:'error',signal:controller.signal,body:JSON.stringify(args)});
   if(r.status!==200){void r.body?.cancel().catch(()=>{});throw denied();}return body(r,controller.signal);})();
  try{return await Promise.race([work,new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(denied());},timeoutMs);})]);}
  finally{clearTimeout(timer);controller.abort();}
 }
 const bound=info=>binding&&info.actor_id===binding.actor_id&&info.session_id===binding.session_id;
 return Object.freeze({
  async loadExactContext(exactBearer){
   binding=null;
   if(!ready||typeof exactBearer!=='string'||!exactBearer||exactBearer.length>16384)throw denied();
   let timer;let a;
   try{a=await Promise.race([Promise.resolve().then(()=>authenticateExactBearer(exactBearer)),new Promise((_,reject)=>{timer=setTimeout(()=>reject(denied()),timeoutMs);})]);}
   finally{clearTimeout(timer);}
   const c=a?.claims,checkedAt=now();
   if(!Number.isSafeInteger(checkedAt)||!c||a.user?.id!==c.sub||a.user.is_anonymous===true||c.role!=='authenticated'||!uuid.test(c.sub??'')||!uuid.test(c.session_id??'')||!Number.isSafeInteger(c.exp)||c.exp<=checkedAt)throw denied();
   const r=await rpc('read_apple_native_enrollment_context',{p_actor_id:c.sub,p_session_id:c.session_id});
   if(!r||r.actor_id!==c.sub||r.session_id!==c.session_id||r.account_allowed!==true||r.primary_password_configured!==true||!/^[a-f0-9]{64}$/.test(r.profile_version??''))throw denied();
   binding={actor_id:c.sub,session_id:c.session_id};return r;
  },
  async reserveSubject(info){
   if(!bound(info)||!info.snapshot||info.snapshot.actor_id!==info.actor_id||info.snapshot.session_id!==info.session_id)throw denied();
   return rpc('reserve_apple_native_subject',{p_actor_id:info.actor_id,p_session_id:info.session_id,p_subject:info.subject,
    p_token_sha256:info.token_sha256,p_snapshot_sha256:info.snapshot_sha256,p_snapshot:JSON.stringify(info.snapshot),p_verified_at:info.verified_at});
  },
  async completeSubject(info){
   if(!bound(info))throw denied();
   return rpc('complete_apple_native_subject',{p_request_id:info.request_id,p_actor_id:info.actor_id,p_session_id:info.session_id,p_subject:info.subject,
    p_token_sha256:info.token_sha256,p_before_snapshot_sha256:info.before_snapshot_sha256});
  },
  async holdSubject(requestId){
   if(!binding||!uuid.test(requestId??''))throw denied();
   return rpc('hold_apple_native_subject',{p_request_id:requestId,p_actor_id:binding.actor_id,p_session_id:binding.session_id});
  },
 });
}
