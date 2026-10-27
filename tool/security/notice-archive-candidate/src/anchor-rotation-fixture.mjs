// Review-only key-rotation experiment for an isolated existing authority.
// No HTTP endpoint, authorization, production key access or lost-key recovery.
import {latestIndependentAnchor} from './anchor-authority.mjs';
import {publicJwk,signBytes,verified} from './security-audit.mjs';
const one=(s,q,...a)=>s.sql.exec(q,...a).toArray()[0];
const ident=x=>typeof x==='string'&&/^[A-Za-z0-9_-]{1,64}$/.test(x);
const domain='sko-anchor-key-rotation-fixture-v1';
const state=s=>{const q=one(s,'SELECT * FROM anchor_authority WHERE id=1');if(!q)throw Error('authority unavailable');return q;};
function payload(q,newId,newJwk,now){return {v:1,deployment_id:q.deployment_id,company_id:q.company_id,sequence:q.sequence,hash:q.hash,old_key_id:q.anchor_key_id,old_jwk:JSON.parse(q.anchor_jwk),new_key_id:newId,new_jwk:newJwk,issued_at:now,old_receipt:q.receipt};}
export async function rotateAuthorityFixture(s,{newId,newJwk,oldKey,newKey,now}){
 if(!ident(newId)||!Number.isSafeInteger(now)||now<0)throw Error('rotation invalid');
 const q=state(s),pub=publicJwk(newJwk);await latestIndependentAnchor(s);
 if(q.sequence<1||q.receipt===null||newId===q.anchor_key_id||newId===q.audit_key_id||pub.x===JSON.parse(q.anchor_jwk).x||pub.x===JSON.parse(q.audit_jwk).x||now<q.clock)throw Error('rotation invalid');
 const p=payload(q,newId,pub,now),body=JSON.stringify(p);
 const oldSignature=await signBytes(oldKey,domain,body),newSignature=await signBytes(newKey,domain,body);
 if(!await verified(p.old_jwk,domain,body,oldSignature)||!await verified(pub,domain,body,newSignature))throw Error('rotation proof rejected');
 const receiptPayload={v:1,deployment_id:q.deployment_id,sequence:q.sequence,hash:q.hash,issued_at:now,key_id:newId},receiptBody=JSON.stringify(receiptPayload),receiptSignature=await signBytes(newKey,'sko-decoy-anchor-v1',receiptBody);
 if(!await verified(pub,'sko-decoy-anchor-v1',receiptBody,receiptSignature))throw Error('new receipt rejected');
 const nextReceipt=JSON.stringify({payload:receiptPayload,signature:receiptSignature});
 return s.transactionSync(()=>{
  const cur=state(s);if(JSON.stringify(cur)!==JSON.stringify(q))throw Error('authority changed');
  s.sql.exec('CREATE TABLE IF NOT EXISTS anchor_rotation_history(id INTEGER PRIMARY KEY,transition TEXT NOT NULL,old_signature TEXT NOT NULL,new_signature TEXT NOT NULL,new_receipt TEXT NOT NULL)');
  const n=one(s,'SELECT count(*) AS n FROM anchor_rotation_history').n;if(n>=100)throw Error('rotation capacity');
  if(one(s,'SELECT 1 AS n FROM anchor_rotation_history WHERE json_extract(transition,\'$.new_key_id\')=? OR json_extract(transition,\'$.old_key_id\')=?',newId,newId))throw Error('key identifier reused');
  const old=one(s,'SELECT * FROM anchor_receipts WHERE sequence=?',q.sequence);if(!old||old.hash!==q.hash||old.receipt!==q.receipt)throw Error('receipt changed');
  s.sql.exec('INSERT INTO anchor_rotation_history VALUES(?,?,?,?,?)',n+1,body,oldSignature,newSignature,nextReceipt);
  s.sql.exec('UPDATE anchor_receipts SET receipt=? WHERE sequence=?',nextReceipt,q.sequence);
  s.sql.exec('UPDATE anchor_authority SET anchor_key_id=?,anchor_jwk=?,receipt=?,clock=? WHERE id=1',newId,JSON.stringify(pub),nextReceipt,now);
  return {sequence:q.sequence,hash:q.hash,key_id:newId};
 });
}
export async function verifyRotationHistoryFixture(s,{genesisKey,genesisId}){
 let pub=publicJwk(genesisKey),id=genesisId,lastSeq=0;
 const rows=s.sql.exec('SELECT * FROM anchor_rotation_history ORDER BY id').toArray();if(rows.length>100)throw Error('history invalid');
 for(let i=0;i<rows.length;i++){
  const row=rows[i];let p,prior,next;try{p=JSON.parse(row.transition);prior=JSON.parse(p.old_receipt);next=JSON.parse(row.new_receipt);}catch{throw Error('history invalid');}
  if(row.id!==i+1||p.v!==1||p.old_key_id!==id||JSON.stringify(p.old_jwk)!==JSON.stringify(pub)||p.sequence<lastSeq||p.sequence!==prior.payload.sequence||p.hash!==prior.payload.hash||p.old_key_id!==prior.payload.key_id||p.new_key_id!==next.payload.key_id||p.sequence!==next.payload.sequence||p.hash!==next.payload.hash||!await verified(pub,domain,row.transition,row.old_signature)||!await verified(publicJwk(p.new_jwk),domain,row.transition,row.new_signature)||!await verified(pub,'sko-decoy-anchor-v1',JSON.stringify(prior.payload),prior.signature)||!await verified(publicJwk(p.new_jwk),'sko-decoy-anchor-v1',JSON.stringify(next.payload),next.signature))throw Error('history rejected');
  pub=publicJwk(p.new_jwk);id=p.new_key_id;lastSeq=p.sequence;
 }
 const q=state(s);if(q.anchor_key_id!==id||q.anchor_jwk!==JSON.stringify(pub))throw Error('history head differs');await latestIndependentAnchor(s);return {key_id:id,rotations:rows.length};
}
