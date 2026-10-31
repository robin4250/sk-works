// Fixed owner-connection purpose queries. No public table grants or caller SQL.
export const outgoingExecutionKeys=['site_id','document_id','local_id','trade_id','request_id','preview_id','decision_id'];
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
export function outgoingExecutionArgs(identity){
 if(!identity||typeof identity!=='object'||Array.isArray(identity)
 ||Object.keys(identity).length!==outgoingExecutionKeys.length
 ||!Object.keys(identity).every(k=>outgoingExecutionKeys.includes(k))
 ||!outgoingExecutionKeys.every(k=>typeof identity[k]==='string'&&uuid.test(identity[k])))throw Error('outgoing_execution_identity_required');
 return outgoingExecutionKeys.map(k=>identity[k]);
}
export async function resolveOutgoingExecution(db,identity,{mutation=false}={}){
 const args=outgoingExecutionArgs(identity);
 const actor=mutation?'private.require_standalone_trade_document_access()':'site_order_package_private.read_actor()';
 const sql=`with actor as materialized(select ${actor} as a)
 select o.id operation_id,o.company_id,o.actor_id,o.session_id,o.request_id prepare_request_id,
 o.site_id,o.document_id,o.local_document_id,o.trade_company_id,o.counterparty_company_id,
 o.connection_fingerprint,o.body_sha256,o.source_sha256,o.seal_sha256,
 d.request_id decision_id,d.preview_id,d.job_id,d.render_hash,
 site_order_outgoing_private.decision_result(d) decision_result
 from actor a join site_order_outgoing_private.prepared_operations o
 on o.company_id=(a.a->>'company_id')::uuid and o.actor_id=auth.uid()
 join site_order_outgoing_private.decision_receipts d on d.operation_id=o.id
 join site_order_outgoing_private.preview_receipts p on p.id=d.preview_id
 where (o.site_id,o.document_id,o.local_document_id,o.trade_company_id,o.request_id,d.preview_id,d.request_id)
 =($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7::uuid)
 and(d.company_id,d.actor_id,d.session_id,d.body_hash)
 =(o.company_id,o.actor_id,o.session_id,o.body_sha256)
 and(p.operation_id,p.company_id,p.actor_id,p.session_id,p.body_hash,p.source_hash,p.seal_hash)
 =(o.id,o.company_id,o.actor_id,o.session_id,o.body_sha256,o.source_sha256,o.seal_sha256)
 ${mutation?"and o.session_id=(a.a->>'session_id')::uuid":''}`;
 const rows=(await db.query(sql,args)).rows;
 if(rows.length!==1||!rows[0].decision_result||rows[0].decision_result.job_id!==rows[0].job_id)throw Error('outgoing_execution_unavailable');
 return rows[0];
}

// Called only AFTER an existing own job has been locked and authorized.
// A missing result is never interpreted as proof of a legacy/non-owned job.
export async function isOutgoingOwnedJob(db,jobId){
 const present=(await db.query("select to_regclass('site_order_outgoing_private.prepared_operations') is not null as present")).rows[0]?.present;
 if(present===false)return false;
 if(present!==true)throw Error('outgoing_ownership_unobserved');
 const owned=(await db.query(`select exists(select 1 from site_order_outgoing_private.prepared_operations o
 join site_order_artifact_private.render_jobs j on j.document_id=o.document_id where j.id=$1) as owned`,[jobId])).rows[0]?.owned;
 if(typeof owned!=='boolean')throw Error('outgoing_ownership_unobserved');
 return owned;
}

// No operation advisory lock is acquired here. Existing registrar/send locks
// are job -> manager/pair; confirmation's pair -> op order must not be inverted.
export async function requireOutgoingExecutionSource(db,identity,jobId){
 const operation=await resolveOutgoingExecution(db,identity,{mutation:true});
 if(operation.job_id!==jobId)throw Error('outgoing_execution_job_changed');
 const current=(await db.query(`select site_order_outgoing_private.source_hash(context) source_hash,
 context#>>'{own_seal,seal_hash}' seal_hash
 from(select site_order_manager_private.outgoing_context($1,$2) context)s`,[operation.site_id,operation.trade_company_id])).rows[0];
 if(!current||current.source_hash!==operation.source_sha256||current.seal_hash!==operation.seal_sha256)throw Error('outgoing_execution_source_changed');
 const evidenceCurrent=(await db.query(`select j.evidence is not distinct from
  site_order_manager_private.render_approved(j.document_id,j.document_revision,j.company_id,false) as valid
  from site_order_artifact_private.render_jobs j where j.id=$1`,[jobId])).rows[0]?.valid;
 if(evidenceCurrent!==true)throw Error('outgoing_current_approval_changed');
 return operation;
}

// Legacy raw send/register cannot mutate a new outgoing-owned operation. The
// fixed new purpose derives all job/receipt/request/recipient IDs on the server.
export async function requireLegacyNonOutgoingJob(db,jobId){
 await db.query('select private.require_standalone_trade_document_access()');
 const row=(await db.query(`select j.id from site_order_artifact_private.render_jobs j
 where j.id=$1 and j.actor_id=auth.uid() and j.session_id=(auth.jwt()->>'session_id')::uuid
 and j.company_id=(private.require_standalone_trade_document_access()->>'company_id')::uuid for share of j`,[jobId])).rows[0];
 if(!row||row.id!==jobId||await isOutgoingOwnedJob(db,jobId))throw Error('outgoing_fixed_purpose_required');
}
