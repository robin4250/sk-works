// OFF server-only Auth transport. getUser verifies the exact JWT before any
// decoded claims are used; SQL subsequently verifies its live original SID.
const project='https://ztktgquxvcxcjxtluspu.supabase.co';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const deny=()=>Error('apple_native_enrollment_unavailable');
const token=value=>typeof value==='string'&&value.length>0&&value.length<=16384&&!/[\s\r\n]/.test(value);
async function read(response,signal){
 const length=response.headers.get('content-length');
 if(!response.body||(length!==null&&(!/^\d+$/.test(length)||Number(length)>65536)))throw deny();
 const reader=response.body.getReader(),chunks=[];let size=0;
 const cancel=()=>{void reader.cancel().catch(()=>{});};signal.addEventListener('abort',cancel,{once:true});
 try{for(;;){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>65536){cancel();throw deny();}chunks.push(part.value);}}
 finally{signal.removeEventListener('abort',cancel);reader.releaseLock();}
 const bytes=new Uint8Array(size);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.byteLength;}
 return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
}
function claimsFromVerifiedToken(jwt,user,now){
 const parts=jwt.split('.');if(parts.length!==3||!/^[A-Za-z0-9_-]+$/.test(parts[1]))throw deny();
 const raw=Uint8Array.from(atob(parts[1].replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));
 const claims=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw));
 if(!claims||claims.sub!==user?.id||!uuid.test(claims.sub??'')||!uuid.test(claims.session_id??'')||claims.role!=='authenticated'||
 !Number.isSafeInteger(claims.exp)||claims.exp<=now||claims.iss!==project+'/auth/v1'||!(claims.aud==='authenticated'||
  (Array.isArray(claims.aud)&&claims.aud.length===1&&claims.aud[0]==='authenticated'))||user.is_anonymous===true)throw deny();
 return claims;
}
function publicCredential(value){
 if(typeof value!=='string'||!value)return false;
 if(value.startsWith('sb_publishable_'))return true;
 try{const p=value.split('.');if(p.length!==3)return false;const c=JSON.parse(atob(p[1].replace(/-/g,'+').replace(/_/g,'/')));return c.role==='anon'&&c.iss==='supabase';}catch{return false;}
}
export function createNativeAppleAuthPorts({enabled=false,nativeOnlyReviewed=false,successorReviewed=false,passwordSuccessorReviewed=false,baseUrl,publicKey,fetcher=fetch,now=()=>Math.floor(Date.now()/1000),timeoutMs=10000}={}){
 if(!Number.isInteger(timeoutMs)||timeoutMs<1||timeoutMs>10000)throw deny();
 const ready=enabled===true&&nativeOnlyReviewed===true&&baseUrl===project&&publicCredential(publicKey);
 let original=null,passwordAttempted=false;const temporary=new Set(),successors=new Set();
 async function request(path,bearer,body,status=200){
  if(!ready||!token(bearer))throw deny();const controller=new AbortController();let timer;
  const work=(async()=>{const r=await fetcher(project+path,{method:body===undefined?'GET':'POST',redirect:'manual',signal:controller.signal,
   headers:{apikey:publicKey,Authorization:'Bearer '+bearer,...(body===undefined?{}:{'Content-Type':'application/json'})},
   ...(body===undefined?{}:{body:JSON.stringify(body)})});
   if(r.status!==status){void r.body?.cancel().catch(()=>{});throw deny();}return status===204?null:read(r,controller.signal);})();
  try{return await Promise.race([work,new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(deny());},timeoutMs);})]);}
  finally{clearTimeout(timer);controller.abort();}
 }
 async function authenticateExactBearer(bearer){
  const user=await request('/auth/v1/user',bearer);const clock=now();if(!Number.isSafeInteger(clock))throw deny();
  return {user,claims:claimsFromVerifiedToken(bearer,user,clock)};
 }
 async function link({exactBearer,idToken,rawNonce}){
   if(!original||exactBearer!==original.bearer||!token(idToken)||typeof rawNonce!=='string'||!/^[A-Za-z0-9_-]{43,128}$/.test(rawNonce))throw deny();
   const current=await authenticateExactBearer(exactBearer);if(current.user.id!==original.actor||current.claims.session_id!==original.sid)throw deny();
   const result=await request('/auth/v1/token?grant_type=id_token',exactBearer,{provider:'apple',id_token:idToken,nonce:rawNonce,link_identity:true});
   if(!token(result?.access_token)||result.access_token===original.bearer||result.token_type!=='bearer')throw deny();
   const issued=await authenticateExactBearer(result.access_token);
   if(issued.user.id!==original.actor||issued.claims.session_id===original.sid)throw deny();
   return result;
 }
 return Object.freeze({authenticateExactBearer,
  async bindOriginal(bearer){if(original)throw deny();const a=await authenticateExactBearer(bearer);original={bearer,actor:a.user.id,sid:a.claims.session_id};return a;},
  // Internal OFF path: a successful password login creates a successor session.
  // Keep it available for a separately reviewed snapshot/reservation handoff;
  // never claim that the former refresh credential remains usable. This method
  // neither rebinds Apple linking nor exposes an HTTP response/client session.
  async authenticatePrimaryPasswordSuccessor({exactBearer,password}){
   if(passwordSuccessorReviewed!==true||successorReviewed!==true||!original||passwordAttempted||
      exactBearer!==original.bearer||typeof password!=='string'||!password||password.length>1024)throw deny();
   passwordAttempted=true;
   const current=await authenticateExactBearer(exactBearer);
   if(current.user.id!==original.actor||current.claims.session_id!==original.sid)throw deny();
   const identifier=typeof current.user.email==='string'&&current.user.email?{email:current.user.email}:
    typeof current.user.phone==='string'&&current.user.phone?{phone:current.user.phone}:null;
   if(!identifier)throw deny();
   const result=await request('/auth/v1/token?grant_type=password',exactBearer,{...identifier,password});
   if(!token(result?.access_token)||!token(result.refresh_token)||result.token_type!=='bearer'||
      result.user?.id!==original.actor||result.access_token===original.bearer)throw deny();
   const verified=await authenticateExactBearer(result.access_token);
   if(verified.user.id!==original.actor||verified.claims.session_id===original.sid)throw deny();
   successors.add(result.access_token);
   return Object.freeze({actor_id:original.actor,original_session_id:original.sid,
    session_id:verified.claims.session_id,access_token:result.access_token,
    refresh_token:result.refresh_token,token_type:'bearer'});
  },
  async linkNativeIdentity(info){
   const result=await link(info);temporary.add(result.access_token);
   return {access_token:result.access_token,token_type:'bearer'};
  },
  // Internal, default-OFF successor path. No handler exposes this credential.
  async linkNativeIdentitySuccessor(info){
   if(successorReviewed!==true)throw deny();
   const result=await link(info);
   if(!token(result.refresh_token))throw deny();
   successors.add(result.access_token);
   return Object.freeze({access_token:result.access_token,refresh_token:result.refresh_token,token_type:'bearer'});
  },
  async authenticateIssuedSession(bearer){
   if(!temporary.has(bearer)&&!successors.has(bearer))throw deny();const a=await authenticateExactBearer(bearer);
   const identities=a.user.identities;
   if(!Array.isArray(identities))throw deny();
   return {actor_id:a.user.id,session_id:a.claims.session_id,apple_subjects:identities.filter(x=>x.provider==='apple').map(x=>x.identity_data?.sub??x.provider_id)};
  },
  async revokeLocal(bearer){
   if(!temporary.has(bearer)||bearer===original?.bearer)throw deny();
   await request('/auth/v1/logout?scope=local',bearer,{},204);temporary.delete(bearer);return true;
  },
 });
}

