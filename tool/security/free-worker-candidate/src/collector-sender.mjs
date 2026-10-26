// Trusted companion only. Not imported by the public Worker and not scheduled.
// No Supabase service credential, user bearer, recipient or arbitrary destination.
import {importHmac,signCollectorV2,uuid} from './protocol.mjs';
export const collectorEndpoint='https://ztktgquxvcxcjxtluspu.supabase.co/functions/v1/security-collector-ingest';
const encoder=new TextEncoder(),keyPattern=/^[a-f0-9]{64}$/;
const one=(s,q,...args)=>s.sql.exec(q,...args).toArray()[0];
const eventKeys='collector_id,correlation_key,event_id,event_kind,generation,key_epoch,occurred_at';
function validEvent(row,collectorId,now){
 if(typeof row.body!=='string'||encoder.encode(row.body).length>1024)return 'held_invalid';
 let event;try{event=JSON.parse(row.body);}catch{return 'held_invalid';}
 if(!event||Array.isArray(event)||JSON.stringify(event)!==row.body||Object.keys(event).sort().join(',')!==eventKeys||
  event.event_id!==row.event_id||!uuid.test(event.event_id)||event.collector_id!==collectorId||
  !['current_lure_touched','retired_lure_touched'].includes(event.event_kind)||
  !Number.isInteger(event.generation)||event.generation<1||event.generation>1000000||
  typeof event.correlation_key!=='string'||!keyPattern.test(event.correlation_key)||
  typeof event.occurred_at!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(event.occurred_at))return 'held_invalid';
 const at=Date.parse(event.occurred_at);
 if(!Number.isFinite(at)||new Date(at).toISOString()!==event.occurred_at||
  at!==row.occurred_at||event.key_epoch!==event.occurred_at.slice(0,10))return 'held_invalid';
 if(at>now+30000)return 'held_clock';
 if(at<now-600000)return 'held_expired';
 return null;
}
function initializeReceipts(s){
 s.sql.exec('CREATE TABLE IF NOT EXISTS collector_delivery_receipts(event_id TEXT PRIMARY KEY,last_result TEXT NOT NULL,updated_at INTEGER NOT NULL,acknowledged_at INTEGER,FOREIGN KEY(event_id) REFERENCES events(event_id))');
}
function receipt(s,id,result,now){
 s.sql.exec('INSERT INTO collector_delivery_receipts VALUES(?,?,?,?) ON CONFLICT(event_id) DO UPDATE SET last_result=excluded.last_result,updated_at=excluded.updated_at,acknowledged_at=excluded.acknowledged_at',
  id,result,now,result==='acknowledged'?now:null);
}
export function createCollectorSender({enabled=false,collectorId,keyVersion,keyHex,
 capabilityKeyHex,derivationKeyHex,fetcher=fetch,clock=()=>Date.now(),timeoutMs=5000}={}){
 if(typeof enabled!=='boolean'||typeof fetcher!=='function'||typeof clock!=='function'||
  !Number.isInteger(timeoutMs)||timeoutMs<1||timeoutMs>5000)throw Error('Collector sender configuration rejected');
 const ready=enabled&&uuid.test(collectorId??'')&&Number.isInteger(keyVersion)&&keyVersion>=1&&keyVersion<=1000000&&
  [keyHex,capabilityKeyHex,derivationKeyHex].every(k=>typeof k==='string'&&keyPattern.test(k))&&
  new Set([keyHex,capabilityKeyHex,derivationKeyHex]).size===3;
 if(enabled&&!ready)throw Error('Collector sender configuration rejected');
 const key=ready?importHmac(Uint8Array.from(keyHex.match(/../g),x=>parseInt(x,16))):null;
 return async storage=>{
  if(!ready)return {state:'disabled'};
  const now=clock();if(!Number.isSafeInteger(now)||now<1000000000000)return {state:'held_clock'};
  const signingKey=await key;
  const row=storage.transactionSync(()=>{
   initializeReceipts(storage);
   const next=one(storage,"SELECT o.*,e.occurred_at,e.body AS event_body FROM outbox o JOIN events e ON e.event_id=o.event_id WHERE (o.state='pending' OR o.state='inflight') AND o.lease_until<=? ORDER BY e.occurred_at,o.event_id LIMIT 1",now);
   if(!next)return null;
   const invalid=next.body!==next.event_body?'held_invalid':validEvent(next,collectorId,now);
   if(invalid||next.attempts>=3){const state=invalid??'held_attempts';storage.sql.exec('UPDATE outbox SET state=?,claim=NULL,lease_until=0 WHERE event_id=?',state,next.event_id);receipt(storage,next.event_id,state,now);return {held:state,event_id:next.event_id};}
   const claim=crypto.randomUUID(),attempts=next.attempts+1;
   storage.sql.exec("UPDATE outbox SET state='inflight',claim=?,lease_until=?,attempts=? WHERE event_id=?",claim,now+10000,attempts,next.event_id);
   receipt(storage,next.event_id,'inflight',now);
   return {...next,claim,attempts};
  });
  if(!row)return {state:'idle'};
  if(row.held)return {state:row.held,event_id:row.event_id};
  let timer,result='retry',controller=new AbortController();
  try{
   const signature=await signCollectorV2({key:signingKey,collectorId,keyVersion,timestamp:now,body:row.body});
   const response=await Promise.race([
    // workerd supports manual/follow, not redirect:error. Never follow redirects.
    fetcher(collectorEndpoint,{method:'POST',redirect:'manual',signal:controller.signal,
     headers:{'content-type':'application/json','x-sko-collector-id':collectorId,
      'x-sko-collector-key-version':String(keyVersion),'x-sko-collector-time':String(now),'x-sko-collector-signature':signature},body:row.body}),
    new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(Error('Collector delivery deadline'));},timeoutMs);})
   ]);
   const length=response.headers.get('content-length');
   if(response.status===204&&response.body===null&&(length===null||length==='0'))result='acknowledged';
   else if(response.status>=300&&response.status<400)result='held_redirect';
   else if([401,403].includes(response.status))result='held_auth';
   else if([400,404,405,413,415].includes(response.status))result='held_invalid';
   void response.body?.cancel().catch(()=>{});
  }catch{/* Unknown acknowledgement retries the identical saved event body. */}
  finally{clearTimeout(timer);controller.abort();}
  const ended=clock();
  if(!Number.isSafeInteger(ended)||ended<now)return {state:'inflight',event_id:row.event_id};
  return storage.transactionSync(()=>{
   const current=one(storage,'SELECT * FROM outbox WHERE event_id=?',row.event_id);
   if(!current||current.state!=='inflight'||current.claim!==row.claim||current.body!==row.body)return {state:'claim_lost',event_id:row.event_id};
   if(result==='retry'&&row.attempts>=3)result='held_attempts';
   const state=result==='retry'?'pending':result;
   storage.sql.exec('UPDATE outbox SET state=?,claim=NULL,lease_until=? WHERE event_id=?',state,result==='retry'?ended+(row.attempts===1?1000:5000):0,row.event_id);
   receipt(storage,row.event_id,result,ended);
   return {state,event_id:row.event_id,attempts:row.attempts};
  });
 };
}
