// TEST ENTRY ONLY. Production entry is src/worker.mjs and never imports this file.
import {DecoyBroker,transitionPolicy,readPolicy,claimOutbox,acknowledgeOutbox} from '../src/broker.mjs';
import {publicFetch} from '../src/worker.mjs';
import {importHmac,signCollectorV1,signCollectorV2,producerEvent,issueCapability} from '../src/protocol.mjs';
export class TestBroker extends DecoyBroker{
 async fetch(req){
  const u=new URL(req.url);if(u.hostname!=='fixture.invalid')return super.fetch(req);
  const s=this.ctx.storage,out=x=>Response.json(x);
  if(u.pathname==='/inspect')return out({policy:readPolicy(s),events:s.sql.exec('SELECT * FROM events ORDER BY event_id').toArray(),outbox:s.sql.exec('SELECT * FROM outbox ORDER BY event_id').toArray(),audit:s.sql.exec('SELECT * FROM audit').toArray()});
  const b=await req.json();
  try{
   if(u.pathname==='/transition')return out(transitionPolicy(s,{...b,now:Date.now()}));
   if(u.pathname==='/budget'){s.sql.exec('UPDATE policy SET event_budget=?,cap_budget=? WHERE id=1',b.events,b.caps);return out(true);}
   if(u.pathname==='/claim')return out(claimOutbox(s,b));
   if(u.pathname==='/ack')return out(acknowledgeOutbox(s,b));
   if(u.pathname==='/rollback'){s.transactionSync(()=>{s.sql.exec('UPDATE policy SET epoch=epoch+1 WHERE id=1');s.sql.exec("INSERT INTO events VALUES('synthetic','{}',0)");throw Error('fixture crash before commit');});}
   if(u.pathname==='/v2-vector')return out({signature:await signCollectorV2({...b,key:await importHmac(Uint8Array.from(b.keyHex.match(/../g),x=>parseInt(x,16)))})});
   if(u.pathname==='/expired'){const key=await importHmac(Uint8Array.from(this.env.CAPABILITY_KEY_HEX.match(/../g),x=>parseInt(x,16)));return out({capability:await issueCapability(key,{epoch:readPolicy(s).epoch,expires:Date.now()-1,nonce:crypto.randomUUID()})});}
   if(u.pathname==='/protocol'){const key=await importHmac(Uint8Array.from(b.keyHex.match(/../g),x=>parseInt(x,16))),event=await producerEvent({...b,key});const body=JSON.stringify(event);return out({event,body,v1:await signCollectorV1({key,collectorId:b.collectorId,timestamp:b.at,body}),v2:await signCollectorV2({key,collectorId:b.collectorId,keyVersion:7,timestamp:b.at,body})});}
  }catch{return new Response(null,{status:409});}
  return new Response(null,{status:404});
 }
}
export default {fetch:publicFetch};
