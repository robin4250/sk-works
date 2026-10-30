// Internal request-scoped coordinator, not an Edge Function/public upload API.
// Caller owns a dedicated privileged DB connection with the original verified
// request claims already installed. Never use this on a shared connection pool
// without its existing per-request claim isolation.
import {spawn} from 'node:child_process';
import {realpath} from 'node:fs/promises';
import {isAbsolute,join} from 'node:path';

const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const maxPdf=20*1024*1024;
export async function createCanonicalSiteOrderRenderer({dartExecutable,repositoryRoot}) {
 if(!isAbsolute(dartExecutable)||!isAbsolute(repositoryRoot))throw Error('canonical_renderer_configuration');
 const dart=await realpath(dartExecutable),root=await realpath(repositoryRoot);
 const command=join(root,'tool/render_site_order_canonical.dart');
 const packages=join(root,'tool/canonical_renderer/.dart_tool/package_config.json');
 return evidence=>new Promise((resolve,reject)=>{
  const input=Buffer.from(JSON.stringify(evidence));
  if(input.length>2*1024*1024){reject(Error('canonical_evidence_too_large'));return;}
  const child=spawn(dart,[`--packages=${packages}`,command,root],{
   cwd:root,env:{LANG:'C.UTF-8'},stdio:['pipe','pipe','pipe']});
  let length=0,failed=false;const chunks=[];
  const fail=()=>{if(failed)return;failed=true;child.kill('SIGKILL');reject(Error('canonical_render_rejected'));};
  const timer=setTimeout(fail,30_000);
  child.on('error',fail);child.stdin.on('error',fail);
  // Diagnostics deliberately never forwarded: evidence can include private data.
  child.stderr.resume();
  child.stdout.on('data',part=>{length+=part.length;if(length>maxPdf){fail();return;}chunks.push(part);});
  child.on('close',code=>{
   clearTimeout(timer);if(failed)return;
   const bytes=Buffer.concat(chunks);
   if(code!==0||bytes.length<16||bytes.subarray(0,5).toString()!=='%PDF-') {fail();return;}
   resolve(bytes);
  });
  child.stdin.end(input);
 });
}

const managerJobLock=`select j.evidence from site_order_artifact_private.render_jobs j
 join site_order_manager_private.document_scopes s on s.document_id=j.document_id
  and s.company_id=j.company_id and s.site_id=j.site_id
  and s.trade_company_id=j.counterparty_trade_company_id
  and s.connection_fingerprint=j.counterparty_connection_fingerprint
 where j.id=$1 and j.actor_id=auth.uid() and j.session_id=(auth.jwt()->>'session_id')::uuid
 and exists(select 1 from public.company_members m where m.user_id=auth.uid()
  and m.company_id=j.company_id and m.role::text in('owner','admin','manager')) for update of j`;

export async function registerCanonicalSiteOrderJob(db,jobId,render) {
 return registerForPurpose(db,jobId,render,false);
}

// Internal route must select this fixed export only for the saved site registry.
// No public request may choose SQL, an authorizer or a registration function.
export async function registerManagerCanonicalSiteOrderJob(db,jobId,render) {
 return registerForPurpose(db,jobId,render,true);
}

async function registerForPurpose(db,jobId,render,manager) {
 if(!uuid.test(jobId))throw Error('canonical_job_id_required');
 // No transaction retries here. A COMMIT transport error is UNKNOWN; caller must
 // look up the same request/job, never mint a replacement job or resubmit bytes.
 let committed=false,commitStarted=false;
 await db.query('begin isolation level read committed');
 try {
  const role=(await db.query('select session_user as role')).rows[0]?.role;
  if(role!=='postgres')throw Error('canonical_internal_connection_required');
  await db.query('select trade_document_confirmation_api_private.actor()');
  if(manager)await db.query('select private.require_standalone_trade_document_access()');
  await db.query('select private.require_trade_documents_master_feature()');
  const j=(await db.query(manager?managerJobLock:`select j.evidence from site_order_artifact_private.render_jobs j
   where j.id=$1 and j.actor_id=auth.uid()
   and j.session_id=(auth.jwt()->>'session_id')::uuid for update of j`,[jobId])).rows[0];
  if(!j)throw Error('canonical_job_unavailable');
  if(manager)await db.query('select site_order_manager_private.require_actor(j.company_id,j.document_id) from site_order_artifact_private.render_jobs j where j.id=$1',[jobId]);
  // This MUST be a separate statement after acquiring the immutable job lock.
  // A joined READ COMMITTED snapshot can miss a first worker's pdf_records
  // insert after waiting, since that worker never updates the locked job row.
  const original=(await db.query('select pdf_bytes from site_order_artifact_private.pdf_records where job_id=$1',[jobId])).rows[0]?.pdf_bytes;
  // Replays reuse immutable original bytes. A fresh PDF timestamp must never
  // replace an already registered original or cause an avoidable retry failure.
  const bytes=original??await render(j.evidence);
  const receipt=(await db.query(manager?'select site_order_manager_private.register_canonical_pdf($1,$2) as receipt':'select site_order_artifact_private.register_canonical_pdf($1,$2) as receipt',[jobId,bytes])).rows[0]?.receipt;
  if(!receipt||receipt.job_id!==jobId||receipt.pdf_byte_length!==bytes.length)throw Error('canonical_receipt_mismatch');
  commitStarted=true;
  await db.query('commit');committed=true;
  return receipt;
 } catch {
  if(!commitStarted)await db.query('rollback').catch(()=>{});
  // Retain only the fixed classification, never a raw SQL/render cause.
  throw Error(commitStarted&&!committed?'canonical_commit_result_unknown':'canonical_registration_rejected');
 }
}
