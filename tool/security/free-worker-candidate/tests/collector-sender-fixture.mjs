// TEST ENTRY ONLY. Never imported by src/worker.mjs.
import {DecoyBroker,transitionPolicy,readPolicy} from '../src/broker.mjs';
import {publicFetch} from '../src/worker.mjs';
import {createCollectorSender} from '../src/collector-sender.mjs';
export class SenderFixtureBroker extends DecoyBroker{
 async fetch(req){
  const u=new URL(req.url);if(u.hostname!=='fixture.invalid')return super.fetch(req);
  const s=this.ctx.storage;
  if(u.pathname==='/inspect'){
   const tables=s.sql.exec("SELECT name FROM sqlite_master WHERE type='table'").toArray().map(x=>x.name);
   return Response.json({policy:readPolicy(s),events:s.sql.exec('SELECT * FROM events ORDER BY event_id').toArray(),outbox:s.sql.exec('SELECT * FROM outbox ORDER BY event_id').toArray(),
    tables,deliveryError:this.deliveryError??null,receipts:tables.includes('collector_delivery_receipts')?s.sql.exec('SELECT * FROM collector_delivery_receipts ORDER BY event_id').toArray():[]});
  }
  const b=await req.json();
  try{
   if(u.pathname==='/enable')return Response.json(transitionPolicy(s,{expectedRevision:readPolicy(s).revision,action:'enable',reason:'reviewed_test',now:Date.now()}));
   if(u.pathname==='/deliver'){
    const sender=createCollectorSender({enabled:b.enabled!==false,collectorId:this.env.COLLECTOR_ID,keyVersion:7,keyHex:b.reusedKey?this.env.CAPABILITY_KEY_HEX:'33'.repeat(32),
     capabilityKeyHex:this.env.CAPABILITY_KEY_HEX,derivationKeyHex:this.env.DERIVATION_KEY_HEX,
     fetcher:b.ignoreAbort?()=>new Promise(()=>{}):async(...args)=>{try{return await this.env.COLLECTOR.fetch(...args);}catch(error){this.deliveryError=String(error);throw error;}},
     clock:()=>Date.now()+(b.offset??0),timeoutMs:b.timeoutMs??5000});
    return Response.json(await sender(s));
   }
   if(u.pathname==='/corrupt'){s.sql.exec("UPDATE outbox SET body=body||' '");return Response.json(true);}
   if(u.pathname==='/receipt-failure'){s.sql.exec("CREATE TRIGGER reject_delivery_ack BEFORE UPDATE ON collector_delivery_receipts WHEN NEW.last_result='acknowledged' BEGIN SELECT RAISE(ABORT,'fixture ACK write failure'); END");return Response.json(true);}
   if(u.pathname==='/remove-failure'){s.sql.exec('DROP TRIGGER reject_delivery_ack');return Response.json(true);}
  }catch{return new Response(null,{status:409});}
  return new Response(null,{status:404});
 }
}
export default {fetch:publicFetch};
