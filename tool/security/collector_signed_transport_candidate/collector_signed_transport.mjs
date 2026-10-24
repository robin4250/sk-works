import {createHmac,timingSafeEqual} from 'node:crypto';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const KEYS=['collector_id','correlation_key','event_id','event_kind','generation','key_epoch','occurred_at'];
const response=n=>new Response(null,{status:n,headers:{'Cache-Control':'no-store'}});
function keyBytes(key){if(!Buffer.isBuffer(key)||key.length!==32)throw Error('Invalid collector key');return Buffer.from(key);}
function mac(key,id,ts,body){return createHmac('sha256',key).update(`sko-collector-v1\n${id}\n${ts}\n`).update(body).digest();}
/** Server-only signer. Sign original UTF-8 bytes; never a user-selected URL or credentials. */
export function signCollectorBytes({key,collectorId,timestamp,body}){
 if(!UUID.test(collectorId)||!Number.isSafeInteger(timestamp)||timestamp<0||!Buffer.isBuffer(body)||body.length>1024)throw Error('Invalid signing input');
 return mac(keyBytes(key),collectorId,String(timestamp),body).toString('hex');
}
function validEvent(e,id,now){
 if(!e||Array.isArray(e)||typeof e!=='object'||JSON.stringify(Object.keys(e).sort())!==JSON.stringify(KEYS)||e.collector_id!==id||!UUID.test(e.event_id)||!['current_lure_touched','retired_lure_touched'].includes(e.event_kind)||!Number.isInteger(e.generation)||e.generation<1||e.generation>1000000||!(/^[a-f0-9]{64}$/.test(e.correlation_key)))return false;
 if(typeof e.occurred_at!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(e.occurred_at))return false;
 const at=Date.parse(e.occurred_at);return Number.isFinite(at)&&new Date(at).toISOString()===e.occurred_at&&at<=now+30000&&at>=now-600000&&e.key_epoch===e.occurred_at.slice(0,10);
}
/** No listener, environment lookup, secrets logging or automatic deployment. Default OFF. */
export function createCollectorSignedHandler({key,collectorId,writeEvent,enabled=()=>false,clock=()=>Date.now()}={}){
 const secret=keyBytes(key);
 if(!UUID.test(collectorId)||typeof writeEvent!=='function'||typeof enabled!=='function'||typeof clock!=='function')throw Error('Invalid collector configuration');
 return async req=>{
  let timer,reader;
  try{
   if(enabled()!==true)return response(503);
   const url=new URL(req.url);if(url.pathname!=='/collector/events'||url.search)return response(404);
   if(req.method!=='POST')return response(405);
   if(req.headers.get('content-type')!=='application/json'||req.headers.has('content-encoding'))return response(415);
   const ts=req.headers.get('x-sko-collector-time'),id=req.headers.get('x-sko-collector-id'),signature=req.headers.get('x-sko-collector-signature');
   const now=clock();if(!Number.isSafeInteger(now)||now<0) return response(503);
   if(id!==collectorId||!/^\d{13}$/.test(ts??'')||Math.abs(now-Number(ts))>60000||!(/^[a-f0-9]{64}$/.test(signature??'')))return response(401);
   const length=req.headers.get('content-length');if(length!==null&&(!/^\d+$/.test(length)||Number(length)>1024))return response(413);
   reader=req.body?.getReader();if(!reader)return response(400);
   const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('body deadline')),1000);});
   let bytes=0;const chunks=[];
   for(;;){const {done,value}=await Promise.race([reader.read(),timeout]);if(done)break;bytes+=value.byteLength;if(bytes>1024)return response(413);chunks.push(value);}
   clearTimeout(timer);const body=Buffer.concat(chunks);
   if(!timingSafeEqual(mac(secret,id,ts,body),Buffer.from(signature,'hex')))return response(401);
   let event;try{event=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(body));}catch{return response(400);}
   if(!validEvent(event,id,now))return response(400);
   // Same event retry is intentionally allowed; existing DB function owns durable
   // idempotence and rejects conflicting reuse. No transient replay cache.
   const result=await writeEvent(event);if(result!==event.event_id)return response(503);
   return response(204);
  }catch{return response(503);}finally{clearTimeout(timer);if(reader){void reader.cancel().catch(()=>{});reader.releaseLock();}}
 };
}
/** Supply one exclusive server connection already SET ROLE to the NOLOGIN bridge.
 * No dynamic role name, connection string, grants, API credentials or SQL input.
 */
export function createCollectorPgSink(client){
 if(!client||typeof client.query!=='function')throw Error('Exclusive PG client required');
 let busy=false;
 return async event=>{
  if(busy)throw Error('Exclusive collector connection busy');busy=true;
  try{
   await client.query('BEGIN');
   await client.query("SET LOCAL statement_timeout = '5s'");
   await client.query("SET LOCAL lock_timeout = '1s'");
   const role=await client.query("select current_user = 'sko_security_collector_ingest' as allowed");
   if(role.rows?.[0]?.allowed!==true)throw Error('Dedicated collector role required');
   const r=await client.query('select private.ingest_security_collector_event($1::jsonb) as event_id',[JSON.stringify(event)]);
   if(r.rows?.[0]?.event_id!==event.event_id)throw Error('Collector persistence mismatch');
   await client.query('COMMIT');return r.rows[0].event_id;
  }catch(error){try{await client.query('ROLLBACK');}catch{}throw error;}finally{busy=false;}
 };
}
