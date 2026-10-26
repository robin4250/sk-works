// Trusted collector only. The isolated decoy never receives the service key.
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const KEYS=['collector_id','correlation_key','event_id','event_kind','generation','key_epoch','occurred_at'];
const reply=status=>new Response(null,{status,headers:{'Cache-Control':'no-store'}});
const unhex=s=>Uint8Array.from(s.match(/../g),x=>parseInt(x,16));
function base64(bytes){let s='';for(const n of bytes)s+=String.fromCharCode(n);return btoa(s);}
function valid(e,id,now){
 if(!e||Array.isArray(e)||typeof e!=='object'||JSON.stringify(Object.keys(e).sort())!==JSON.stringify(KEYS)||e.collector_id!==id||!UUID.test(e.event_id)||!['current_lure_touched','retired_lure_touched'].includes(e.event_kind)||!Number.isInteger(e.generation)||e.generation<1||e.generation>1000000||typeof e.correlation_key!=='string'||!/^[a-f0-9]{64}$/.test(e.correlation_key)||typeof e.occurred_at!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(e.occurred_at))return false;
 const at=Date.parse(e.occurred_at);return Number.isFinite(at)&&new Date(at).toISOString()===e.occurred_at&&at<=now+30000&&at>=now-600000&&e.key_epoch===e.occurred_at.slice(0,10);
}
export function createSecurityCollectorHandler({baseUrl,serviceKey,keys=[],enabled=()=>false,fetcher=fetch,clock=()=>Date.now()}={}){
 const base=new URL(baseUrl);if(base.protocol!=='https:'||base.username||base.password||base.pathname!=='/'||base.search||base.hash||!serviceKey||typeof serviceKey!=='string'||typeof fetcher!=='function'||typeof enabled!=='function'||typeof clock!=='function'||!Array.isArray(keys)||keys.length>8)throw Error('Invalid trusted collector configuration');
 const registry=new Map();for(const entry of keys){if(!entry||Object.keys(entry).sort().join(',')!=='collector_id,key_hex,key_version'||!UUID.test(entry.collector_id)||!Number.isInteger(entry.key_version)||entry.key_version<1||entry.key_version>1000000||typeof entry.key_hex!=='string'||!/^[a-f0-9]{64}$/.test(entry.key_hex))throw Error('Invalid collector key configuration');const id=entry.collector_id+':'+entry.key_version;if(registry.has(id))throw Error('Duplicate collector key configuration');registry.set(id,crypto.subtle.importKey('raw',unhex(entry.key_hex),{name:'HMAC',hash:'SHA-256'},false,['verify']));}
 return async req=>{
  let reader,timer,upstreamTimer;const controller=new AbortController();
  try{
   if(enabled()!==true)return reply(503);
   const url=new URL(req.url);if(!['/security-collector-ingest','/functions/v1/security-collector-ingest'].includes(url.pathname)||url.search)return reply(404);
   if(req.method!=='POST')return reply(405);
   if(req.headers.get('content-type')!=='application/json'||req.headers.has('content-encoding'))return reply(415);
   const id=req.headers.get('x-sko-collector-id'),v=req.headers.get('x-sko-collector-key-version'),ts=req.headers.get('x-sko-collector-time'),signature=req.headers.get('x-sko-collector-signature');
   const now=clock();if(!Number.isSafeInteger(now)||now<1000000000000)return reply(503);
   if(!UUID.test(id??'')||!/^[1-9][0-9]{0,6}$/.test(v??'')||Number(v)>1000000||!/^\d{13}$/.test(ts??'')||Math.abs(now-Number(ts))>60000||!/^[a-f0-9]{64}$/.test(signature??''))return reply(401);
   const key=registry.get(id+':'+v);if(!key)return reply(401);
   const length=req.headers.get('content-length');if(length!==null&&(!/^\d+$/.test(length)||Number(length)>1024))return reply(413);
   reader=req.body?.getReader();if(!reader)return reply(400);
   const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('body deadline')),1000);});let total=0;const chunks=[];
   for(;;){const {done,value}=await Promise.race([reader.read(),deadline]);if(done)break;total+=value.byteLength;if(total>1024)return reply(413);chunks.push(value);}
   clearTimeout(timer);const raw=new Uint8Array(total);let offset=0;for(const chunk of chunks){raw.set(chunk,offset);offset+=chunk.byteLength;}
   const prefix=new TextEncoder().encode(`sko-collector-v2\n${id}\n${v}\n${ts}\n`);const signed=new Uint8Array(prefix.byteLength+raw.byteLength);signed.set(prefix);signed.set(raw,prefix.byteLength);
   if(!await crypto.subtle.verify('HMAC',await key,unhex(signature),signed))return reply(401);
   let event;try{event=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw));}catch{return reply(400);}
   if(!valid(event,id,now))return reply(400);
   upstreamTimer=setTimeout(()=>controller.abort(),5000);
   const result=await fetcher(new URL('rest/v1/rpc/ingest_signed_security_collector_event',base),{method:'POST',headers:{apikey:serviceKey,'Content-Type':'application/json'},body:JSON.stringify({p_envelope:{collector_id:id,key_version:Number(v),timestamp:Number(ts),body_base64:base64(raw),signature}}),signal:controller.signal});
   if(result.status!==200)return reply(503);
   const lengthResult=result.headers.get('content-length');if(lengthResult!==null&&Number(lengthResult)>128){void result.body?.cancel();return reply(503);}
   const rr=result.body?.getReader();if(!rr)return reply(503);let count=0;const parts=[];try{for(;;){const part=await rr.read();if(part.done)break;count+=part.value.byteLength;if(count>128){void rr.cancel();return reply(503);}parts.push(part.value);}}finally{rr.releaseLock();}
   const bytes=new Uint8Array(count);offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.byteLength;}
   let returned;try{returned=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{return reply(503);}
   return returned===event.event_id?reply(204):reply(503);
  }catch{return reply(503);}finally{clearTimeout(timer);clearTimeout(upstreamTimer);controller.abort();if(reader){void reader.cancel().catch(()=>{});reader.releaseLock();}}
 };
}
