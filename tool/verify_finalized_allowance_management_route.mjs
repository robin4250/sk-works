// Disposable PostgreSQL only. Reuses actual explicit finalization and management
// installers; does not deploy SQL or read application records.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import {spawnSync} from 'node:child_process';
const folder=await mkdtemp(join(tmpdir(),'finalized-allowance-management-'));
try{
 const bootstrap=join(folder,'bootstrap.mjs');
 const root=resolve('docs/review/explicit-finalization-candidate');
 const emitted=spawnSync(process.execPath,[join(root,'verify_ordinary_explicit_finalization.mjs')],{stdio:'inherit',env:{...process.env,SKO_ORDINARY_EXPLICIT_EMIT_ONLY:bootstrap}});
 assert.equal(emitted.status,0,'Actual source-bound ordinary finalization installer emitted');
 const original=await readFile(bootstrap,'utf8');
 const marker=" phase='ordinary-highest-management-finalized-edit-delete-and-new';";
 assert.equal(original.split(marker).length,2);
 const unit=String.raw`
 phase='finalized-registered-allowance-removal-with-real-management-proof';
 const managedReportBefore=await q('select to_jsonb(r) v from daily_reports r where id=$1',[rid]);
 const managedWorkerBefore=await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2',[rid,reportWorker]);
 const managedPeerBefore=await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2',[rid,W2]);
 const managedReceiptBefore=await q('select to_jsonb(r) v from attendance_entries a join company_checkout_allowance_private.receipts r on r.id=a.company_allowance_receipt_id where a.source_report_id=$1 and a.worker_id=$2',[rid,reportWorker]);
 assert.ok(managedReceiptBefore.snapshot.items.length>0,'Actually finalized report has a registered company allowance');
 eq(await q("select exists(select 1 from explicit_report_finalization_private.events where report_id=$1 and kind='finalized') v",[rid]),true,'Actual finalization evidence exists');
 const finalEvents=await q('select jsonb_agg(to_jsonb(e) order by id) v from explicit_report_finalization_private.events e where report_id=$1',[rid]);
 const invoiceBeforeRemoval=await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]);
 const payrollDaysBeforeRemoval=await q("select detail->>'出勤日数' v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,reportWorker]);
 eq(await withManagementProof('upsert',[managementCell(reportWorker,docDay,{company_allowance_selections:choices([]),company_allowance_legacy_labels:''})]),1,'Real highest-management proof explicitly removes selected registered allowances');
 const managedReportAfter=await q('select to_jsonb(r) v from daily_reports r where id=$1',[rid]);
 eq(managedReportAfter.status,'draft','Managed correction requires fresh signatures');
 for(const key of ['representative_signature_json','representative_name','supervisor_signature_json','supervisor_name'])eq(managedReportAfter[key],null,'No reuse of old role signature: '+key);
 const managedWorkerAfter=await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2',[rid,reportWorker]);
 eq(managedWorkerAfter.company_allowance_selections,choices([]),'Only explicit authorized empty registered selection is saved');
 eq(managedWorkerAfter.company_allowance_legacy_labels,'','No obsolete name retained');
 eq(await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2',[rid,W2]),managedPeerBefore,'Unselected member source unchanged');
 eq(await q('select to_jsonb(r) v from company_checkout_allowance_private.receipts r where id=$1',[managedReceiptBefore.id]),managedReceiptBefore,'Original signed receipt preserved byte-identically');
 eq(await q("select exists(select 1 from attendance_admin_override_private.operations o where state='committed' and exists(select 1 from jsonb_array_elements(o.before_state->'reports') d where d->'report'=$1::jsonb and d->'roster' @> jsonb_build_array($2::jsonb))) v",[JSON.stringify(managedReportBefore),JSON.stringify(managedWorkerBefore)]),true,'Audit preserves original signed report and selected member');
 for(const event of finalEvents)eq(await q('select to_jsonb(e) v from explicit_report_finalization_private.events e where id=$1',[event.id]),event,'Original finalization event retained');
 const managedSourceReceipt=await q('select r.snapshot v from attendance_entries a join company_checkout_allowance_private.receipts r on r.id=a.company_allowance_receipt_id where a.source_report_id=$1 and a.worker_id=$2',[rid,reportWorker]);
 eq(managedSourceReceipt.authority.kind,'attendance_management','Empty selection has honest management authority');
 eq(managedSourceReceipt.authority.actor_id,managementUser,'Actual proof actor retained');
 eq(managedSourceReceipt.items,[],'Current normalized receipt explicitly records no registered allowance');
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1 and worker_id=$2',[rid,reportWorker]),1,'Removal does not delete attendance');
 eq(await q("select detail->>'出勤日数' v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,reportWorker]),payrollDaysBeforeRemoval,'Worked payroll days retained');
 eq(await q('select grand_total v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]),invoiceBeforeRemoval,'Invoice member-days not duplicated or removed');
 eq(await q('select count(*)::int v from attendance_admin_override_private.contexts'),0,'No reusable management context remains');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,finalized_approved_reset_rejected_atomically:true,actual_registered_allowance_removed_by_management_proof:true,original_report_roster_receipt_events_preserved:true,ordinary_and_no_proof_denied:true,production_changed:false}));
`;
 const generated=original.slice(0,original.indexOf(marker))+unit+original.slice(original.indexOf('}catch(error){'));
 const proof=join(folder,'proof.mjs');await writeFile(proof,generated);
 const syntax=spawnSync(process.execPath,['--check',proof],{stdio:'inherit'});assert.equal(syntax.status,0);
 if(process.env.SKO_FINALIZED_MANAGEMENT_EMIT_ONLY)await writeFile(process.env.SKO_FINALIZED_MANAGEMENT_EMIT_ONLY,generated);
 else{
 const result=spawnSync(process.execPath,[proof,process.argv[2]],{stdio:'inherit',env:{...process.env,SKO_DOCUMENT_CANDIDATE:resolve('docs/review/supervisor-document-candidate/document-signature-and-edit.sql.review-only'),SKO_DOCUMENT_TRIGGER_PINS:resolve('docs/review/supervisor-document-candidate/trigger-source-pins.json'),SKO_ADMIN_CANDIDATE:resolve('docs/review/attendance-admin-override-candidate/attendance-admin-override.sql.review-only'),SKO_ADMIN_ORIGINALS:resolve('docs/review/attendance-admin-override-candidate/native-original-sources.sql'),SKO_ORDINARY_EXPLICIT_ROOT:root}});
 if(result.error)throw result.error;process.exitCode=result.status??1;
 }
}finally{await rm(folder,{recursive:true,force:true});}
