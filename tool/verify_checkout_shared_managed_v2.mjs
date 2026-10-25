// Isolated composition: actual v2 public confirmations + actual manual AE adoption.
// The parent proof runs every legacy/source/shared/ordinary-v2 scenario first.
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const original=await readFile('tool/verify_checkout_shared_hours_v2.mjs','utf8');
const marker=" console.log(JSON.stringify({pass:true,versioned_work_report_then_individual_hours:true,first_work_signature_preserved:true,stale_and_direct_supervisor_bypass_denied:true,actual_payroll_quantities:[7.25,6.75],legacy_reports_preserved:true,real_gotrue:false,production_changed:false}));";
if(!original.includes(marker))throw new Error('managed_v2_parent_marker_changed');
const addition=String.raw`
 phase='managed-source-actual-v2-finalization';
 await exec(await readFile('docs/candidates/checkout_shared_managed_source.sql.review-only','utf8'));
 const managedDay='2026-10-19',managedEntry=id(8950);
 eq(await q('select count(*)::int v from daily_reports where company_id=$1 and report_date=$2',[A,managedDay]),0,'Manual fixture uses an unused eligible day');
 eq(await q('select count(*)::int v from attendance_verifications where company_id=$1 and worker_id=$2 and work_date=$3',[A,reportWorker,managedDay]),0,'Manual case has no invented GPS or clock proof');
 await client.query("insert into attendance_entries(id,company_id,worker_id,work_date,site_id,base_man_days,overtime_hours,early_hours,night_hours,allowance_amount,work_category,source_report_id) values($1,$2,$3,$4,$5,1,0,0,0,0,'day',null)",[managedEntry,A,reportWorker,managedDay,SITE]);
 await client.query('select private.refresh_automatic_payroll($1,$2,$3)',[A,reportWorker,managedDay]);
 await client.query('select private.sync_payroll_attendance_detail($1,$2,$3)',[A,reportWorker,managedDay]);
 const managedOriginalEntry=await q('select to_jsonb(a) v from attendance_entries a where id=$1',[managedEntry]);
 const managedMoneyBefore=await q('select checkout_shared_managed_private.payroll_vector($1,$2,$3) v',[A,reportWorker,managedDay]);
 eq(managedMoneyBefore.length>0,true,'Original monthly payroll exists before any adoption');
 const managedRoster=JSON.stringify([worker(reportWorker,[])]);
 const managedRid=await sharedCall(U,id(80),'select public.save_daily_report_destination_draft(null,$1,null,$2,$3,$4::jsonb) v',[SITE,managedDay,'既存手入力勤怠を保持する管理者日報',managedRoster]);
 await exec("select set_config('fixture.manager','on',false)");
 const managedFirst=await sharedCall(memberC,sidC,'select public.read_shared_daily_report_context($1) v',[managedRid]);
 await sharedCall(memberC,sidC,'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[managedRid,'representative','実際の報告者',signature,managedFirst.report_updated_at,managedFirst.signature_scope_fingerprint]);
 const managedInput=await sharedCall(memberC,sidC,'select public.read_shared_worker_facts($1,$2) v',[managedRid,reportWorker]);
 eq(managedInput.source_kind,'managed_attendance','Manager reads actual manual source instead of fake GPS');
 eq(managedInput.source_blocked,false,'Strict matching existing formal entry is eligible');
 eq(managedInput.management_confirmation_available,true,'Audited management capability comes from server');
 const managedFacts={...managedInput.proposed_worker_facts};delete managedFacts.company_allowance_legacy_labels;
 await reject(()=>sharedCall(memberC,sidC,'select public.confirm_managed_shared_worker_facts($1,$2,$3::jsonb,null,$4,$5,$6) v',[managedRid,reportWorker,JSON.stringify(managedFacts),managedInput.revision,managedInput.scope_fingerprint,'']),/shared_hours_audited_management_required/);
 await sharedCall(memberC,sidC,'select public.confirm_managed_shared_worker_facts($1,$2,$3::jsonb,null,$4,$5,$6) v',[managedRid,reportWorker,JSON.stringify(managedFacts),managedInput.revision,managedInput.scope_fingerprint,'原本の手入力勤怠と照合して実署名を取得']);
 const managedFinal=await sharedCall(memberC,sidC,'select public.read_shared_daily_report_context($1) v',[managedRid]);
 eq(managedFinal.hours_annex.ready,true,'Actual manager confirmation closes only matching manual source');
 await sharedCall(memberC,sidC,'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[managedRid,'supervisor','実際の現場責任者',signature,managedFinal.report_updated_at,managedFinal.signature_scope_fingerprint]);
 eq(await q("select status v from daily_reports where id=$1",[managedRid]),'signed','Original dual-role signature writer completes actual managed v2 report');
 const managedFinalEntry=await q('select to_jsonb(a) v from attendance_entries a where id=$1',[managedEntry]);
 eq(managedFinalEntry.id,managedOriginalEntry.id,'Existing formal attendance identity is preserved');
 eq(managedFinalEntry.source_report_id,managedRid,'Only the previously unbound formal attendance receives report provenance');
 for(const key of ['base_man_days','overtime_hours','early_hours','night_hours','allowance_amount','work_category'])eq(managedFinalEntry[key],managedOriginalEntry[key],'Existing manual attendance value is unchanged: '+key);
 eq(await q('select checkout_shared_managed_private.payroll_vector($1,$2,$3) v',[A,reportWorker,managedDay]),managedMoneyBefore,'Every original salary currency component is unchanged after actual finalization');
 eq(await q("select count(*)::int v from checkout_shared_managed_private.adoption_events e join checkout_shared_managed_private.adoptions a on a.id=e.adoption_id where a.report_id=$1 and e.phase='verified'",[managedRid]),1,'Original signer completes immutable before-image and verified adoption audit');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.ledger where report_id=$1 and source_kind=$2',[managedRid,'managed_attendance']),1,'Actual final supervisor captures the separately confirmed manual source');
 eq(await q('select count(*)::int v from attendance_verifications where company_id=$1 and worker_id=$2 and work_date=$3',[A,reportWorker,managedDay]),0,'Successful management finalization never fabricates attendance verifications');
 await exec("select set_config('fixture.manager','off',false)");
 console.log(JSON.stringify({pass:true,actual_managed_v2_public_flow:true,manual_entry_identity_preserved:true,payroll_currency_unchanged:true,no_fake_clock_proof:true,real_gotrue:false,production_changed:false}));
`;
const folder=await mkdtemp(join(tmpdir(),'managed-shared-v2-proof-'));
try{
 const path=join(folder,'proof.mjs');await writeFile(path,original.replace(marker,()=>addition+marker));
 const result=spawnSync(process.execPath,[path,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally{await rm(folder,{recursive:true,force:true});}
