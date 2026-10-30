// Native PostgreSQL17 only. Extends the existing real save/sign/receipt chain;
// authentication, tax and permission surroundings remain declared fixtures.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const base=await readFile('tool/verify_shared_approved_edit.mjs','utf8');
const marker=' const approvedRequest=id(8600);';
assert.equal(base.split(marker).length,2);
const unit=String.raw`
 phase='unchanged-PC-approved-reset';
 const resetSource=JSON.parse(await readFile('docs/review/approved-edit-allowance-reset/deployed-source.json','utf8'));
 eq(resetSource.application_rows_read,false,'Only deployed function metadata was captured');
 await exec(resetSource.function.definition);
 for(const f of resetSource.history_functions)await exec(f.definition);
 await exec(resetSource.report_basis.definition);
 eq(await q("select md5(prosrc) v from pg_proc where oid='public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'::regprocedure"),resetSource.source_md5,'Exact current deployed writer body installed');
 const pcItem=id(8660),pcClock=id(8662),pcRequest=id(8664);
 await client.query("insert into company_common_allowance_private.items(id,company_id,payroll_type,section,unit,name,amount_yen) values($1,$2,'daily','earning','day','PC',3000)",[pcItem,A]);
 const pcChoice=choice('company_common',pcItem,'PC');
 const pcRows=JSON.stringify([worker(reportWorker,[pcChoice])]);
 await mkShift(8662,reportWorker,'2026-10-18');
 await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[U,id(80)]);
 const pcRid=await draft('2026-10-18',reportWorker,[pcChoice]);
 const pcFirst=await sharedCall(U,id(80),'select public.read_my_shared_daily_report($1) v',[pcClock]);
 const pcReporter=await sharedCall(U,id(80),'select public.submit_shared_daily_report($1,$6::timestamptz,$2,$3::jsonb,$4,$5::jsonb,$7) v',
  [pcClock,'合成作業',pcRows,'合成報告者',signature,pcFirst.report_updated_at,pcFirst.signature_scope_fingerprint]);
 eq(pcReporter.report_id,pcRid,'PC work report is the exact source-linked report');
 await client.query('insert into checkout_shared_hours_private.fixture_confirmations values($1,$2,$3)',[pcRid,reportWorker,U]);
 const pcBeforeSupervisor=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[pcRid]);
 await sharedCall(U,id(80),'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',
  [pcRid,pcClock,'合成責任者',signature,pcBeforeSupervisor.report_updated_at,pcBeforeSupervisor.signature_scope_fingerprint]);
 const pcReportBefore=await q('select to_jsonb(r) v from daily_reports r where id=$1',[pcRid]);
 const pcRosterBefore=await q('select jsonb_agg(to_jsonb(w) order by worker_id) v from daily_report_workers w where report_id=$1',[pcRid]);
 const pcReceiptsBefore=await q('select jsonb_agg(to_jsonb(r) order by id) v from company_checkout_allowance_private.receipts r where report_id=$1',[pcRid]);
 eq(pcReportBefore.status,'signed','Unchanged PC baseline is fully signed');
 assert.ok(pcReportBefore.representative_signature_json&&pcReportBefore.supervisor_signature_json);
 const pcSave=()=>sharedCall(U,id(80),"select public.save_daily_report_destination_draft($1,$2,null,'2026-10-18','合成作業',$3::jsonb) v",[pcRid,SITE,pcRows]);
 await reject(pcSave,/approved edit request/);
 eq(await q('select to_jsonb(r) v from daily_reports r where id=$1',[pcRid]),pcReportBefore,'Missing approval changes no signed data');
 await client.query("insert into public.daily_report_edit_requests(id,report_id,company_id,requested_by,status) values($1,$2,$3,$4,'approved')",[pcRequest,pcRid,A,U]);
 await reject(()=>sharedCall(memberB,sidB,"select public.save_daily_report_destination_draft($1,$2,null,'2026-10-18','合成作業',$3::jsonb) v",[pcRid,SITE,pcRows]),/approved edit request|actor|member/);
 eq(await q('select status v from daily_report_edit_requests where id=$1',[pcRequest]),'approved','Foreign actor cannot consume the approval');
 // Savepoint makes the old broken attempt observable without retaining its
 // draft/signature inconsistency in the rest of the disposable proof.
 await exec('begin;savepoint old_unchanged_pc');
 await pcSave();
 const oldPc=await q('select to_jsonb(r) v from daily_reports r where id=$1',[pcRid]);
 eq(oldPc.status,'draft','Old writer consumes approval and changes status');
 eq(oldPc.representative_signature_json,pcReportBefore.representative_signature_json,'RED: old writer incorrectly retains reporter signature on unchanged PC');
 eq(oldPc.supervisor_signature_json,pcReportBefore.supervisor_signature_json,'RED: old writer incorrectly retains supervisor signature on unchanged PC');
 await exec('rollback to old_unchanged_pc;commit');
 eq(await q('select status v from daily_report_edit_requests where id=$1',[pcRequest]),'approved','Old attempt rolled back including consumed request');
 await exec(await readFile('docs/review/approved-edit-allowance-reset/approved-edit-allowance-reset.sql.review-only','utf8'));
 const fixedAttrs=await q("select to_jsonb(p)-'prosrc' v from pg_proc p where oid='public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'::regprocedure");
 await pcSave();
 const fixedPc=await q('select to_jsonb(r) v from daily_reports r where id=$1',[pcRid]);
 eq(fixedPc.status,'draft','Approved PC reset reaches editable draft');
 for(const field of ['representative_signature_json','representative_signer_name','supervisor_signature_json','supervisor_signer_name'])eq(fixedPc[field],null,'GREEN: approved reset clears only obsolete current role field '+field);
 eq(await q('select status v from daily_report_edit_requests where id=$1',[pcRequest]),'used','Exact approved request consumed once');
 const pcSession=await q('select to_jsonb(s) v from shared_report_edit_private.sessions s where report_id=$1',[pcRid]);
 eq(pcSession.state,'active','Existing authorized edit-session proof is active');
 eq(pcSession.old_report,pcReportBefore,'Original signed report preserved byte-for-byte in existing history');
 eq(pcSession.old_roster,pcRosterBefore,'Original PC roster preserved byte-for-byte in existing history');
 assert.ok(pcSession.old_annex,'Existing annex history is retained');
 eq(await q('select jsonb_agg(to_jsonb(r) order by id) v from company_checkout_allowance_private.receipts r where report_id=$1',[pcRid]),pcReceiptsBefore,'Unchanged original PC receipt is preserved');
 const otherSid=id(8668);await client.query('insert into auth.sessions(id,user_id) values($1,$2)',[otherSid,U]);
 await reject(()=>sharedCall(U,otherSid,"select public.save_daily_report_destination_draft($1,$2,null,'2026-10-18','合成作業',$3::jsonb) v",[pcRid,SITE,pcRows]),/exact_actor_session_required|reset_proof|exact_session/);
 await pcSave();
 eq(await q('select to_jsonb(s) v from shared_report_edit_private.sessions s where report_id=$1',[pcRid]),pcSession,'Retry cannot consume another request or replace the old signature history');
 eq(await q("select to_jsonb(p)-'prosrc' v from pg_proc p where oid='public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'::regprocedure"),fixedAttrs,'Ownership grants and security attributes remain unchanged');
 for(const f of resetSource.history_functions)eq(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',
  [f.schema_name+'.'+f.proname+'('+f.identity_arguments.split(',').map(x=>x.trim().split(' ').slice(1).join(' ')).join(',')+')']),
  md5(dbBody(f.definition)),'Exact deployed history capture/reset guard is unchanged');
 // Legacy non-protocol draft: ordinary unchanged PC saves still retain an
 // already collected reporter signature. The patch is NOT a global clear.
 await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[U,id(80)]);
 const ordinaryPc=await draft('2026-10-17',reportWorker,[pcChoice]);
 await client.query("update daily_reports set created_at=(select new_report_from-interval '1 day' from shared_daily_report_private.rollout where company_id=$2) where id=$1",[ordinaryPc,A]);
 await sharedCall(U,id(80),"select public.save_daily_report_signature($1,'representative','合成通常報告者',$2::jsonb) v",[ordinaryPc,signature]);
 const ordinarySig=await q('select representative_signature_json v from daily_reports where id=$1',[ordinaryPc]);
 await draft('2026-10-17',reportWorker,[pcChoice],{reportId:ordinaryPc});
 eq(await q('select representative_signature_json v from daily_reports where id=$1',[ordinaryPc]),ordinarySig,'Ordinary unchanged PC draft preserves its signature');
 console.log(JSON.stringify({pass:true,unchanged_PC_old_retained_signatures_reproduced:true,approved_reset_current_roles_cleared:true,original_report_roster_annex_and_receipts_preserved:true,ordinary_draft_preserved:true,production_changed:false}));
`;
const folder=await mkdtemp(join(tmpdir(),'approved-pc-reset-proof-'));
try {
 const file=join(folder,'proof.mjs');await writeFile(file,base.replace(marker,()=>unit+marker));
 const result=spawnSync(process.execPath,[file,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
} finally {await rm(folder,{recursive:true,force:true});}
