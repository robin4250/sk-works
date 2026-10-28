// Review-only request boundary. Not deployed, routed, or granted to clients.
// authenticateBearer must independently verify the token AND return a request-
// scoped pool with transaction-local verified auth. It must not trust body claims,
// user_metadata, or a caller-selected database pool. No owner approval/activation.
import {issuePasswordVerifiedMigrationKeyChallenge} from './key-migration-challenge-issuer.mjs';
import {readOwnMigrationKeyChallenge} from './key-migration-challenge-delivery.mjs';

const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
function response(status,value) {
 return new Response(JSON.stringify(value),{status,headers:{'content-type':'application/json',
  'cache-control':'no-store','pragma':'no-cache','referrer-policy':'no-referrer','x-content-type-options':'nosniff'}});
}
export async function handleMigrationChallengeRequest(request,{authenticateBearer,timeoutMs=10000}={}) {
 if(!Number.isSafeInteger(timeoutMs)||timeoutMs<1||timeoutMs>10000)return response(400,{error:'invalid request'});
 const controller=new AbortController();
 const timer=setTimeout(()=>controller.abort(),timeoutMs);
 const deadline=new Promise((_,reject)=>controller.signal.addEventListener('abort',()=>reject(new Error('deadline')),{once:true}));
 deadline.catch(()=>{});
 const bounded=value=>Promise.race([value,deadline]);
 let reader;
 try {
  const url=new URL(request.url);
  if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash||request.method!=='POST') return response(400,{error:'invalid request'});
  if(request.headers.get('content-type')?.split(';')[0].trim()!=='application/json') return response(400,{error:'invalid request'});
  const authorization=request.headers.get('authorization');
  if(typeof authorization!=='string'||!/^Bearer [^\s]{16,4096}$/.test(authorization)||typeof authenticateBearer!=='function') return response(401,{error:'authentication required'});
  const context=await bounded(authenticateBearer(authorization.slice(7),{signal:controller.signal}));
  if(!context||!uuid.test(context.actor)||!uuid.test(context.session)||!context.pool||typeof context.pool.connect!=='function') return response(401,{error:'authentication required'});
  const declared=request.headers.get('content-length');
  if(declared!==null&&(!/^\d+$/.test(declared)||Number(declared)>8192)) return response(400,{error:'invalid request'});
  if(!request.body) return response(400,{error:'invalid request'});
  reader=request.body.getReader();
  const bytes=new Uint8Array(8192);let length=0;
  while(true) {
   const {done,value}=await bounded(reader.read());if(done)break;
   if(!(value instanceof Uint8Array)||value.length>bytes.length-length)return response(400,{error:'invalid request'});
   bytes.set(value,length);length+=value.length;
  }
  const body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes.subarray(0,length)));
  if(!body||Array.isArray(body)||typeof body!=='object'||!['issue','read'].includes(body.action)||
    Object.keys(body).some(k=>!['action','deviceId','publicKeyPem',...(body.action==='issue'?['secondPassword']:[])].includes(k))||
    !uuid.test(body.deviceId)||typeof body.publicKeyPem!=='string'||body.publicKeyPem.length>1024||
    (body.action==='issue'&&(typeof body.secondPassword!=='string'||body.secondPassword.length>1024)))return response(400,{error:'invalid request'});
  // actor/session/pool are exclusively from the trusted verification adapter.
  const args={pool:context.pool,actor:context.actor,session:context.session,deviceId:body.deviceId,publicKeyPem:body.publicKeyPem};
  if(body.action==='read')return response(200,{accepted:true,challenge:await bounded(readOwnMigrationKeyChallenge(args))});
  const result=await bounded(issuePasswordVerifiedMigrationKeyChallenge({...args,secondPassword:body.secondPassword}));
  return response(result.accepted?200:403,result);
 } catch {
  // A commit may have succeeded before transport failed. Never automatically
  // reissue; the authenticated read action reconciles the original challenge.
  return response(409,{error:'challenge outcome unavailable; read original before retry'});
 } finally {
  clearTimeout(timer);controller.abort();
  if(reader){try{Promise.resolve(reader.cancel()).catch(()=>{});}catch{}try{reader.releaseLock();}catch{}}
 }
}
