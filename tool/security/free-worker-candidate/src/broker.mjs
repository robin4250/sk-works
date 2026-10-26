import {importHmac,issueCapability,verifyCapability,producerEvent,uuid} from './protocol.mjs';
import {renderDecoy} from './wasm.mjs';
const reply=(status,value)=>new Response(value===undefined?null:JSON.stringify(value),{status,headers:{'content-type':'application/json','cache-control':'no-store'}});
export function initialize(storage){
 storage.transactionSync(()=>{
  storage.sql.exec('CREATE TABLE IF NOT EXISTS policy(id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL,epoch INTEGER NOT NULL,generation INTEGER NOT NULL,enabled INTEGER NOT NULL,quarantined INTEGER NOT NULL,sequence INTEGER NOT NULL,rendered INTEGER NOT NULL,clock INTEGER NOT NULL,day TEXT NOT NULL,events_today INTEGER NOT NULL,caps_today INTEGER NOT NULL,event_budget INTEGER NOT NULL,cap_budget INTEGER NOT NULL)');
  storage.sql.exec("INSERT OR IGNORE INTO policy VALUES(1,1,1,1,0,0,0,0,0,'',0,0,100,500)");
  storage.sql.exec('CREATE TABLE IF NOT EXISTS audit(revision INTEGER PRIMARY KEY,action TEXT NOT NULL,reason TEXT NOT NULL,occurred_at INTEGER NOT NULL)');
  storage.sql.exec('CREATE TABLE IF NOT EXISTS nonces(nonce TEXT PRIMARY KEY,expires INTEGER NOT NULL)');
  storage.sql.exec('CREATE TABLE IF NOT EXISTS events(event_id TEXT PRIMARY KEY,body TEXT NOT NULL,occurred_at INTEGER NOT NULL)');
  storage.sql.exec('CREATE TABLE IF NOT EXISTS outbox(event_id TEXT PRIMARY KEY,body TEXT NOT NULL,state TEXT NOT NULL,claim TEXT,lease_until INTEGER NOT NULL,attempts INTEGER NOT NULL,FOREIGN KEY(event_id) REFERENCES events(event_id))');
 });
}
const one=(s,q,...a)=>s.sql.exec(q,...a).toArray()[0];
export const readPolicy=s=>one(s,'SELECT * FROM policy WHERE id=1');
export function transitionPolicy(storage,{expectedRevision,action,reason,now}){
 // Not connected to any public route/RPC method. Future caller must authenticate a Master capability.
 if(!Number.isSafeInteger(expectedRevision)||!Number.isSafeInteger(now)||typeof reason!=='string'||!['enable','rotate','quarantine','release','disable'].includes(action)||!['reviewed_test','operator_review','false_positive','overload'].includes(reason))throw Error('Control rejected');
 return storage.transactionSync(()=>{const p=readPolicy(storage);if(p.revision!==expectedRevision||now<p.clock)throw Error('Policy CAS rejected');
  if(one(storage,'SELECT count(*) AS n FROM audit').n>=1000)throw Error('Audit budget unavailable');
  const revision=p.revision+1,epoch=p.epoch+1,generation=action==='rotate'?p.generation+1:p.generation;
  if(revision>1000000||epoch>1000000||generation>1000000)throw Error('Policy bounds');
  storage.sql.exec('UPDATE policy SET revision=?,epoch=?,generation=?,enabled=?,quarantined=?,clock=? WHERE id=1',revision,epoch,generation,action==='enable'?1:action==='disable'?0:p.enabled,action==='quarantine'?1:action==='release'?0:p.quarantined,now);
  storage.sql.exec('INSERT INTO audit VALUES(?,?,?,?)',revision,action,reason,now);return readPolicy(storage);
 });
}
function refreshDay(storage,now){
 const p=readPolicy(storage),day=new Date(now).toISOString().slice(0,10);if(now<p.clock)throw Error('Clock regression');
 if(p.day!==day)storage.sql.exec('UPDATE policy SET day=?,events_today=0,caps_today=0 WHERE id=1',day);
 storage.sql.exec('UPDATE policy SET clock=? WHERE id=1',now);return readPolicy(storage);
}
function key(hex){if(typeof hex!=='string'||!/^[0-9a-f]{64}$/.test(hex))throw Error('Key unavailable');return importHmac(Uint8Array.from(hex.match(/../g),x=>parseInt(x,16)));}
export function claimOutbox(storage,{now,leaseMs=10000}){
 if(!Number.isSafeInteger(now)||!Number.isInteger(leaseMs)||leaseMs<1||leaseMs>30000)throw Error('Claim rejected');
 return storage.transactionSync(()=>{const row=one(storage,"SELECT * FROM outbox WHERE attempts<3 AND (state='pending' OR(state='inflight' AND lease_until<=?)) ORDER BY event_id LIMIT 1",now);if(!row)return null;
  const claim=crypto.randomUUID();storage.sql.exec("UPDATE outbox SET state='inflight',claim=?,lease_until=?,attempts=attempts+1 WHERE event_id=?",claim,now+leaseMs,row.event_id);return {...row,claim,lease_until:now+leaseMs,attempts:row.attempts+1};
 });
}
export function acknowledgeOutbox(storage,{eventId,claim}){
 return storage.transactionSync(()=>{const row=one(storage,'SELECT * FROM outbox WHERE event_id=?',eventId);if(!row||row.state!=='inflight'||row.claim!==claim)throw Error('ACK rejected');storage.sql.exec("UPDATE outbox SET state='acknowledged',claim=NULL,lease_until=0 WHERE event_id=?",eventId);return true;});
}
export class DecoyBroker{
 constructor(ctx,env){this.ctx=ctx;this.env=env;initialize(ctx.storage);}
 async fetch(request){
  try{
   const url=new URL(request.url),now=Date.now();
   if(this.env.DECOY_ENABLED!=='true'||!uuid.test(this.env.COLLECTOR_ID)||!uuid.test(this.env.STARTUP_SESSION_ID)||this.env.CAPABILITY_KEY_HEX===this.env.DERIVATION_KEY_HEX)return reply(503);
   const p=readPolicy(this.ctx.storage);if(!p.enabled||p.quarantined)return reply(503);
   if(request.method!=='GET'||url.search||!['/capability','/observe'].includes(url.pathname))return reply(404);
   const capabilityKey=await key(this.env.CAPABILITY_KEY_HEX);
   if(url.pathname==='/capability'){
    const nonce=crypto.randomUUID(),expires=now+60000;
    const epoch=this.ctx.storage.transactionSync(()=>{const q=refreshDay(this.ctx.storage,now);if(!q.enabled||q.quarantined||q.caps_today>=q.cap_budget)throw Error('Budget unavailable');this.ctx.storage.sql.exec('UPDATE policy SET caps_today=caps_today+1 WHERE id=1');return q.epoch;});
    return reply(200,{capability:await issueCapability(capabilityKey,{epoch,expires,nonce}),expires});
   }
   const cap=await verifyCapability(capabilityKey,request.headers.get('x-sko-decoy-capability'),now);
   const generation=Number(request.headers.get('x-sko-decoy-generation'));
   if(!cap)return reply(401);if(!Number.isInteger(generation)||generation<1||generation>1000000)return reply(404);
   const snapshot=readPolicy(this.ctx.storage);if(cap.epoch!==snapshot.epoch)return reply(401);
   const kind=generation===snapshot.generation?'current_lure_touched':'retired_lure_touched';
   if(generation>snapshot.generation)return reply(404);
   const event=await producerEvent({key:await key(this.env.DERIVATION_KEY_HEX),collectorId:this.env.COLLECTOR_ID,sessionId:this.env.STARTUP_SESSION_ID,sequence:snapshot.sequence+1,at:now,kind,generation}),body=JSON.stringify(event);
   this.ctx.storage.transactionSync(()=>{
    const q=refreshDay(this.ctx.storage,now);
    if(!q.enabled||q.quarantined||q.epoch!==cap.epoch||q.revision!==snapshot.revision||q.sequence!==snapshot.sequence)throw Error('Admission CAS rejected');
    if(one(this.ctx.storage,'SELECT nonce FROM nonces WHERE nonce=?',cap.nonce))throw Error('Capability already used');
    if(q.events_today>=q.event_budget||one(this.ctx.storage,'SELECT count(*) AS n FROM events').n>=1000)throw Error('Budget unavailable');
    this.ctx.storage.sql.exec('INSERT INTO nonces VALUES(?,?)',cap.nonce,cap.expires);
    this.ctx.storage.sql.exec('INSERT INTO events VALUES(?,?,?)',event.event_id,body,now);
    this.ctx.storage.sql.exec("INSERT INTO outbox VALUES(?,?,'pending',NULL,0,0)",event.event_id,body);
    this.ctx.storage.sql.exec('UPDATE policy SET sequence=sequence+1,events_today=events_today+1 WHERE id=1');
   });
   if(kind==='retired_lure_touched')return reply(404);
   const result=await renderDecoy();this.ctx.storage.sql.exec('UPDATE policy SET rendered=rendered+1 WHERE id=1');
   return new Response(result,{headers:{'content-type':'application/json','cache-control':'no-store'}});
  }catch{return reply(503);}
 }
}
