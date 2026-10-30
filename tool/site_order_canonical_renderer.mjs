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

export async function registerCanonicalSiteOrderJob(db,jobId,render) {
 if(!uuid.test(jobId))throw Error('canonical_job_id_required');
 // No transaction retries here. A COMMIT transport error is UNKNOWN; caller must
 // look up the same request/job, never mint a replacement job or resubmit bytes.
 let committed=false,commitStarted=false;
 await db.query('begin');
 try {
  const role=(await db.query('select session_user as role')).rows[0]?.role;
  if(role!=='postgres')throw Error('canonical_internal_connection_required');
  await db.query('select trade_document_confirmation_api_private.actor()');
  await db.query('select private.require_trade_documents_master_feature()');
  const j=(await db.query(`select j.evidence,r.pdf_bytes from site_order_artifact_private.render_jobs j
   left join site_order_artifact_private.pdf_records r on r.job_id=j.id where j.id=$1 and j.actor_id=auth.uid()
   and j.session_id=(auth.jwt()->>'session_id')::uuid for update of j`,[jobId])).rows[0];
  if(!j)throw Error('canonical_job_unavailable');
  // Replays reuse immutable original bytes. A fresh PDF timestamp must never
  // replace an already registered original or cause an avoidable retry failure.
  const bytes=j.pdf_bytes??await render(j.evidence);
  const receipt=(await db.query('select site_order_artifact_private.register_canonical_pdf($1,$2) as receipt',[jobId,bytes])).rows[0]?.receipt;
  if(!receipt||receipt.job_id!==jobId||receipt.pdf_byte_length!==bytes.length)throw Error('canonical_receipt_mismatch');
  commitStarted=true;
  await db.query('commit');committed=true;
  return receipt;
 } catch(error) {
  if(!commitStarted)await db.query('rollback').catch(()=>{});
  throw Error(commitStarted&&!committed?'canonical_commit_result_unknown':'canonical_registration_rejected',{cause:error});
 }
}
