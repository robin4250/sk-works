// Isolated actual v2 epoch carry-forward; approved request/session surroundings
// are fixture-only. Original save, two-role signature and payroll writers run.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const original=await readFile('tool/verify_checkout_shared_hours_v2.mjs','utf8');
const marker=" console.log(JSON.stringify({pass:true,versioned_work_report_then_individual_hours:true,first_work_signature_preserved:true,stale_and_direct_supervisor_bypass_denied:true,actual_payroll_quantities:[7.25,6.75],legacy_reports_preserved:true,real_gotrue:false,production_changed:false}));";
assert.equal(original.split(marker).length,2);
const addition=String.raw`
 phase='approved-v2-exact-unchanged-fact-copy';
 await exec("create table if not exists public.daily_report_edit_requests(id uuid primary key,report_id uuid,company_id uuid,requested_by uuid,reason text,status text,approvals_required integer default 2,created_at timestamptz default now(),resolved_at timestamptz);alter table public.daily_report_edit_requests add column if not exists company_id uuid;revoke insert,update,delete on public.daily_report_edit_requests from authenticated,anon;");
 await exec(await readFile('docs/candidates/shared_daily_report_approved_edit.sql.review-only','utf8'));
 const approvedV2=id(8990);
 const v2OriginalPayroll=await q("select jsonb_agg(jsonb_build_object('worker_id',worker_id,'gross_pay',gross_pay,'deductions',deductions,'net_pay',net_pay) order by worker_id) v from payroll_statements where company_id=$1 and worker_id=any($2::uuid[]) and period_start='2026-10-01'",[A,[reportWorker,W2]]);
 const v2ApprovedRoster=await q('select jsonb_agg(to_jsonb(w)-\'report_id\' order by worker_id) v from daily_report_workers w where report_id=$1',[v2Rid]);
 const v2BeforeEdits=await q('select jsonb_agg(to_jsonb(c) order by worker_id,revision) v from checkout_shared_hours_private.confirmations c where report_id=$1',[v2Rid]);
 await client.query("insert into public.daily_report_edit_requests(id,report_id,company_id,requested_by,status) values($1,$2,$3,$4,'approved')",[approvedV2,v2Rid,A,memberC]);
 await sharedCall(memberC,sidC,'select public.save_daily_report_destination_draft($1,$2,null,$3,$4,$5::jsonb) v',[v2Rid,SITE,v2Day,'作業説明のみ承認修正',JSON.stringify(v2ApprovedRoster)]);
 const v2Editing=await sharedCall(memberC,sidC,'select public.read_shared_daily_report_context($1) v',[v2Rid]);
 eq(v2Editing.approved_edit_request_id,approvedV2,'Exact approved non-roster editor may continue only this request');
 eq(v2Editing.can_manage_attendance,false,'Approved correction never grants general management');
 const wrongEditSid=id(8991);await client.query('insert into auth.sessions(id,user_id) values($1,$2)',[wrongEditSid,memberC]);
 await reject(()=>sharedCall(memberC,wrongEditSid,"select public.save_daily_report_signature($1,'representative',$2,$3::jsonb) v",[v2Rid,'別セッション',signature]),/exact_actor_session_required/);
 await sharedCall(memberC,sidC,"select public.save_daily_report_signature($1,'representative',$2,$3::jsonb) v",[v2Rid,'承認修正の実報告者',signature]);
 const v2Copies=await q('select jsonb_agg(to_jsonb(c) order by worker_id) v from checkout_shared_hours_private.approved_fact_copies c where request_id=$1',[approvedV2]);
 eq(v2Copies.length,2,'Both and only unchanged clocked personal attestations carry forward');
 eq(v2Copies.every(c=>c.editor_actor_id===memberC&&c.editor_session_id===sidC&&c.prior_actor_id!==memberC),true,'Copy audit distinguishes each original actor from exact editor and session');
 const v2CopiedFacts=await q("select jsonb_agg(jsonb_build_object('kind',confirmation_kind,'actor',confirmed_by,'hours',hours) order by worker_id) v from checkout_shared_hours_private.confirmations where id=any($1::bigint[])",[v2Copies.map(c=>c.new_confirmation_id)]);
 eq(v2CopiedFacts.every(c=>c.kind==='approved_editor'&&c.actor===memberC),true,'Copied attestation never misrepresents the editor as worker or manager');
 eq(v2CopiedFacts.map(c=>c.hours).sort((a,b)=>a-b),[6.75,7.25],'Previously attested hours remain exact');
 const v2EditedReady=await sharedCall(memberC,sidC,'select public.read_shared_daily_report_context($1) v',[v2Rid]);
 eq(v2EditedReady.hours_annex.ready,true,'New work epoch has auditable matching unchanged facts');
 await sharedCall(memberC,sidC,'select public.collect_approved_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[v2Rid,approvedV2,'承認修正の実現場責任者',signature,v2EditedReady.report_updated_at,v2EditedReady.signature_scope_fingerprint]);
 eq(await q("select jsonb_agg(jsonb_build_object('worker_id',worker_id,'gross_pay',gross_pay,'deductions',deductions,'net_pay',net_pay) order by worker_id) v from payroll_statements where company_id=$1 and worker_id=any($2::uuid[]) and period_start='2026-10-01'",[A,[reportWorker,W2]]),v2OriginalPayroll,'Work-description correction preserves all payroll currency');
 eq(await q('select jsonb_agg(to_jsonb(c) order by worker_id,revision) v from checkout_shared_hours_private.confirmations c where report_id=$1 and id=any($2::bigint[])',[v2Rid,v2BeforeEdits.map(c=>c.id)]),v2BeforeEdits,'Every old personal attestation remains byte-identical');
 eq(await q("select has_function_privilege('authenticated','checkout_shared_hours_private.copy_forward_approved_unchanged_facts(uuid,uuid)','execute') v"),false,'No client can manufacture a copy receipt by direct call');
 console.log(JSON.stringify({pass:true,approved_v2_original_attestations_preserved:true,approved_editor_audit_distinct:true,actual_signed_payroll_unchanged:true,real_gotrue:false,production_changed:false}));
`;
const folder=await mkdtemp(join(tmpdir(),'approved-shared-v2-proof-'));
try{
 const file=join(folder,'proof.mjs');await writeFile(file,original.replace(marker,()=>addition+marker));
 const result=spawnSync(process.execPath,[file,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally{await rm(folder,{recursive:true,force:true});}
