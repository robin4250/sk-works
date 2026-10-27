// Isolated adapter: no network, production secrets, DB access or source unpin.
// Signer input must come from a separately authenticated source verifier; a
// signature alone does not prove the supplied source snapshot is genuine.
import {ZERO,exact,hash,publicJwk,verified} from './security-audit.mjs';
const id=x=>typeof x==='string'&&/^[A-Za-z0-9_-]{1,64}$/.test(x);
const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(x);
const digest=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const one=(s,q,...a)=>s.sql.exec(q,...a).toArray()[0];
const te=new TextEncoder();
function state(s){const v=one(s,'SELECT * FROM notice_archive_state WHERE id=1');if(!v)throw Error('Archive unavailable');return v;}
export function initializeNoticeArchive(s,c){
 if(!exact(c,'anchorJwk,anchorKeyId,auditJwk,auditKeyId,companyId,deploymentId,ownerId,retentionMs')||
  ![c.anchorKeyId,c.auditKeyId,c.companyId,c.deploymentId,c.ownerId].every(id)||
  !Number.isSafeInteger(c.retentionMs)||c.retentionMs<7*86400000)throw Error('Archive trust rejected');
 const a=publicJwk(c.auditJwk),b=publicJwk(c.anchorJwk);
 if(a.x===b.x||c.auditKeyId===c.anchorKeyId)throw Error('Independent archive keys required');
 return s.transactionSync(()=>{
  s.sql.exec('CREATE TABLE IF NOT EXISTS notice_archive_state(id INTEGER PRIMARY KEY CHECK(id=1),deployment_id TEXT NOT NULL,company_id TEXT NOT NULL,owner_id TEXT NOT NULL,audit_key_id TEXT NOT NULL,audit_jwk TEXT NOT NULL,anchor_key_id TEXT NOT NULL,anchor_jwk TEXT NOT NULL,retention_ms INTEGER NOT NULL,batch_sequence INTEGER NOT NULL,manifest_hash TEXT NOT NULL,anchor_sequence INTEGER NOT NULL,anchor_hash TEXT NOT NULL)');
  s.sql.exec('CREATE TABLE IF NOT EXISTS notice_archive_batches(sequence INTEGER PRIMARY KEY,manifest_hash TEXT NOT NULL,manifest TEXT NOT NULL,audit TEXT NOT NULL,anchor TEXT NOT NULL)');
  const old=one(s,'SELECT * FROM notice_archive_state WHERE id=1');
  if(old){if(old.deployment_id!==c.deploymentId||old.company_id!==c.companyId||old.owner_id!==c.ownerId||old.audit_key_id!==c.auditKeyId||old.audit_jwk!==JSON.stringify(a)||old.anchor_key_id!==c.anchorKeyId||old.anchor_jwk!==JSON.stringify(b)||old.retention_ms!==c.retentionMs)throw Error('Existing archive trust differs');return {batch_sequence:old.batch_sequence,manifest_hash:old.manifest_hash};}
  s.sql.exec('INSERT INTO notice_archive_state VALUES(1,?,?,?,?,?,?,?,?,0,?,0,?)',c.deploymentId,c.companyId,c.ownerId,c.auditKeyId,JSON.stringify(a),c.anchorKeyId,JSON.stringify(b),c.retentionMs,ZERO,ZERO);
  return {batch_sequence:0,manifest_hash:ZERO};
 });
}
function canonicalManifest(q,m,now){
 if(!exact(m,'archived_at,batch_sequence,company_id,deployment_id,events,previous_hash,v')||m.v!==1||m.deployment_id!==q.deployment_id||m.company_id!==q.company_id||!Number.isSafeInteger(m.batch_sequence)||m.batch_sequence<1||!digest(m.previous_hash)||!Number.isSafeInteger(now)||!Number.isSafeInteger(m.archived_at)||m.archived_at>now||m.archived_at<0||!Array.isArray(m.events)||m.events.length<1||m.events.length>100)throw Error('Archive manifest rejected');
 let previous='';const events=[];
 for(const e of m.events){
  if(!exact(e,'event_id,event_kind,evidence_digest,generation,history,occurred_at,review_state,reviewed_at')||!uuid(e.event_id)||e.event_id<=previous||!['current_lure_touched','retired_lure_touched'].includes(e.event_kind)||!digest(e.evidence_digest)||!Number.isInteger(e.generation)||e.generation<1||e.generation>1000000||!Number.isSafeInteger(e.occurred_at)||e.occurred_at<0||e.occurred_at>e.reviewed_at||!Number.isSafeInteger(e.reviewed_at)||e.reviewed_at>m.archived_at-q.retention_ms||!['resolved','false_positive'].includes(e.review_state)||!Array.isArray(e.history)||e.history.length<1||e.history.length>20)throw Error('Archive event rejected');
  previous=e.event_id;let last=-1;const history=[];
  for(const h of e.history){
   if(!exact(h,'action,actor_id,occurred_at,reason')||!['read','investigating','false_positive','resolved'].includes(h.action)||h.actor_id!==q.owner_id||!Number.isSafeInteger(h.occurred_at)||h.occurred_at<last||h.occurred_at>e.reviewed_at||typeof h.reason!=='string'||h.reason.length>500||(h.action==='read'&&h.reason!=='')||(h.action!=='read'&&!h.reason.trim()))throw Error('Archive history rejected');
   last=h.occurred_at;history.push({action:h.action,actor_id:h.actor_id,occurred_at:h.occurred_at,reason:h.reason});
  }
  if(history.at(-1).action!==e.review_state||history.at(-1).occurred_at!==e.reviewed_at)throw Error('Archive review mismatch');
  events.push({event_id:e.event_id,event_kind:e.event_kind,evidence_digest:e.evidence_digest,generation:e.generation,occurred_at:e.occurred_at,review_state:e.review_state,reviewed_at:e.reviewed_at,history});
 }
 const body=JSON.stringify({v:1,deployment_id:m.deployment_id,company_id:m.company_id,batch_sequence:m.batch_sequence,previous_hash:m.previous_hash,archived_at:m.archived_at,events});
 if(te.encode(body).length>200000)throw Error('Archive byte limit');return body;
}
async function verifyEvidence(q,manifestBody,audit,anchor,now){
 if(!exact(audit,'body,hash,key_id,occurred_at,previous_hash,sequence,signature')||typeof audit.body!=='string'||te.encode(audit.body).length>4096||!digest(audit.hash)||audit.key_id!==q.audit_key_id||!Number.isSafeInteger(audit.sequence)||audit.sequence<1||!Number.isSafeInteger(audit.occurred_at)||audit.occurred_at>now||!digest(audit.previous_hash)||await hash(audit.body)!==audit.hash||!await verified(JSON.parse(q.audit_jwk),'sko-decoy-audit-v1',audit.body,audit.signature))throw Error('Signed archive audit rejected');
 let b;try{b=JSON.parse(audit.body);}catch{throw Error('Signed archive audit rejected');}
 const mh=await hash(manifestBody),m=JSON.parse(manifestBody);
 if(!exact(b,'action,actor_id,after,before,company_id,deployment_id,kind,occurred_at,previous_hash,reason,sequence,v')||b.v!==1||b.deployment_id!==q.deployment_id||b.company_id!==q.company_id||b.actor_id!=='system_retention'||b.kind!=='retention'||b.action!=='archive_notice_batch'||b.sequence!==audit.sequence||b.previous_hash!==audit.previous_hash||b.occurred_at!==audit.occurred_at||!exact(b.after,'batch_sequence,event_count,manifest_sha256')||b.after.manifest_sha256!==mh||b.after.batch_sequence!==m.batch_sequence||b.after.event_count!==m.events.length)throw Error('Archive binding rejected');
 if(!exact(anchor,'payload,signature')||!exact(anchor.payload,'deployment_id,hash,issued_at,key_id,sequence,v'))throw Error('Independent anchor rejected');
 const p=anchor.payload,body=JSON.stringify({v:1,deployment_id:p.deployment_id,sequence:p.sequence,hash:p.hash,issued_at:p.issued_at,key_id:p.key_id});
 if(p.v!==1||p.deployment_id!==q.deployment_id||p.key_id!==q.anchor_key_id||p.sequence!==audit.sequence||p.hash!==audit.hash||!Number.isSafeInteger(p.issued_at)||p.issued_at<audit.occurred_at||p.issued_at>now||!await verified(JSON.parse(q.anchor_jwk),'sko-decoy-anchor-v1',body,anchor.signature))throw Error('Independent anchor rejected');
 return {manifestHash:mh,anchorSequence:p.sequence,anchorHash:p.hash};
}
async function verifyStoredChain(s,q,now){
 const rows=s.sql.exec('SELECT * FROM notice_archive_batches ORDER BY sequence').toArray();
 if(rows.length!==q.batch_sequence||rows.length>1000)throw Error('Archive sequence missing');
 let previous=ZERO,anchorSequence=0,anchorHash=ZERO;
 for(let i=0;i<rows.length;i++){
  const row=rows[i];let manifest,audit,anchor;
  try{manifest=JSON.parse(row.manifest);audit=JSON.parse(row.audit);anchor=JSON.parse(row.anchor);}catch{throw Error('Archive stored data rejected');}
  const body=canonicalManifest(q,manifest,now),proof=await verifyEvidence(q,body,audit,anchor,now);
  if(row.sequence!==i+1||manifest.batch_sequence!==row.sequence||manifest.previous_hash!==previous||body!==row.manifest||proof.manifestHash!==row.manifest_hash||proof.anchorSequence<=anchorSequence)throw Error('Archive stored chain rejected');
  previous=proof.manifestHash;anchorSequence=proof.anchorSequence;anchorHash=proof.anchorHash;
 }
 if(previous!==q.manifest_hash||anchorSequence!==q.anchor_sequence||anchorHash!==q.anchor_hash)throw Error('Archive stored head differs');
}
// caller supplies the latest receipt fetched from a genuinely independent
// authority. A caller-provided old receipt cannot prove global freshness.
export async function storeNoticeArchive(s,{manifest,audit,anchor,latestIndependentAnchor,now}){
 const q=state(s),body=canonicalManifest(q,manifest,now),proof=await verifyEvidence(q,body,audit,anchor,now);
 await verifyStoredChain(s,q,now);
 if(JSON.stringify(anchor)!==JSON.stringify(latestIndependentAnchor))throw Error('Latest independent anchor required');
 return s.transactionSync(()=>{
  const current=state(s);const old=one(s,'SELECT * FROM notice_archive_batches WHERE sequence=?',manifest.batch_sequence);
  if(old){if(old.manifest_hash!==proof.manifestHash||old.manifest!==body||old.audit!==JSON.stringify(audit)||old.anchor!==JSON.stringify(anchor)||current.batch_sequence!==manifest.batch_sequence||current.manifest_hash!==proof.manifestHash)throw Error('Archive retry conflict');return {batch_sequence:manifest.batch_sequence,manifest_hash:proof.manifestHash,replayed:true};}
  if(current.batch_sequence!==q.batch_sequence||current.manifest_hash!==q.manifest_hash||manifest.batch_sequence!==q.batch_sequence+1||manifest.previous_hash!==q.manifest_hash||proof.anchorSequence<=q.anchor_sequence||one(s,'SELECT count(*) AS n FROM notice_archive_batches').n>=1000||one(s,'SELECT coalesce(sum(length(cast(manifest as blob))+length(cast(audit as blob))+length(cast(anchor as blob))),0) AS n FROM notice_archive_batches').n+te.encode(body).length+te.encode(JSON.stringify(audit)).length+te.encode(JSON.stringify(anchor)).length>16*1024*1024)throw Error('Archive monotonic capacity rejected');
  s.sql.exec('INSERT INTO notice_archive_batches VALUES(?,?,?,?,?)',manifest.batch_sequence,proof.manifestHash,body,JSON.stringify(audit),JSON.stringify(anchor));
  s.sql.exec('UPDATE notice_archive_state SET batch_sequence=?,manifest_hash=?,anchor_sequence=?,anchor_hash=? WHERE id=1',manifest.batch_sequence,proof.manifestHash,proof.anchorSequence,proof.anchorHash);
  return {batch_sequence:manifest.batch_sequence,manifest_hash:proof.manifestHash,replayed:false};
 });
}
// Review-only strict entry point. The archive requires every signed audit row
// since its own last checkpoint, including non-archive events. This is not a
// freshness proof: the trusted authority and independent witness must supply an
// authenticated current head and retained rows. The older entry point remains
// for fixture compatibility and MUST NOT be used as a production entry point.
export async function storeNoticeArchiveWithContinuity(s,input){
 const q=state(s), rows=input.auditExtension;
 if(!Array.isArray(rows)||rows.length>100||te.encode(JSON.stringify(rows)).length>450000)throw Error('Audit extension bound');
 // Exact latest-batch retry uses the existing immutable comparison in store.
 if(rows.length===0){
  if(input.audit?.sequence!==q.anchor_sequence||input.audit?.hash!==q.anchor_hash)throw Error('Audit extension required');
 }else{
  let sequence=q.anchor_sequence,previous=q.anchor_hash,lastTime=-1;
  if(q.batch_sequence>0){
   const lastStored=one(s,'SELECT audit FROM notice_archive_batches WHERE sequence=?',q.batch_sequence);
   try{lastTime=JSON.parse(lastStored.audit).occurred_at;}catch{throw Error('Archive checkpoint unavailable');}
   if(!Number.isSafeInteger(lastTime))throw Error('Archive checkpoint unavailable');
  }
  for(const row of rows){
   if(!exact(row,'body,hash,key_id,occurred_at,previous_hash,sequence,signature')||
    !Number.isSafeInteger(row.sequence)||row.sequence!==sequence+1||row.previous_hash!==previous||
    row.key_id!==q.audit_key_id||typeof row.body!=='string'||te.encode(row.body).length>4096||
    !digest(row.hash)||await hash(row.body)!==row.hash||
    !await verified(JSON.parse(q.audit_jwk),'sko-decoy-audit-v1',row.body,row.signature))throw Error('Audit extension rejected');
   let b;try{b=JSON.parse(row.body);}catch{throw Error('Audit extension rejected');}
   if(!exact(b,'action,actor_id,after,before,company_id,deployment_id,kind,occurred_at,previous_hash,reason,sequence,v')||
    b.v!==1||b.deployment_id!==q.deployment_id||b.company_id!==q.company_id||b.sequence!==row.sequence||
    b.previous_hash!==previous||b.occurred_at!==row.occurred_at||!Number.isSafeInteger(row.occurred_at)||
    row.occurred_at<0||row.occurred_at>input.now||row.occurred_at<lastTime||
    !['management','recovery','retention'].includes(b.kind)||
    (b.kind==='retention'?b.actor_id!=='system_retention':b.actor_id!==q.owner_id))throw Error('Audit extension binding rejected');
   sequence=row.sequence;previous=row.hash;lastTime=row.occurred_at;
  }
  const last=rows.at(-1), a=input.audit;
  if(!a||['body','hash','key_id','occurred_at','previous_hash','sequence','signature'].some(k=>last[k]!==a[k]))throw Error('Audit extension head differs');
 }
 const current=state(s);
 if(current.batch_sequence!==q.batch_sequence||current.manifest_hash!==q.manifest_hash||current.anchor_sequence!==q.anchor_sequence||current.anchor_hash!==q.anchor_hash)throw Error('Archive changed; retry');
 return storeNoticeArchive(s,input);
}
export async function readNoticeArchive(s,{batchSequence,latestIndependentAnchor,now}){
 const q=state(s);await verifyStoredChain(s,q,now);const row=one(s,'SELECT * FROM notice_archive_batches WHERE sequence=?',batchSequence);if(!row)throw Error('Archive batch unavailable');
 // This initial candidate requires the independent stream to have exactly the
 // same head as the local archive. An unrelated/newer head deliberately holds.
 if(!latestIndependentAnchor||latestIndependentAnchor.payload?.sequence!==q.anchor_sequence||latestIndependentAnchor.payload?.hash!==q.anchor_hash)throw Error('Archive head mismatch');
 const m=JSON.parse(row.manifest),audit=JSON.parse(row.audit),anchor=JSON.parse(row.anchor),body=canonicalManifest(q,m,now),p=await verifyEvidence(q,body,audit,anchor,now);
 if(body!==row.manifest||p.manifestHash!==row.manifest_hash)throw Error('Archive contents differ');
 const latest=one(s,'SELECT * FROM notice_archive_batches WHERE sequence=?',q.batch_sequence);
 if(!latest||latest.manifest_hash!==q.manifest_hash||JSON.stringify(JSON.parse(latest.anchor))!==JSON.stringify(latestIndependentAnchor))throw Error('Archive state rollback');
 const current=state(s);if(current.batch_sequence!==q.batch_sequence||current.manifest_hash!==q.manifest_hash||current.anchor_sequence!==q.anchor_sequence||current.anchor_hash!==q.anchor_hash)throw Error('Archive changed; retry');
 return m;
}
