// Server-only, OFF by default. Uses the existing Auth password API contract,
// never the attendance second password or a new operation-proof protocol.
const origin='https://ztktgquxvcxcjxtluspu.supabase.co';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const unavailable=()=>Error('apple_primary_verification_unavailable');
async function jsonBody(response,signal){
 if(!response.body)throw unavailable();
 const reader=response.body.getReader();let total=0;const chunks=[];
 const cancel=()=>{void reader.cancel().catch(()=>{});};signal.addEventListener('abort',cancel,{once:true});
 try{for(;;){const part=await reader.read();if(part.done)break;total+=part.value.byteLength;if(total>65536){cancel();throw unavailable();}chunks.push(part.value);}}
 finally{signal.removeEventListener('abort',cancel);reader.releaseLock();}
 const raw=new Uint8Array(total);let offset=0;for(const chunk of chunks){raw.set(chunk,offset);offset+=chunk.byteLength;}
 return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw));
}
function verifiedIdentity(access,expected,now){
 return access?.user?.id===expected.actor_id&&access.user.is_anonymous!==true&&access.claims?.sub===expected.actor_id&&access.claims.role==='authenticated'&&
  access.claims.session_id===expected.session_id&&uuid.test(expected.session_id)&&Number.isSafeInteger(access.claims.exp)&&access.claims.exp>now;
}
function sameContext(current,expected){
 return current?.account_allowed===true&&current.primary_password_configured===true&&current.actor_id===expected.actor_id&&current.session_id===expected.session_id&&
  current.primary_credential_version===expected.primary_credential_version&&
  JSON.stringify(current.memberships)===JSON.stringify(expected.memberships)&&JSON.stringify(current.google_identities)===JSON.stringify(expected.google_identities)&&
  JSON.stringify(current.apple_subjects)===JSON.stringify(expected.apple_subjects);
}
export function createNativeApplePasswordPort({enabled=false,passwordSessionIsolationReviewed=false,baseUrl,publicKey,authenticateExactBearer,loadExactContext,fetcher=fetch,now=()=>Math.floor(Date.now()/1000),timeoutMs=10000}={}){
 if(!Number.isInteger(timeoutMs)||timeoutMs<1||timeoutMs>10000)throw unavailable();
 const ready=enabled===true&&passwordSessionIsolationReviewed===true&&baseUrl===origin&&typeof publicKey==='string'&&!!publicKey&&typeof authenticateExactBearer==='function'&&typeof loadExactContext==='function';
 async function request(path,init,status){
  const controller=new AbortController();let timer;
  const work=(async()=>{const response=await fetcher(origin+path,{...init,redirect:'error',signal:controller.signal});
   if(response.status!==status){void response.body?.cancel().catch(()=>{});throw unavailable();}
   return status===204?null:jsonBody(response,controller.signal);
  })();
  try{return await Promise.race([work,new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(unavailable());},timeoutMs);})]);}
  finally{clearTimeout(timer);controller.abort();}
 }
 const close=async token=>{await request('/auth/v1/logout?scope=local',{method:'POST',headers:{apikey:publicKey,Authorization:'Bearer '+token}},204);return true;};
 return async({exactBearer,password,expected})=>{
  if(!ready||typeof exactBearer!=='string'||!exactBearer||typeof password!=='string'||!password||password.length>1024||!uuid.test(expected?.actor_id??'')||!uuid.test(expected?.session_id??'')||!/^[a-f0-9]{64}$/.test(expected?.primary_credential_version??''))throw unavailable();
  const started=now();if(!Number.isSafeInteger(started))throw unavailable();
  const original=await authenticateExactBearer(exactBearer);
  if(!verifiedIdentity(original,expected,started)||!sameContext(await loadExactContext(exactBearer),expected))throw unavailable();
  // Only identifiers returned for the original authenticated actor are used.
  const identity=typeof original.user.email==='string'&&original.user.email?{email:original.user.email}:
   typeof original.user.phone==='string'&&original.user.phone?{phone:original.user.phone}:null;
  if(!identity)throw unavailable();
  let temporaryAccess=null;let cleanupAllowed=false;
  try{
   const result=await request('/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:publicKey,'Content-Type':'application/json'},body:JSON.stringify({...identity,password})},200);
   temporaryAccess=typeof result?.access_token==='string'?result.access_token:null;
   if(!temporaryAccess||result.user?.id!==expected.actor_id||result.token_type!=='bearer')throw unavailable();
   // Decoding by itself is not verification. This adapter must call Auth getUser
   // on that exact temporary JWT before returning authenticated claims.
   const temporary=await authenticateExactBearer(temporaryAccess);
   if(temporary?.user?.id!==expected.actor_id||temporary.user.is_anonymous===true||temporary.claims?.sub!==expected.actor_id||temporary.claims.role!=='authenticated'||
    !uuid.test(temporary.claims.session_id??'')||temporary.claims.session_id===expected.session_id||!Number.isSafeInteger(temporary.claims.exp)||temporary.claims.exp<=now())throw unavailable();
   cleanupAllowed=true;
   if(await close(temporaryAccess)!==true)throw unavailable();temporaryAccess=null;cleanupAllowed=false;
   const checkedAt=now();
   if(!Number.isSafeInteger(checkedAt)||checkedAt<started||checkedAt-started>120||
    !verifiedIdentity(await authenticateExactBearer(exactBearer),expected,checkedAt)||!sameContext(await loadExactContext(exactBearer),expected))throw unavailable();
   return Object.freeze({source:'auth_primary_password',actor_id:expected.actor_id,original_session_id:expected.session_id,temporary_session_closed:true,verified_at:checkedAt});
  }finally{
   if(temporaryAccess&&cleanupAllowed){try{await close(temporaryAccess);}catch{/* hold; no token or password returned */}}
  }
 };
}
