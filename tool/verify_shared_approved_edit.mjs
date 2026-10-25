// Authorization/CAS continuation proof over unchanged real save/sign/payroll.
// Closing facts remain the parent's explicitly synthetic boundary here; the
// actual hours-v2 suite separately proves epoch/copy-forward evidence.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const base=await readFile('tool/verify_shared_daily_report.mjs','utf8');
const marker=" // A real recorded-hours basis hashes source links; it must not silently change.";
assert.equal(base.split(marker).length,2);
const unit=String.raw`
 await exec("create table if not exists public.daily_report_edit_requests(id uuid primary key,report_id uuid,company_id uuid,requested_by uuid,reason text,status text,approvals_required integer default 2,created_at timestamptz default now(),resolved_at timestamptz);alter table public.daily_report_edit_requests add column if not exists company_id uuid;revoke insert,update,delete on public.daily_report_edit_requests from authenticated,anon;");
 await exec(await readFile('docs/candidates/shared_daily_report_approved_edit.sql.review-only','utf8'));
 const approvedRequest=id(8600);
 await client.query("insert into public.daily_report_edit_requests(id,report_id,company_id,requested_by,status) values($1,$2,$3,$4,'approved')",[approvedRequest,sharedRid,A,memberC]);
 await sharedCall(memberC,sidC,"select public.save_daily_report_destination_draft($1,$2,null,'2026-10-25','承認された修正',$3::jsonb) v",[sharedRid,SITE,roster]);
 eq(await q('select status v from public.daily_report_edit_requests where id=$1',[approvedRequest]),'used','Original pinned draft writer consumes exact approved request');
 const editing=await sharedCall(memberC,sidC,'select public.read_shared_daily_report_context($1) v',[sharedRid]);
 eq(editing.approved_edit_request_id,approvedRequest,'Non-roster approved editor receives exact active request');
 eq(editing.can_manage_attendance,false,'Approved edit never grants global management');
 await reject(()=>sharedCall(U,id(80),"select public.save_daily_report_destination_draft($1,$2,null,'2026-10-25','他人の承認編集中',$3::jsonb) v",[sharedRid,SITE,roster]),/exact_actor_session_required/);
 await reject(()=>sharedCall(U,id(80),"select public.save_daily_report_signature($1,'representative',$2,$3::jsonb) v",[sharedRid,'割込報告者',signature]),/exact_actor_session_required/);

 eq(editing.work_basis.report.work_description,'承認された修正','Review context binds current approved draft, not old work epoch');
 await sharedCall(memberC,sidC,"select public.save_daily_report_signature($1,'representative',$2,$3::jsonb) v",[sharedRid,'編集後の報告者本人',signature]);
 const editedBefore=await sharedCall(memberC,sidC,'select public.read_shared_daily_report_context($1) v',[sharedRid]);
 await reject(()=>sharedCall(memberC,sidC,'select public.collect_approved_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[sharedRid,id(8601),'編集後の責任者本人',signature,editedBefore.report_updated_at,editedBefore.signature_scope_fingerprint]),/exact_session_required/);
 eq((await sharedCall(memberC,sidC,'select public.collect_approved_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[sharedRid,approvedRequest,'編集後の責任者本人',signature,editedBefore.report_updated_at,editedBefore.signature_scope_fingerprint])).state,'saved','Exact approved non-roster editor finalizes through annex/CAS wrapper');
 const editedFinal=await sharedCall(memberC,sidC,'select public.read_shared_daily_report_context($1) v',[sharedRid]);
 eq(editedFinal.approved_edit_request_id,approvedRequest,'Exact closed session retains final read receipt');
 eq(editedFinal.supervisor_saved,true,'Final read retains actual supervisor signature');
 eq((await sharedCall(memberC,sidC,'select public.collect_approved_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[sharedRid,approvedRequest,'編集後の責任者本人',signature,editedBefore.report_updated_at,editedBefore.signature_scope_fingerprint])).state,'already_saved','Lost-response exact signature retry does not rewrite final report');
 await reject(()=>sharedCall(memberC,sidC,"select public.save_daily_report_destination_draft($1,$2,null,'2026-10-25','再利用禁止',$3::jsonb) v",[sharedRid,SITE,roster]),/approved edit request/);
 const replacementSession=id(8680);await client.query('insert into auth.sessions(id,user_id) values($1,$2)',[replacementSession,memberC]);
 await reject(()=>sharedCall(memberC,replacementSession,'select public.read_shared_daily_report_context($1) v',[sharedRid]),/member_required/);
 eq(await q("select count(*)::int v from shared_report_edit_private.sessions where report_id=$1 and state='closed' and request_id=$2",[sharedRid,approvedRequest]),1,'Only actual used request has a closed audited session');
`;
const generated=base.replace(marker,()=>unit+marker);
const folder=await mkdtemp(join(tmpdir(),'shared-approved-proof-'));
try{const file=join(folder,'proof.mjs');await writeFile(file,generated);
 const result=spawnSync(process.execPath,[file,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
 if(result.status===0)console.log(JSON.stringify({pass:true,exact_approved_editor_authority:true,production_changed:false}));
}finally{await rm(folder,{recursive:true,force:true});}
