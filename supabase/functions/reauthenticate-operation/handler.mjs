const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const scopes = new Map([
 ['secondary_password.replace', 'secondary_password'],
 ['master.feature.set', 'master_feature'],
 ['master.security_incidents.read', 'master_security'],
]);
const featureKeys = new Set(['vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop']);
const reply = (status, data) => new Response(JSON.stringify(data), {
 status, headers: {'Content-Type':'application/json', 'Cache-Control':'no-store'},
});
function claims(token) {
 const parts=token.split('.'); if(parts.length!==3)throw Error('invalid_token');
 return JSON.parse(atob(parts[1].replaceAll('-','+').replaceAll('_','/')));
}
export function createReauthenticationHandler({baseUrl,publicKey,serviceKey,fetcher=fetch,random=crypto.getRandomValues.bind(crypto),digest=crypto.subtle.digest.bind(crypto.subtle)}) {
 const base=baseUrl?.replace(/\/$/,'');
 async function request(path, options) {
  return fetcher(base+path,{...options,redirect:'error',signal:AbortSignal.timeout(10000)});
 }
 const serviceHeaders=()=>({'Content-Type':'application/json',apikey:serviceKey,
  ...(!serviceKey.startsWith('sb_secret_')?{Authorization:'Bearer '+serviceKey}:{})});
 return async req => {
  if(req.method!=='POST')return reply(405,{error:'method_not_allowed'});
  if(!base||!publicKey||!serviceKey)return reply(503,{error:'reauthentication_unavailable'});
  const authorization=req.headers.get('authorization');
  if(!authorization?.startsWith('Bearer '))return reply(401,{error:'authentication_required'});
  let verifiedAccess;
  try {
   // Claims are decoded only AFTER the Auth server has validated the exact JWT.
   const response=await request('/auth/v1/user',{headers:{apikey:publicKey,Authorization:authorization}});
   if(!response.ok)return reply(response.status===401||response.status===403?401:503,{error:'reauthentication_unavailable'});
   const user=await response.json(), token=claims(authorization.slice(7));
   if(!uuid.test(user?.id??'')||token.sub!==user.id||token.role!=='authenticated'||!uuid.test(token.session_id??'')||!Number.isFinite(token.exp)||token.exp*1000<=Date.now())return reply(401,{error:'authentication_required'});
   verifiedAccess={user,session:token.session_id};
  }catch{return reply(503,{error:'reauthentication_unavailable'});}
  let payload;
  try {
   if(Number(req.headers.get('content-length')??0)>4096)return reply(400,{error:'invalid_request'});
   const text=await req.text(); if(text.length>4096)return reply(400,{error:'invalid_request'});
   payload=JSON.parse(text);
  }catch{return reply(400,{error:'invalid_request'});}
  const {user,session}=verifiedAccess;
  if(!payload||typeof payload!=='object'||Array.isArray(payload)||Object.keys(payload).sort().join(',')!=='operation,password,target'||!scopes.has(payload.operation)||typeof payload.password!=='string'||payload.password.length===0||payload.password.length>1024)return reply(400,{error:'invalid_request'});
  const target=payload.target;
  if(!target||typeof target!=='object'||Array.isArray(target))return reply(400,{error:'invalid_request'});
  if(payload.operation==='secondary_password.replace'&&(Object.keys(target).join(',')!=='user_id'||target.user_id!==user.id))return reply(400,{error:'invalid_request'});
  if(payload.operation==='master.feature.set'&&(Object.keys(target).sort().join(',')!=='enabled,feature_key'||!featureKeys.has(target.feature_key)||typeof target.enabled!=='boolean'))return reply(400,{error:'invalid_request'});
  if(payload.operation==='master.security_incidents.read'&&(Object.keys(target).join(',')!=='scope'||target.scope!=='platform'))return reply(400,{error:'invalid_request'});
  try {
   const capabilities=await request('/rest/v1/rpc/reauthentication_capabilities',{method:'POST',headers:{apikey:publicKey,Authorization:authorization,'Content-Type':'application/json'},body:'{}'});
   if(!capabilities.ok)return reply(503,{error:'reauthentication_unavailable'});
   const value=await capabilities.json();
   if(value?.protocol!=='sko-reauthentication-v1'||value[scopes.get(payload.operation)]!==true)return reply(403,{error:'reauthentication_disabled'});
  }catch{return reply(503,{error:'reauthentication_unavailable'});}
  let temporaryAccess;
  try {
   // The identifier comes from the authenticated user, never the request body.
   const identity=user.phone?{phone:user.phone}:user.email?{email:user.email}:null;
   if(!identity)return reply(403,{error:'reauthentication_failed'});
   const result=await request('/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:publicKey,'Content-Type':'application/json'},body:JSON.stringify({...identity,password:payload.password})});
   if(!result.ok)return reply(result.status===429?429:result.status>=500?503:403,{error:'reauthentication_failed'});
   const verified=await result.json();
   temporaryAccess=typeof verified.access_token==='string'?verified.access_token:null;
   if(!temporaryAccess||verified.user?.id!==user.id)return reply(403,{error:'reauthentication_failed'});
   const tempClaims=claims(temporaryAccess);
   // Never risk logging out the caller's original session.
   if(tempClaims.sub!==user.id||!uuid.test(tempClaims.session_id??'')||tempClaims.session_id===session)return reply(503,{error:'reauthentication_unavailable'});
   const cleanup=await request('/auth/v1/logout?scope=local',{method:'POST',headers:{apikey:publicKey,Authorization:'Bearer '+temporaryAccess}});
   if(!cleanup.ok)return reply(503,{error:'reauthentication_unavailable'});
   temporaryAccess=null;
   const nonce=Array.from(random(new Uint8Array(32)),x=>x.toString(16).padStart(2,'0')).join('');
   const hash=Array.from(new Uint8Array(await digest('SHA-256',new TextEncoder().encode(nonce))),x=>x.toString(16).padStart(2,'0')).join('');
   const issued=await request('/rest/v1/rpc/issue_reauthentication_proof',{method:'POST',headers:serviceHeaders(),body:JSON.stringify({p_actor:user.id,p_session:session,p_operation:payload.operation,p_target:target,p_proof_hash:hash})});
   if(!issued.ok)return reply(issued.status===401||issued.status===403?403:503,{error:'reauthentication_unavailable'});
   const expiresAt=await issued.json();
   if(typeof expiresAt!=='string'||!Number.isFinite(Date.parse(expiresAt))||Date.parse(expiresAt)<=Date.now()||Date.parse(expiresAt)>Date.now()+125000)return reply(503,{error:'reauthentication_unavailable'});
   return reply(200,{protocol:'sko-reauthentication-v1',proof:nonce,expiresAt,operation:payload.operation,target});
  }catch{return reply(503,{error:'reauthentication_unavailable'});}
  finally {
   if(temporaryAccess) {
    // Only the distinct temporary password-verification session is cleaned up.
    try { const c=claims(temporaryAccess); if(c.sub===user.id&&uuid.test(c.session_id??'')&&c.session_id!==session)await request('/auth/v1/logout?scope=local',{method:'POST',headers:{apikey:publicKey,Authorization:'Bearer '+temporaryAccess}}); }catch{ /* Fail closed without logging credentials. */ }
   }
  }
 };
}
