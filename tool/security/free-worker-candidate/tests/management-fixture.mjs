// TEST ONLY: ephemeral fixture keys and direct inspection are absent from production graph.
import {DecoyBroker,readPolicy} from '../src/broker.mjs';
import {initializeSecurity,securityState,verifyAuditChain,acceptIndependentAnchor,pruneAnchoredAudit} from '../src/security-audit.mjs';
import {applyManagedCommand} from '../src/management.mjs';
export class ManagementFixture extends DecoyBroker{
 async fetch(request){
  const path=new URL(request.url).pathname,s=this.ctx.storage;
  if(path==='/snapshot')return Response.json({security:securityState(s),policy:readPolicy(s),signed:s.sql.exec('SELECT * FROM signed_audit ORDER BY sequence').toArray(),nonces:s.sql.exec('SELECT * FROM management_nonces').toArray()});
  const b=await request.json();
  try{
   if(path==='/initialize')return Response.json(initializeSecurity(s,b));
   if(path==='/command'){const auditKey=await crypto.subtle.importKey('jwk',JSON.parse(this.env.FIXTURE_AUDIT_PRIVATE),'Ed25519',false,['sign']);return Response.json(await applyManagedCommand(s,{...b,auditKey}));}
   if(path==='/verify')return Response.json(await verifyAuditChain(s,b.minimumAnchor??null));
   if(path==='/anchor')return Response.json(await acceptIndependentAnchor(s,b.envelope,b.now));
   if(path==='/prune'){const auditKey=await crypto.subtle.importKey('jwk',JSON.parse(this.env.FIXTURE_AUDIT_PRIVATE),'Ed25519',false,['sign']);return Response.json(await pruneAnchoredAudit(s,{...b,auditKey}));}
   if(path==='/fail-signed-audit'){s.sql.exec("CREATE TRIGGER fail_signed_audit BEFORE INSERT ON signed_audit BEGIN SELECT RAISE(ABORT,'synthetic failure'); END");return Response.json(true);}
   if(path==='/tamper-body'){s.sql.exec('UPDATE signed_audit SET body=? WHERE sequence=?',b.body,b.sequence);return Response.json(true);}
   if(path==='/truncate'){s.sql.exec('DELETE FROM signed_audit WHERE sequence>?',b.sequence);s.sql.exec('UPDATE security_state SET audit_seq=?,audit_hash=? WHERE id=1',b.sequence,b.hash);return Response.json(true);}
  }catch{return new Response(null,{status:409});}
  return new Response(null,{status:404});
 }
}
export default {fetch:()=>new Response(null,{status:404})};
