import {createAppleSharedRatePort} from './apple_shared_rate_port.mjs';
import {createAppleKeyResolver} from '../apple_key_resolver.mjs';
// Review-only endpoint composition. No deployment entrypoint or gate activation.
import {createNativeAppleAuthPorts} from '../../apple-existing-login-candidate/native_apple_auth_port.mjs';
import {createNativeAppleEnrollmentSQLPorts} from '../../apple-existing-login-candidate/native_apple_enrollment_sql_port.mjs';
import {createNativeApplePasswordPort} from '../../apple-existing-login-candidate/native_apple_password_port.mjs';
import {enrollNativeApple} from '../../apple-existing-login-candidate/native_apple_enrollment.mjs';
const project='https://ztktgquxvcxcjxtluspu.supabase.co';
const unavailable=()=>Error('apple_native_enrollment_unavailable');
const response=(status,value)=>new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','Pragma':'no-cache'}});
async function input(req){
 if(req.headers.get('content-type')?.split(';')[0].trim()!=='application/json'||!req.body)throw unavailable();
 const length=req.headers.get('content-length');if(length!==null&&(!/^\d+$/.test(length)||Number(length)>32768))throw unavailable();
 const reader=req.body.getReader();let timer,size=0;const chunks=[];
 try{return await Promise.race([(async()=>{for(;;){const r=await reader.read();if(r.done)break;size+=r.value.byteLength;if(size>32768)throw unavailable();chunks.push(r.value);}
  const bytes=new Uint8Array(size);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.byteLength;}
  const data=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
  if(!data||typeof data!=='object'||Array.isArray(data)||Object.keys(data).sort().join(',')!=='id_token,nonce,password')throw unavailable();
  if(typeof data.password!=='string'||!data.password||data.password.length>1024||typeof data.id_token!=='string'||!data.id_token||data.id_token.length>16384||typeof data.nonce!=='string'||!/^[A-Za-z0-9_-]{43,128}$/.test(data.nonce))throw unavailable();
  return data;})(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(unavailable()),5000);})]);}
 finally{clearTimeout(timer);void reader.cancel().catch(()=>{});}
}
export function createNativeAppleEnrollmentHandler(config={},dependencies={}){
 const {fetcher=fetch,now=()=>Math.floor(Date.now()/1000)}=dependencies;
 const resolveKey=createAppleKeyResolver({fetcher});
 const audiences=config.audiences;
 const keyTimeoutMs=config.keyTimeoutMs??10000;
 const boundedResolveKey=async kid=>{let timer;try{return await Promise.race([Promise.resolve().then(()=>resolveKey(kid)),new Promise((_,reject)=>{timer=setTimeout(()=>reject(unavailable()),keyTimeoutMs);})]);}finally{clearTimeout(timer);}};
 const ready=config.enabled===true&&config.nativeOnlyReviewed===true&&config.passwordSessionIsolationReviewed===true&&config.globalGoogleProtectionReviewed===true&&config.sharedRateReviewed===true&&
  config.baseUrl===project&&typeof config.publicKey==='string'&&!!config.publicKey&&typeof config.serviceKey==='string'&&!!config.serviceKey&&
  Number.isInteger(keyTimeoutMs)&&keyTimeoutMs>0&&keyTimeoutMs<=10000&&Array.isArray(audiences)&&audiences.length>0&&audiences.length<=8&&audiences.every(x=>typeof x==='string'&&/^[A-Za-z0-9._-]{1,255}$/.test(x))&&typeof resolveKey==='function';
 return async req=>{
  if(req.method!=='POST')return response(405,{error:'method_not_allowed'});
  if(!ready)return response(503,{error:'apple_native_enrollment_unavailable'});
  try{
   const authHeader=req.headers.get('authorization');if(!authHeader?.startsWith('Bearer ')||authHeader.length>16391)throw unavailable();
   const exactBearer=authHeader.slice(7);if(!exactBearer||/[\s\r\n]/.test(exactBearer))throw unavailable();
   const data=await input(req);
   // Request-local ports cannot leak original UID/SID, pending token, SQL
   // context or cleanup authorization into another request.
   const auth=createNativeAppleAuthPorts({...config,fetcher,now});
   const verified=await auth.bindOriginal(exactBearer);
   const rate=createAppleSharedRatePort({...config,enabled:true,fetcher});
   await rate.takeVerified(verified);
   const sql=createNativeAppleEnrollmentSQLPorts({...config,fetcher,now,authenticateExactBearer:auth.authenticateExactBearer});
   const verifyPrimaryPassword=createNativeApplePasswordPort({...config,fetcher,now,authenticateExactBearer:auth.authenticateExactBearer,loadExactContext:sql.loadExactContext});
   const result=await enrollNativeApple({exactBearer,password:data.password,idToken:data.id_token,rawNonce:data.nonce},
    {...sql,...auth,verifyPrimaryPassword,enabled:true,nativeOnlyReviewed:true,audiences,now,resolveKey:boundedResolveKey});
   return response(200,result);
  }catch{return response(403,{error:'apple_native_enrollment_unavailable',message:'Apple連携を確認できません。現在のGoogleログインを維持して管理者に確認してください。'});}
 };
}
