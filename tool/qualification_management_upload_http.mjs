import {createQualificationUploadInspector} from './qualification_management_upload_inspection.mjs';
const isUuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
const maxBodyBytes=1024;
class HttpFailure extends Error{constructor(status,code,retry){super(code);this.status=status;this.code=code;this.retry=retry;}}
const response=(status,body,extra={})=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff',...extra}});
async function timed(work,ms,failure){let timer;try{return await Promise.race([Promise.resolve().then(work),new Promise((_,reject)=>{timer=setTimeout(()=>reject(failure),ms);})]);}finally{clearTimeout(timer);}}
async function bodyIds(request,timeoutMs){
 const length=request.headers.get('content-length');
 if(length!==null&&(!/^(0|[1-9][0-9]*)$/.test(length)||!Number.isSafeInteger(Number(length))))throw new HttpFailure(400,'invalid_request');
 if(length!==null&&Number(length)>maxBodyBytes)throw new HttpFailure(413,'request_too_large');
 if(!request.body)throw new HttpFailure(400,'invalid_request');
 const reader=request.body.getReader(),chunks=[];let total=0,count=0;
 try{
  await timed(async()=>{for(;;){const{done,value}=await reader.read();if(done)break;if(++count>256)throw new HttpFailure(413,'request_too_large');if(!(value instanceof Uint8Array))throw new HttpFailure(400,'invalid_request');total+=value.length;if(total>maxBodyBytes)throw new HttpFailure(413,'request_too_large');chunks.push(value);}},timeoutMs,new HttpFailure(408,'request_timeout'));
  if(length!==null&&Number(length)!==total)throw new HttpFailure(400,'invalid_request');
  const bytes=new Uint8Array(total);let offset=0;for(const part of chunks){bytes.set(part,offset);offset+=part.length;}
  let text,value;try{text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);value=JSON.parse(text);}catch{throw new HttpFailure(400,'invalid_request');}
  // This endpoint accepts only two literal JSON UUID strings, with either key
  // order. Escaped keys/values, duplicate members and nested bodies are refused.
  const match=/^\s*\{\s*"(request_id|slot_id)"\s*:\s*"([a-fA-F0-9-]{36})"\s*,\s*"(request_id|slot_id)"\s*:\s*"([a-fA-F0-9-]{36})"\s*\}\s*$/.exec(text);
  if(!value||Array.isArray(value)||!match||match[1]===match[3]||Object.keys(value).length!==2||!isUuid(value.request_id)||!isUuid(value.slot_id))throw new HttpFailure(400,'invalid_request');
  return{requestId:value.request_id.toLowerCase(),slotId:value.slot_id.toLowerCase()};
 }finally{reader.cancel().catch(()=>{});try{reader.releaseLock();}catch{}}
}

// Unregistered Fetch handler candidate. The host must provide a real session
// verifier and an atomic shared limiter. clientKey is a host-generated HMAC of
// trusted network context, never X-Forwarded-For or another request field.
export function createQualificationInspectionHttpEndpoint({pathname,verifySession,rateLimiter,db,storage,validateFile,bodyTimeoutMs=2000,dependencyTimeoutMs=2000}){
 if(typeof pathname!=='string'||!/^\/[A-Za-z0-9/_-]{1,127}$/.test(pathname)||typeof verifySession!=='function'||typeof rateLimiter?.take!=='function'||typeof db?.authorizedPendingSlot!=='function'||typeof db?.commitReceiptAtomically!=='function'||typeof storage?.readImmutableVersion!=='function'||typeof validateFile!=='function'||!Number.isSafeInteger(bodyTimeoutMs)||bodyTimeoutMs<10||bodyTimeoutMs>5000||!Number.isSafeInteger(dependencyTimeoutMs)||dependencyTimeoutMs<10||dependencyTimeoutMs>5000)throw Error('inspection_unavailable');
 async function charge(input){
  const result=await timed(()=>rateLimiter.take(Object.freeze(input)),dependencyTimeoutMs,new HttpFailure(503,'inspection_unavailable'));
  if(result?.allowed===true)return;
  if(result?.allowed===false&&Number.isSafeInteger(result.retryAfterSeconds)&&result.retryAfterSeconds>=1&&result.retryAfterSeconds<=3600)throw new HttpFailure(429,'rate_limited',result.retryAfterSeconds);
  throw new HttpFailure(503,'inspection_unavailable');
 }
 return async function handle(request,context){
  try{
   if(!(request instanceof Request))throw new HttpFailure(400,'invalid_request');
   const url=new URL(request.url);if(url.pathname!==pathname||url.search||url.hash||url.protocol!=='https:')throw new HttpFailure(404,'not_found');
   if(request.method!=='POST')return response(405,{error:'method_not_allowed'},{allow:'POST'});
   if(request.signal.aborted)throw new HttpFailure(408,'request_timeout');
   if(typeof context?.clientKey!=='string'||!/^[a-f0-9]{64}$/.test(context.clientKey))throw new HttpFailure(503,'inspection_unavailable');
   await charge({bucket:'qualification-inspection-ingress-v1',subject:context.clientKey,limit:60,windowSeconds:60});
   const contentType=request.headers.get('content-type');if(!contentType||!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(contentType))throw new HttpFailure(415,'unsupported_media_type');
   const encoding=request.headers.get('content-encoding');if(encoding!==null&&encoding.toLowerCase()!=='identity')throw new HttpFailure(415,'unsupported_media_type');
   const auth=request.headers.get('authorization');if(typeof auth!=='string'||auth.length>8192||!/^Bearer [A-Za-z0-9._~-]+$/.test(auth))throw new HttpFailure(401,'authentication_required');
   const bearerToken=auth.slice(7),ids=await bodyIds(request,bodyTimeoutMs);
   const inspect=createQualificationUploadInspector({db,storage,validateFile,verifySession:async token=>{
    if(request.signal.aborted)throw new HttpFailure(408,'request_timeout');
    const verified=await timed(()=>verifySession(token),dependencyTimeoutMs,new HttpFailure(503,'inspection_unavailable'));
    if(!verified||verified.active!==true||verified.anonymous!==false||!isUuid(verified.actorId)||!isUuid(verified.sessionId))throw new HttpFailure(401,'authentication_required');
    const session=Object.freeze({active:true,anonymous:false,actorId:verified.actorId,sessionId:verified.sessionId});
    await charge({bucket:'qualification-inspection-actor-v1',subject:session.actorId,limit:20,windowSeconds:60});
    if(request.signal.aborted)throw new HttpFailure(408,'request_timeout');
    return session;
   }});
   const result=await inspect({bearerToken,...ids});
   if(result?.inspected!==true||result.requestId!==ids.requestId||result.slotId!==ids.slotId)throw new HttpFailure(503,'inspection_unavailable');
   return response(200,{inspected:true,request_id:result.requestId,slot_id:result.slotId});
  }catch(error){
   if(error instanceof HttpFailure)return response(error.status,{error:error.code},error.retry?{'retry-after':String(error.retry)}:{});
   const code=error instanceof Error?error.message:'';
   if(code==='invalid_file')return response(422,{error:'invalid_file'});
   if(code==='inspection_conflict')return response(409,{error:'inspection_conflict'});
   if(code==='inspection_unavailable')return response(403,{error:'inspection_unavailable'});
   return response(503,{error:'inspection_unavailable'});
  }finally{if(request instanceof Request&&request.body&&!request.body.locked)request.body.cancel().catch(()=>{});}
 };
}
