const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const scopes = new Map([
 ['secondary_password.replace', 'secondary_password'],
 ['secondary_password.change', 'secondary_password'],
 ['attendance.manage', 'attendance_management'],
 ['master.feature.set', 'master_feature'],
 ['master.security_incidents.read', 'master_security'],
 ['master.security_collector.read', 'master_security'],
 ['master.device.lock', 'master_device_lock'],
 ['employee.bank.initial', 'employee_bank_registration'],
]);
const featureKeys = new Set(['vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop','company_seal_image_tools','site_order_documents']);
const reply = (status, data) => new Response(JSON.stringify(data), {
 status, headers: {'Content-Type':'application/json', 'Cache-Control':'no-store'},
});
function claims(token) {
 const parts=token.split('.'); if(parts.length!==3)throw Error('invalid_token');
 return JSON.parse(atob(parts[1].replaceAll('-','+').replaceAll('_','/')));
}
async function boundedJson(req) {
 if(Number(req.headers.get('content-length')??0)>4096)throw Error('invalid_request');
 const reader=req.body?.getReader();if(!reader)throw Error('invalid_request');
 const chunks=[];let length=0,timer;
 const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>{
  void reader.cancel().catch(()=>{});reject(Error('invalid_request'));
 },10000);});
 try {
  while(true) {
   const chunk=await Promise.race([reader.read(),timeout]);
   if(chunk.done)break;
   length+=chunk.value.byteLength;
   if(length>4096){void reader.cancel().catch(()=>{});throw Error('invalid_request');}
   chunks.push(chunk.value);
  }
  const data=new Uint8Array(length);let offset=0;
  for(const chunk of chunks){data.set(chunk,offset);offset+=chunk.byteLength;}
  return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(data));
 }finally{clearTimeout(timer);reader.releaseLock();}
}
export function createReauthenticationHandler({baseUrl,publicKey,serviceKey,fetcher=fetch,random=crypto.getRandomValues.bind(crypto),digest=crypto.subtle.digest.bind(crypto.subtle)}) {
 const base=baseUrl?.replace(/\/$/,'');
 async function request(path, options) {
  return fetcher(base+path,{...options,redirect:'error',signal:AbortSignal.timeout(10000)});
 }
 const serviceHeaders=()=>({'Content-Type':'application/json',apikey:serviceKey,
  ...(!serviceKey.startsWith('sb_secret_')?{Authorization:'Bearer '+serviceKey}:{})});
 async function issue(actor,session,operation,target,secondary) {
   const nonce=Array.from(random(new Uint8Array(32)),x=>x.toString(16).padStart(2,'0')).join('');
   const hash=Array.from(new Uint8Array(await digest('SHA-256',new TextEncoder().encode(nonce))),x=>x.toString(16).padStart(2,'0')).join('');
   const issued=await request(secondary?'/rest/v1/rpc/issue_secondary_reauthentication_proof':'/rest/v1/rpc/issue_reauthentication_proof',{method:'POST',
    headers:secondary?{apikey:publicKey,Authorization:secondary.authorization,'Content-Type':'application/json'}:serviceHeaders(),
    body:JSON.stringify(secondary?{p_operation:operation,p_target:target,p_proof_hash:hash,p_password:secondary.password}:
      {p_actor:actor,p_session:session,p_operation:operation,p_target:target,p_proof_hash:hash})});
   if(!issued.ok)return reply(issued.status===429?429:issued.status===401||issued.status===403||secondary&&issued.status===400?403:503,{error:'reauthentication_unavailable'});
   const expiresAt=await issued.json();
   if(secondary&&expiresAt===null)return reply(403,{error:'reauthentication_failed'});
   if(typeof expiresAt!=='string'||!Number.isFinite(Date.parse(expiresAt))||Date.parse(expiresAt)<=Date.now()||Date.parse(expiresAt)>Date.now()+125000)return reply(503,{error:'reauthentication_unavailable'});
   return reply(200,{protocol:'sko-reauthentication-v1',proof:nonce,expiresAt,operation:operation,target});
 }
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
   if(user?.is_anonymous===true||token.is_anonymous===true||!uuid.test(user?.id??'')||token.sub!==user.id||token.role!=='authenticated'||!uuid.test(token.session_id??'')||!Number.isFinite(token.exp)||token.exp*1000<=Date.now())return reply(401,{error:'authentication_required'});
   verifiedAccess={user,session:token.session_id};
  }catch{return reply(503,{error:'reauthentication_unavailable'});}
  let payload;
  try {
   payload=await boundedJson(req);
  }catch{return reply(400,{error:'invalid_request'});}
  const {user,session}=verifiedAccess;
  if(!payload||typeof payload!=='object'||Array.isArray(payload)||!['operation,password,target','captcha_token,operation,password,target'].includes(Object.keys(payload).sort().join(','))||!scopes.has(payload.operation)||typeof payload.password!=='string'||payload.password.length===0||payload.password.length>1024)return reply(400,{error:'invalid_request'});
  if(Object.hasOwn(payload,'captcha_token')&&(typeof payload.captcha_token!=='string'||payload.captcha_token.length===0||payload.captcha_token.length>2048||payload.captcha_token.trim()!==payload.captcha_token))return reply(400,{error:'invalid_request'});
  const target=payload.target;
  if(!target||typeof target!=='object'||Array.isArray(target))return reply(400,{error:'invalid_request'});
  if(payload.operation==='employee.bank.initial'&&(Object.keys(target).sort().join(',')!=='company_id,input_sha256,worker_id'||!uuid.test(target.company_id??'')||target.company_id!==target.company_id.toLowerCase()||!uuid.test(target.worker_id??'')||target.worker_id!==target.worker_id.toLowerCase()||!/^[0-9a-f]{64}$/.test(target.input_sha256??'')))return reply(400,{error:'invalid_request'});
  if(payload.operation==='attendance.manage'&&(Object.keys(target).sort().join(',')!=='action,company_id,items_sha256'||!uuid.test(target.company_id??'')||!['upsert','delete'].includes(target.action)||!/^[0-9a-f]{64}$/.test(target.items_sha256??'')))return reply(400,{error:'invalid_request'});
  if(['secondary_password.replace','secondary_password.change'].includes(payload.operation)&&(Object.keys(target).join(',')!=='user_id'||target.user_id!==user.id))return reply(400,{error:'invalid_request'});
  if(payload.operation==='master.feature.set'&&(Object.keys(target).sort().join(',')!=='enabled,feature_key'||!featureKeys.has(target.feature_key)||typeof target.enabled!=='boolean'))return reply(400,{error:'invalid_request'});
  if(payload.operation==='master.device.lock'&&(Object.keys(target).sort().join(',')!=='device_id,locked'||typeof target.device_id!=='string'||!uuid.test(target.device_id)||target.device_id!==target.device_id.toLowerCase()||typeof target.locked!=='boolean'))return reply(400,{error:'invalid_request'});
  if(payload.operation==='master.security_incidents.read'&&(Object.keys(target).join(',')!=='scope'||target.scope!=='platform'))return reply(400,{error:'invalid_request'});
  if(payload.operation==='master.security_collector.read'&&(Object.keys(target).join(',')!=='scope'||target.scope!=='decoy_collector'))return reply(400,{error:'invalid_request'});
  try {
   const deviceOperation=payload.operation==='master.device.lock';
   const bankOperation=payload.operation==='employee.bank.initial';
   const capabilityPath=bankOperation?'/rest/v1/rpc/employee_bank_initial_capability':deviceOperation?'/rest/v1/rpc/master_device_lock_capability':'/rest/v1/rpc/reauthentication_capabilities';
   const capabilities=await request(capabilityPath,{method:'POST',headers:{apikey:publicKey,Authorization:authorization,'Content-Type':'application/json'},
    body:bankOperation?JSON.stringify({p_company_id:target.company_id,p_worker_id:target.worker_id}):'{}'});
   if(!capabilities.ok)return reply(503,{error:'reauthentication_unavailable'});
   const value=await capabilities.json();
   if(bankOperation ? (value?.protocol!=='sko-employee-bank-initial-v1'||value.enabled!==true||value.company_id!==target.company_id||value.worker_id!==target.worker_id||value.registered!==false)
     : deviceOperation ? (value?.protocol!=='sko-master-device-lock-v1'||value.enabled!==true)
     : (value?.protocol!=='sko-reauthentication-v1'||value[scopes.get(payload.operation)]!==true))return reply(403,{error:'reauthentication_disabled'});
  }catch{return reply(503,{error:'reauthentication_unavailable'});}
  if(payload.operation==='attendance.manage'||payload.operation==='secondary_password.change') {
   try {
    // Verification/counter commit, fingerprint and issue are atomic in the DB.
    return await issue(user.id,session,payload.operation,target,{password:payload.password,authorization});
   }catch{return reply(503,{error:'reauthentication_unavailable'});}
  }
  let temporaryAccess,temporaryActor;
  try {
   // The identifier comes from the authenticated user, never the request body.
   const identity=user.phone?{phone:user.phone}:user.email?{email:user.email}:null;
   if(!identity)return reply(403,{error:'reauthentication_failed'});
   const result=await request('/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:publicKey,'Content-Type':'application/json'},body:JSON.stringify({...identity,password:payload.password,...(payload.captcha_token===undefined?{}:{gotrue_meta_security:{captcha_token:payload.captcha_token}})})});
   if(!result.ok)return reply(result.status===429?429:result.status>=500?503:403,{error:'reauthentication_failed'});
   const verified=await result.json();
   temporaryAccess=typeof verified.access_token==='string'?verified.access_token:null;
   temporaryActor=verified.user?.id;
   if(!temporaryAccess||verified.user?.id!==user.id)return reply(403,{error:'reauthentication_failed'});
   const tempClaims=claims(temporaryAccess);
   // Never risk logging out the caller's original session.
   if(tempClaims.sub!==user.id||!uuid.test(tempClaims.session_id??'')||tempClaims.session_id===session)return reply(503,{error:'reauthentication_unavailable'});
   const cleanup=await request('/auth/v1/logout?scope=local',{method:'POST',headers:{apikey:publicKey,Authorization:'Bearer '+temporaryAccess}});
   if(!cleanup.ok)return reply(503,{error:'reauthentication_unavailable'});
   temporaryAccess=null;
   return await issue(user.id,session,payload.operation,target);
  }catch{return reply(503,{error:'reauthentication_unavailable'});}
  finally {
   if(temporaryAccess) {
    // Only the distinct temporary password-verification session is cleaned up.
    try { const c=claims(temporaryAccess); if(uuid.test(temporaryActor??'')&&c.sub===temporaryActor&&uuid.test(c.session_id??'')&&c.session_id!==session)await request('/auth/v1/logout?scope=local',{method:'POST',headers:{apikey:publicKey,Authorization:'Bearer '+temporaryAccess}}); }catch{ /* Fail closed without logging credentials. */ }
   }
  }
 };
}

