// Extends the existing actual old-writer RED/native chain without modifying it.
// Only synthetic auth/session/explicit-finalization surroundings; no real GoTrue.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
let original=await readFile('tool/verify_approved_edit_allowance_reset.mjs','utf8');
const marker=" eq(oldPc.supervisor_signature_json,pcReportBefore.supervisor_signature_json,'RED: old writer incorrectly retains supervisor signature on unchanged PC');";
assert.equal(original.split(marker).length,2,'Exact old-writer failure observation');
const addition=String.raw`
 phase='resume-old-signatures-without-new-approval';
 await exec('create schema if not exists explicit_report_finalization_private;create table if not exists explicit_report_finalization_private.events(report_id uuid,kind text);create table if not exists explicit_report_finalization_private.management_reports(report_id uuid);');
 await exec(await readFile('docs/review/approved-edit-signature-resume/core.sql','utf8'));
 const resumeBefore=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[pcRid]);
 const resumeSession=await q('select to_jsonb(s) v from shared_report_edit_private.sessions s where report_id=$1',[pcRid]);
 eq(resumeSession.state,'active','Broken draft retains the existing exact active session');
 eq(resumeSession.request_id,pcRequest,'No replacement request is invented');
 const resumeArgs=[pcRid,pcRequest,resumeBefore.report_updated_at,resumeBefore.signature_scope_fingerprint];
 const resumeSql='select public.resume_approved_daily_report_signatures($1,$2,$3::timestamptz,$4) v';
 const recoveryCall=async(actor,sid,sql,args=[])=>{await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[actor,sid]);await exec('set role authenticated');const result=await q(sql,args);await exec('reset role');return result;};
 const recoveryReject=async(operation,pattern)=>{
  await exec('savepoint recovery_case');let failure;
  try {await operation();}catch(error){failure=error;}
  await exec('rollback to recovery_case;release recovery_case;reset role');
  assert.ok(failure,'Recovery operation must reject');assert.match(failure.message,pattern);
 };
 await recoveryReject(()=>recoveryCall(memberB,sidB,resumeSql,resumeArgs),/exact_session|membership|actor/);
 const recoverySid=id(8666);await client.query('insert into auth.sessions(id,user_id) values($1,$2)',[recoverySid,U]);
 await recoveryReject(()=>recoveryCall(U,recoverySid,resumeSql,resumeArgs),/exact_session/);
 await recoveryReject(()=>recoveryCall(U,id(80),resumeSql,[pcRid,id(8667),resumeArgs[2],resumeArgs[3]]),/exact_session/);
 await recoveryReject(()=>recoveryCall(U,id(80),resumeSql,[pcRid,pcRequest,'2020-01-01',resumeArgs[3]]),/scope_changed/);
 await recoveryReject(()=>recoveryCall(U,id(80),resumeSql,[pcRid,pcRequest,resumeArgs[2],'bad-scope']),/scope_changed/);
 await exec('savepoint recovery_finalized');
 await client.query("insert into explicit_report_finalization_private.events values($1,'finalized')",[pcRid]);
 await recoveryReject(()=>recoveryCall(U,id(80),resumeSql,resumeArgs),/requires_attendance_management/);
 await exec('rollback to recovery_finalized;release recovery_finalized');
 await exec('savepoint recovery_managed');await client.query('insert into explicit_report_finalization_private.management_reports values($1)',[pcRid]);
 await recoveryReject(()=>recoveryCall(U,id(80),resumeSql,resumeArgs),/requires_attendance_management/);
 await exec('rollback to recovery_managed;release recovery_managed');
 const resumeAfter=await recoveryCall(U,id(80),resumeSql,resumeArgs);
 const resumed=await q('select to_jsonb(r) v from daily_reports r where id=$1',[pcRid]);
 for(const field of ['representative_signature_json','representative_signer_name','supervisor_signature_json','supervisor_signer_name'])eq(resumed[field],null,'Recovered current role field is empty '+field);
 eq(resumed.status,'draft','Recovery enables fresh signatures, never silently finalizes');
 eq(await q('select to_jsonb(s) v from shared_report_edit_private.sessions s where report_id=$1',[pcRid]),resumeSession,'Archived original session/report/roster/annex remain byte-for-byte');
 eq(await q('select jsonb_agg(to_jsonb(w) order by worker_id) v from daily_report_workers w where report_id=$1',[pcRid]),pcRosterBefore,'Recovery never changes financial or roster facts');
 eq(await q('select jsonb_agg(to_jsonb(r) order by id) v from company_checkout_allowance_private.receipts r where report_id=$1',[pcRid]),pcReceiptsBefore,'PC receipt history unchanged');
 eq(await q('select status v from daily_report_edit_requests where id=$1',[pcRequest]),'used','Existing consumed approval is not reset or replaced');
 eq(resumeAfter.reporter_saved,false,'Client receives authoritative unsigned reporter state');
 eq(resumeAfter.supervisor_saved,false,'Client receives authoritative unsigned responsible state');
 await recoveryCall(U,id(80),resumeSql,resumeArgs);
 eq(await q('select to_jsonb(r) v from daily_reports r where id=$1',[pcRid]),resumed,'Lost-response retry performs no second update');
 const resumeParentContext=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[pcRid]);
 await sharedCall(U,id(80),"select public.save_daily_report_signature($1,'representative','新しい報告者',$2::jsonb) v",[pcRid,signature]);
 await recoveryReject(()=>recoveryCall(U,id(80),resumeSql,resumeArgs),/new_signature_present|basis_changed/);
 const newReporter=await q('select representative_signature_json v from daily_reports where id=$1',[pcRid]);
 const resumedReady=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[pcRid]);
 const resumedFinal=await sharedCall(U,id(80),'select public.collect_approved_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[pcRid,pcRequest,'新しい責任者',signature,resumedReady.report_updated_at,resumedReady.signature_scope_fingerprint]);
 const resumedFinalState=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[pcRid]);
 eq(resumedFinalState.supervisor_saved,true,'The same request reaches a new responsible signature through the existing approved route');
 eq(await q('select status v from daily_reports where id=$1',[pcRid]),'signed','Recovery finishes through the existing audited finalization');
 assert.ok(newReporter,'New signature is not erased by a stale recovery action');
 eq(await q("select has_function_privilege('anon','public.resume_approved_daily_report_signatures(uuid,uuid,timestamp with time zone,text)','execute') v"),false,'Anonymous recovery denied');
 eq(await q("select has_function_privilege('service_role','public.resume_approved_daily_report_signatures(uuid,uuid,timestamp with time zone,text)','execute') v"),false,'Service role cannot bypass the human live-session route');
 console.log(JSON.stringify({pass:true,actual_old_writer_stranded_state:true,same_approved_request_resume:true,old_originals_preserved:true,new_signature_not_erased:true,repeat_no_second_mutation:true,foreign_actor_sid_and_finalized_denied:true,real_gotrue:false,production_changed:false}));
`;
original=original.replace(marker,()=>marker+'\n'+addition);
const folder=await mkdtemp(join(tmpdir(),'approved-signature-resume-'));
try {
 const file=join(folder,'proof.mjs');await writeFile(file,original);
 const result=spawnSync(process.execPath,[file,...process.argv.slice(2)],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally{await rm(folder,{recursive:true,force:true});}
