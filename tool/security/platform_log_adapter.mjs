import {createHmac} from 'node:crypto';
// Server-only library: no automatic execution, credentials, environment lookup,
// arbitrary SQL, project override, client imports, or production deployment hook.
const sources=new Set(['edge_logs','postgres_logs','auth_audit_logs']);
const iso=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
export function validateWindow(from,to){
 if(!iso.test(from)||!iso.test(to)||new Date(from).toISOString()!==from||new Date(to).toISOString()!==to||Date.parse(to)<=Date.parse(from)||Date.parse(to)-Date.parse(from)>900000)throw Error('Invalid log window');
}
export function platformQuery(source,from,to){
 if(!sources.has(source))throw Error('Unsupported log source');
 validateWindow(from,to);
 // Confirmed ClickHouse fields, not raw event_message/headers/query/IP/body.
 const fields=source==='edge_logs'?", log_attributes['response.status_code'] as status, log_attributes['request.path'] as target":source==='postgres_logs'?", log_attributes['parsed.sql_state_code'] as sqlstate":"";
 const literal=t=>t.replace('T',' ').slice(0,-1);
 return `select id, timestamp${fields} from logs where source = '${source}' and timestamp >= toDateTime64('${literal(from)}',3,'UTC') and timestamp < toDateTime64('${literal(to)}',3,'UTC') order by timestamp asc, id asc limit 1000`;
}
function at(value){
 // ClickHouse DateTime64 UTC can omit Z and use microseconds. Do not infer a local timezone.
 if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z?$/.test(value))throw Error('Invalid log timestamp');
 const normalized=value.replace(' ','T');const d=new Date(normalized.endsWith('Z')?normalized:normalized+'Z');if(!Number.isFinite(+d))throw Error('Invalid log timestamp');return d.toISOString();
}
export function sanitizePlatformRows({source,rows,from,to,hmacKey,keyEpoch}){
 validateWindow(from,to);platformQuery(source,from,to);
 if(!Buffer.isBuffer(hmacKey)||hmacKey.length<32||!Number.isInteger(keyEpoch)||keyEpoch<1||keyEpoch>1000000||!Array.isArray(rows)||rows.length>1000)throw Error('Invalid adapter input');
 const hash=(kind,value)=>createHmac('sha256',hmacKey).update(`${keyEpoch}\0${kind}\0${source}\0${value}`).digest('hex');
 const events=[],seen=new Set();
 for(const row of rows.slice(0,1000)){
  if(!row||typeof row.id!=='string'||row.id.length<1||row.id.length>256)throw Error('Invalid upstream identity');
  const occurred_at=at(row.timestamp);if(occurred_at<from||occurred_at>=to)throw Error('Out of window log');
  const event_key=hash('id',row.id);if(seen.has(event_key))throw Error('Duplicate upstream identity');seen.add(event_key);
  let result='unknown';
  if(source==='edge_logs'){
   const n=typeof row.status==='number'?row.status:/^\d{3}$/.test(row.status??'')?Number(row.status):0;
   if(n===401)result='unauthenticated';else if(n===403)result='forbidden';else if(n===429)result='rate_limited';else if(n>=500&&n<=599)result='server_error';else if(n>=200&&n<=299)result='http_success';
  }else if(source==='postgres_logs'&&row.sqlstate==='42501')result='permission_denied';
  // A 200/empty response is never classified as a successful RLS bypass or attack.
  const target_key=source==='edge_logs'&&typeof row.target==='string'&&row.target.startsWith('/')&&row.target.length<=4096?hash('target',row.target.split(/[?#]/,1)[0]):null;
  events.push({event_key,occurred_at,result,target_key,source_key:null,source_tracking:'unavailable'});
 }
 return {source,window_from:from,window_to:to,key_epoch:keyEpoch,coverage:rows.length>=1000?'capacity_limited':'bounded_query',events};
}
export async function collectPlatformWindow({projectRef,source,from,to,hmacKey,keyEpoch,managementToken,fetchImpl=fetch}){
 validateWindow(from,to);const sql=platformQuery(source,from,to);
 if(!/^[a-z]{20}$/.test(projectRef)||typeof managementToken!=='string'||managementToken.length<16||/[\r\n]/.test(managementToken))throw Error('Invalid server configuration');
 const url=new URL(`https://api.supabase.com/v1/projects/${projectRef}/analytics/endpoints/logs`);
 url.searchParams.set('sql',sql);// The API rounds bounds to minutes. Enclose the requested interval, then apply
 // its exact half-open boundaries in SQL so minute rounding cannot drop records.
 url.searchParams.set('iso_timestamp_start',new Date(Math.floor(Date.parse(from)/60000)*60000).toISOString());
 url.searchParams.set('iso_timestamp_end',new Date(Math.ceil(Date.parse(to)/60000)*60000).toISOString());
 try{
  const r=await fetchImpl(url,{headers:{Authorization:`Bearer ${managementToken}`},redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!r.ok)throw Error('Upstream unavailable');
  // Limit streaming bytes before JSON parse: no unbounded response.text/json.
  if(!r.body)throw Error('Upstream unavailable');
  const reader=r.body.getReader(),chunks=[];let bytes=0;
  try{for(;;){const {done,value}=await reader.read();if(done)break;bytes+=value.byteLength;if(bytes>1024*1024)throw Error('Upstream unavailable');chunks.push(value);}}finally{await reader.cancel();}
  const payload=JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if(!payload||!Array.isArray(payload.result)||payload.error)throw Error('Upstream unavailable');
  return sanitizePlatformRows({source,rows:payload.result,from,to,hmacKey,keyEpoch});
 }catch{throw Error('Platform log collection unavailable');}
}
// Caller must keep Management API/OAuth credentials on a trusted server and send
// only this sanitized batch to service-only RPC. No credential is persisted here.
