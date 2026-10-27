// Trusted internal adapter only. No HTTP route, deployment, secret discovery or
// management permission is provided by this independent-storage core.
import {ZERO,exact,publicJwk,hash,signBytes,verified} from './security-audit.mjs';
const one=(s,q,...a)=>s.sql.exec(q,...a).toArray()[0];
const ident=x=>typeof x==='string'&&/^[a-zA-Z0-9_-]{1,64}$/.test(x);
const digest=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
function state(s){const q=one(s,'SELECT * FROM anchor_authority WHERE id=1');if(!q)throw Error('Anchor authority unavailable');return q;}
export function initializeAnchorAuthority(s,c){
 if(!exact(c,'anchorJwk,anchorKeyId,auditJwk,auditKeyId,companyId,deploymentId,ownerId')||
  ![c.anchorKeyId,c.auditKeyId,c.companyId,c.deploymentId,c.ownerId].every(ident))throw Error('Anchor trust rejected');
 const audit=publicJwk(c.auditJwk),anchor=publicJwk(c.anchorJwk);
 if(audit.x===anchor.x||c.anchorKeyId===c.auditKeyId)throw Error('Independent anchor key required');
 return s.transactionSync(()=>{
  s.sql.exec('CREATE TABLE IF NOT EXISTS anchor_authority(id INTEGER PRIMARY KEY CHECK(id=1),deployment_id TEXT NOT NULL,company_id TEXT NOT NULL,owner_id TEXT NOT NULL,audit_key_id TEXT NOT NULL,audit_jwk TEXT NOT NULL,anchor_key_id TEXT NOT NULL,anchor_jwk TEXT NOT NULL,sequence INTEGER NOT NULL,hash TEXT NOT NULL,clock INTEGER NOT NULL,audit_clock INTEGER NOT NULL,receipt TEXT,audit_body TEXT,audit_signature TEXT)');
  s.sql.exec('CREATE TABLE IF NOT EXISTS anchor_receipts(sequence INTEGER PRIMARY KEY,hash TEXT NOT NULL,receipt TEXT NOT NULL)');
  const old=one(s,'SELECT * FROM anchor_authority WHERE id=1');
  if(old){if(old.deployment_id!==c.deploymentId||old.company_id!==c.companyId||old.owner_id!==c.ownerId||old.audit_key_id!==c.auditKeyId||old.audit_jwk!==JSON.stringify(audit)||old.anchor_key_id!==c.anchorKeyId||old.anchor_jwk!==JSON.stringify(anchor))throw Error('Existing anchor trust differs');return {sequence:old.sequence,hash:old.hash};}
  s.sql.exec('INSERT INTO anchor_authority VALUES(1,?,?,?,?,?,?,?,0,?,0,0,NULL,NULL,NULL)',c.deploymentId,c.companyId,c.ownerId,c.auditKeyId,JSON.stringify(audit),c.anchorKeyId,JSON.stringify(anchor),ZERO);
  return {sequence:0,hash:ZERO};
 });
}
async function validateReceipt(q,receipt){
 if(!exact(receipt,'payload,signature')||!exact(receipt.payload,'deployment_id,hash,issued_at,key_id,sequence,v'))throw Error('Saved anchor receipt rejected');
 const p=receipt.payload,body=JSON.stringify({v:1,deployment_id:p.deployment_id,sequence:p.sequence,hash:p.hash,issued_at:p.issued_at,key_id:p.key_id});
 if(p.v!==1||p.deployment_id!==q.deployment_id||p.key_id!==q.anchor_key_id||!Number.isSafeInteger(p.sequence)||p.sequence<1||!digest(p.hash)||!Number.isSafeInteger(p.issued_at)||!await verified(JSON.parse(q.anchor_jwk),'sko-decoy-anchor-v1',body,receipt.signature))throw Error('Saved anchor signature rejected');
 return p;
}
export async function latestIndependentAnchor(s){
 const q=state(s);if(q.sequence===0){if(q.hash!==ZERO||q.receipt!==null||q.clock!==0||q.audit_clock!==0||q.audit_body!==null||q.audit_signature!==null)throw Error('Anchor genesis rejected');return null;}
 const receipt=JSON.parse(q.receipt),p=await validateReceipt(q,receipt),row=one(s,'SELECT * FROM anchor_receipts WHERE sequence=?',q.sequence);
 if(!row||row.hash!==q.hash||row.receipt!==q.receipt||p.sequence!==q.sequence||p.hash!==q.hash||p.issued_at!==q.clock)throw Error('Anchor state differs');
 const audit=JSON.parse(q.audit_body);
 if(await hash(q.audit_body)!==q.hash||!await verified(JSON.parse(q.audit_jwk),'sko-decoy-audit-v1',q.audit_body,q.audit_signature)||audit.sequence!==q.sequence||audit.deployment_id!==q.deployment_id||audit.company_id!==q.company_id||!Number.isSafeInteger(q.audit_clock)||audit.occurred_at!==q.audit_clock)throw Error('Anchor audit clock differs');
 return receipt;
}
export async function preserveIndependentAnchor(s,{publication,now,anchorKey}){
 if(!Number.isSafeInteger(now)||now<0||!exact(publication,'expected_hash,expected_sequence,records')||!Number.isSafeInteger(publication.expected_sequence)||publication.expected_sequence<0||!digest(publication.expected_hash)||!Array.isArray(publication.records)||publication.records.length<1||publication.records.length>100||new TextEncoder().encode(JSON.stringify(publication)).length>450000)throw Error('Anchor publication bound');
 const q=state(s);await latestIndependentAnchor(s);
 if(now<q.clock)throw Error('Anchor clock regression');
 let sequence=publication.expected_sequence,previous=publication.expected_hash;
 const rows=publication.records;let lastOccurred=-1;
 for(const row of rows){
  if(!exact(row,'body,hash,key_id,occurred_at,previous_hash,sequence,signature')||!Number.isSafeInteger(row.sequence)||row.sequence!==++sequence||row.previous_hash!==previous||row.key_id!==q.audit_key_id||typeof row.body!=='string'||new TextEncoder().encode(row.body).length>4096||!digest(row.hash)||await hash(row.body)!==row.hash||!await verified(JSON.parse(q.audit_jwk),'sko-decoy-audit-v1',row.body,row.signature))throw Error('Anchor audit chain rejected');
  const b=JSON.parse(row.body);
  if(b.v!==1||b.deployment_id!==q.deployment_id||b.company_id!==q.company_id||b.sequence!==row.sequence||b.previous_hash!==previous||b.occurred_at!==row.occurred_at||!Number.isSafeInteger(row.occurred_at)||row.occurred_at<0||row.occurred_at>now+30000||!['management','recovery','retention'].includes(b.kind)||row.occurred_at<lastOccurred||(b.kind==='retention'?b.actor_id!=='system_retention':b.actor_id!==q.owner_id))throw Error('Anchor audit binding rejected');
  previous=row.hash;lastOccurred=row.occurred_at;
 }
 // A lost ACK can resend the same signed suffix. Verify it before consulting a
 // saved receipt; never issue a different receipt or advance clocks on retry.
 if(sequence===q.sequence&&previous===q.hash)return latestIndependentAnchor(s);
 if(rows[0].occurred_at<q.audit_clock)throw Error('Anchor audit clock regression');
 if(publication.expected_sequence!==q.sequence||publication.expected_hash!==q.hash||sequence<=q.sequence)throw Error('Anchor monotonic CAS rejected');
 const payload={v:1,deployment_id:q.deployment_id,sequence,hash:previous,issued_at:now,key_id:q.anchor_key_id},body=JSON.stringify(payload);
 const signature=await signBytes(anchorKey,'sko-decoy-anchor-v1',body);
 if(!await verified(JSON.parse(q.anchor_jwk),'sko-decoy-anchor-v1',body,signature))throw Error('Anchor private key differs');
 const receipt={payload,signature},encoded=JSON.stringify(receipt);
 return s.transactionSync(()=>{
  const current=state(s);if(current.sequence!==q.sequence||current.hash!==q.hash||current.clock!==q.clock||current.receipt!==q.receipt||current.audit_clock!==q.audit_clock||current.audit_body!==q.audit_body||current.audit_signature!==q.audit_signature)throw Error('Anchor concurrent CAS rejected');
  if(one(s,'SELECT count(*) AS n FROM anchor_receipts').n>=1000)throw Error('Anchor capacity unavailable');
  s.sql.exec('INSERT INTO anchor_receipts VALUES(?,?,?)',sequence,previous,encoded);
  s.sql.exec('UPDATE anchor_authority SET sequence=?,hash=?,clock=?,audit_clock=?,receipt=?,audit_body=?,audit_signature=? WHERE id=1',sequence,previous,now,lastOccurred,encoded,rows.at(-1).body,rows.at(-1).signature);
  return receipt;
 });
}
