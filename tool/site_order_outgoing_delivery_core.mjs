import {outgoingExecutionArgs,resolveOutgoingExecution,requireOutgoingExecutionSource} from './site_order_outgoing_execution_contract.mjs';
import {registerOutgoingCanonicalSiteOrderJob} from './site_order_canonical_core.mjs';

async function begin(db,claims){
 if(!claims)throw Error('outgoing_execution_rejected');
 await db.query('begin isolation level read committed');
 if((await db.query('select session_user as role')).rows[0]?.role!=='postgres')throw Error('outgoing_internal_connection_required');
 await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify(claims)]);
 await db.query("select set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim','',true)");
}
async function run(db,claims,work){
 let commitStarted=false;
 try{
  await begin(db,claims);
  const result=await work();
  commitStarted=true;await db.query('commit');return result;
 }catch{
  if(!commitStarted)await db.query('rollback').catch(()=>{});
  throw Error(commitStarted?'outgoing_commit_result_unknown':'outgoing_execution_rejected');
 }
}
const packageRows=`select id,sender_company_id,recipient_company_id,actor_id,session_id,request_id,
 source_job_id,original_receipt_id,data_item_id from site_order_package_private.packages where source_job_id=$1 order by id`;
function exactPackage(p,o,receipt){
 return p.sender_company_id===o.company_id&&p.recipient_company_id===o.counterparty_company_id&&p.actor_id===o.actor_id
 &&p.session_id===o.session_id&&p.request_id===o.prepare_request_id&&p.source_job_id===o.job_id&&p.original_receipt_id===receipt;
}
async function snapshot(db,o){
 const value=(await db.query(`select
 (select jsonb_build_object('receipt_id',r.receipt_id,'job_id',r.job_id,'pdf_sha256',r.pdf_sha256,'byte_length',octet_length(r.pdf_bytes))
  from site_order_artifact_private.pdf_records r where r.job_id=$1) original,
 coalesce((select jsonb_agg(to_jsonb(p)order by p.id) from(
 ${packageRows})p),'[]'::jsonb) packages`,[o.job_id])).rows[0];
 if(!value||!Array.isArray(value.packages))throw Error('outgoing_status_unobserved');
 const original=value.original;
 if(original&&(original.job_id!==o.job_id||typeof original.pdf_sha256!=='string'||!/^[a-f0-9]{64}$/.test(original.pdf_sha256)
 ||!Number.isInteger(original.byte_length)||original.byte_length<16||original.byte_length>20*1024*1024))throw Error('outgoing_original_unobserved');
 const packages=value.packages;
 const exact=original&&packages.length===1&&exactPackage(packages[0],o,original.receipt_id);
 const sharing=packages.length===0?'not_observed':exact?'recipient_stored':'unresolved';
 return {contract_version:1,operation_id:o.operation_id,company_id:o.company_id,site_id:o.site_id,document_id:o.document_id,
  local_document_id:o.local_document_id,trade_company_id:o.trade_company_id,request_id:o.prepare_request_id,
  preview_id:o.preview_id,decision_id:o.decision_id,job_id:o.job_id,body_hash:o.body_sha256,render_hash:o.render_hash,
  original_saved:Boolean(original),original_receipt_id:original?.receipt_id??null,pdf_sha256:original?.pdf_sha256??null,
  pdf_byte_length:original?.byte_length??null,sharing_state:sharing,package_id:exact?packages[0].id:null,
  recipient_company_id:o.counterparty_company_id,recipient_approval_state:'not_checked',device_push_confirmed:false,
  read_only:true,retry_automatically:false,journal_clearable:false};
}

export async function observeOutgoingExecution(db,identity,claims){
 outgoingExecutionArgs(identity);
 return run(db,claims,async()=>snapshot(db,await resolveOutgoingExecution(db,identity)));
}

export async function registerOutgoingOriginal(db,identity,render,claims){
 outgoingExecutionArgs(identity);
 // The shared registrar owns its own transaction and exact-byte replay. Never
 // nest it in the consent transaction or an outer caller transaction.
 const receipt=await registerOutgoingCanonicalSiteOrderJob(db,identity,render,claims);
 return {contract_version:1,identity:{...identity},original_saved:true,original_receipt:receipt,retry_automatically:false,journal_clearable:false};
}

export async function shareConfirmedOutgoing(db,identity,confirmed,claims){
 outgoingExecutionArgs(identity);
 if(confirmed!==true)throw Error('outgoing_explicit_share_confirmation_required');
 return run(db,claims,async()=>{
  const o=await resolveOutgoingExecution(db,identity,{mutation:true});
  // Same existing package key before the job lock. No operation lock is taken.
  await db.query(`select pg_advisory_xact_lock(hashtextextended('site-package:'||$1::uuid::text||':'||$2::uuid::text||':'||$3::uuid::text,0))`,
   [o.company_id,o.actor_id,o.prepare_request_id]);
  const own=(await db.query(`select j.id from site_order_artifact_private.render_jobs j where j.id=$1
   and j.company_id=$2 and j.actor_id=auth.uid() and j.session_id=(auth.jwt()->>'session_id')::uuid for update of j`,[o.job_id,o.company_id])).rows[0];
  if(!own||own.id!==o.job_id)throw Error('outgoing_own_job_required');
  // Fresh statements after waiting observe a previously committed original or
  // package. A legacy package with another nonce is never borrowed or repeated.
  const original=(await db.query('select receipt_id from site_order_artifact_private.pdf_records where job_id=$1',[o.job_id])).rows[0];
  if(!original)throw Error('outgoing_registered_original_required');
  const existing=(await db.query(packageRows,[o.job_id])).rows;
  if(existing.length>1||(existing.length===1&&!exactPackage(existing[0],o,original.receipt_id)))throw Error('outgoing_legacy_package_unresolved');
  await db.query('select site_order_manager_private.require_actor($1,$2)',[o.company_id,o.document_id]);
  await requireOutgoingExecutionSource(db,identity,o.job_id);
  const sent=(await db.query('select site_order_package_private.send_order($1,$2,$3) result',[o.job_id,original.receipt_id,o.prepare_request_id])).rows[0]?.result;
  if(!sent||typeof sent.package_id!=='string'||sent.sender_company_id!==o.company_id
   ||sent.recipient_company_id!==o.counterparty_company_id||sent.status!=='received')throw Error('outgoing_share_receipt_unobserved');
  const notifications=(await db.query('select site_order_package_private.dispatch_notifications($1) result',[sent.package_id])).rows[0]?.result;
  if(!notifications||notifications.package_id!==sent.package_id||notifications.device_push_confirmed!==false)throw Error('outgoing_notification_result_unobserved');
  await requireOutgoingExecutionSource(db,identity,o.job_id);
  const result=await snapshot(db,o);
  if(result.package_id!==sent.package_id||result.sharing_state!=='recipient_stored')throw Error('outgoing_share_result_unobserved');
  return {...result,read_only:false,notifications};
 });
}

export async function reviewOutgoingOriginal(db,identity,claims,{bytes=false}={}){
 outgoingExecutionArgs(identity);
 return run(db,claims,async()=>{
  const o=await resolveOutgoingExecution(db,identity);
  const status=await snapshot(db,o);
  if(!status.original_saved)throw Error('outgoing_original_unavailable');
  const row=(await db.query(`select r.pdf_bytes,j.evidence,
   j.session_id=(auth.jwt()->>'session_id')::uuid same_session
   from site_order_artifact_private.pdf_records r
   join site_order_artifact_private.render_jobs j on j.id=r.job_id
   where r.job_id=$1 and r.receipt_id=$2`,[o.job_id,status.original_receipt_id])).rows[0];
  if(!row||typeof row.same_session!=='boolean'||!row.evidence||typeof row.evidence!=='object')throw Error('outgoing_original_unavailable');
  const pdf=new Uint8Array(row.pdf_bytes);
  if(pdf.byteLength!==status.pdf_byte_length||pdf.byteLength>20*1024*1024
   ||new TextDecoder().decode(pdf.subarray(0,5))!=='%PDF-')throw Error('outgoing_original_bytes_changed');
  const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',pdf)),byte=>byte.toString(16).padStart(2,'0')).join('');
  if(digest!==status.pdf_sha256)throw Error('outgoing_original_bytes_changed');
  if(bytes)return pdf;
  // The approved job snapshot is authoritative, even if company fields or rates
  // have since changed. This read does not render, consent, register or share.
  return {contract_version:1,purpose:'persisted_original_review',read_only:true,
   same_session:row.same_session,status,evidence:row.evidence};
 });
}
