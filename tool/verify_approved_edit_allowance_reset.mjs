// Native PostgreSQL17 only. Extends the existing real save/sign/receipt chain;
// authentication, tax and permission surroundings remain declared fixtures.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
let base=await readFile('tool/verify_checkout_shared_approved_v2.mjs','utf8');
const originalRead="const original=await readFile('tool/verify_checkout_shared_hours_v2.mjs','utf8');";
const rosterLine=' const v2Roster=JSON.stringify([worker(reportWorker,[]),worker(W2,[])]);';
const pcSetup=" const resetPcItem=id(8660);\n await client.query(\"insert into company_common_allowance_private.items(id,company_id,payroll_type,section,unit,name,amount_yen) values($1,$2,'daily','earning','day','PC',3000)\",[resetPcItem,A]);\n const resetPcChoice=choice('company_common',resetPcItem,'PC');\n const v2Roster=JSON.stringify([worker(reportWorker,[resetPcChoice]),worker(W2,[resetPcChoice])]);";
const selectedLine="const v2SelectedHours={contract_version:1,items:[choice('company_common',HOUR,'合成時間手当','hour')]};";
const selectedPC="const v2SelectedHours={contract_version:1,items:[choice('company_common',HOUR,'合成時間手当','hour'),resetPcChoice]};";
assert.equal(base.split(originalRead).length,2);
base=base.replace(originalRead,"const original=(await readFile('tool/verify_checkout_shared_hours_v2.mjs','utf8')).replace("+JSON.stringify(rosterLine)+","+JSON.stringify(pcSetup)+").replace("+JSON.stringify(selectedLine)+","+JSON.stringify(selectedPC)+").replaceAll("+JSON.stringify("allowance_label:'合成時間手当'")+","+JSON.stringify("allowance_label:'合成時間手当\\nPC'")+");");
const marker=' const approvedV2=id(8990);';
assert.equal(base.split(marker).length,2);
const unit=String.raw`
 phase='unchanged-PC-approved-reset';
 const resetSource=JSON.parse(await readFile('docs/review/approved-edit-allowance-reset/deployed-source.json','utf8'));
 eq(resetSource.application_rows_read,false,'Only deployed function metadata was captured');
 await exec(resetSource.function.definition);
 for(const f of resetSource.history_functions)await exec(f.definition);
 await exec(resetSource.report_basis.definition);
 eq(await q("select md5(prosrc) v from pg_proc where oid='public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'::regprocedure"),resetSource.source_md5,'Exact current deployed writer body installed');
 const pcRid=v2Rid,pcRequest=id(8664),pcDate=v2Day;
 const pcRows=JSON.stringify(await q("select jsonb_agg(to_jsonb(w)-'report_id' order by worker_id) v from daily_report_workers w where report_id=$1",[pcRid]));
 const pcDescription=await q('select work_description v from daily_reports where id=$1',[pcRid]);
 const pcReportBefore=await q('select to_jsonb(r) v from daily_reports r where id=$1',[pcRid]);
 const pcRosterBefore=await q('select jsonb_agg(to_jsonb(w) order by worker_id) v from daily_report_workers w where report_id=$1',[pcRid]);
 const pcReceiptsBefore=await q('select jsonb_agg(to_jsonb(r) order by id) v from company_checkout_allowance_private.receipts r where report_id=$1',[pcRid]);
 assert.ok(pcReceiptsBefore?.some(receipt=>receipt.snapshot.items.some(item=>item.name==='PC')),'Actual v2 report has a captured PC receipt before reset');
 eq(pcReportBefore.status,'signed','Unchanged PC baseline is fully signed');
 assert.ok(pcReportBefore.representative_signature_json&&pcReportBefore.supervisor_signature_json);
 const pcSave=()=>sharedCall(U,id(80),"select public.save_daily_report_destination_draft($1,$2,null,$3,$4,$5::jsonb) v",[pcRid,SITE,pcDate,pcDescription,pcRows]);
 await reject(pcSave,/approved edit request/);
 eq(await q('select to_jsonb(r) v from daily_reports r where id=$1',[pcRid]),pcReportBefore,'Missing approval changes no signed data');
 await client.query("insert into public.daily_report_edit_requests(id,report_id,company_id,requested_by,status) values($1,$2,$3,$4,'approved')",[pcRequest,pcRid,A,U]);
 await reject(()=>sharedCall(memberB,sidB,"select public.save_daily_report_destination_draft($1,$2,null,$3,$4,$5::jsonb) v",[pcRid,SITE,pcDate,pcDescription,pcRows]),/approved edit request|actor|member/);
 eq(await q('select status v from daily_report_edit_requests where id=$1',[pcRequest]),'approved','Foreign actor cannot consume the approval');
 // Savepoint makes the old broken attempt observable without retaining its
 // draft/signature inconsistency in the rest of the disposable proof.
 await exec('begin;savepoint old_unchanged_pc');
 await pcSave();
 const oldPc=await q('select to_jsonb(r) v from daily_reports r where id=$1',[pcRid]);
 eq(oldPc.status,'draft','Old writer consumes approval and changes status');
 eq(oldPc.representative_signature_json,pcReportBefore.representative_signature_json,'RED: old writer incorrectly retains reporter signature on unchanged PC');
 eq(oldPc.supervisor_signature_json,pcReportBefore.supervisor_signature_json,'RED: old writer incorrectly retains supervisor signature on unchanged PC');
 await exec('rollback');
 eq(await q('select status v from daily_report_edit_requests where id=$1',[pcRequest]),'approved','Old attempt rolled back including request consumption');
 await exec(await readFile('docs/review/approved-edit-allowance-reset/approved-edit-allowance-reset.sql.review-only','utf8'));
 const resetPin=Object.keys(pins.after_source_md5).filter(name=>fq(name)==='public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)');
 eq(resetPin.length,1,'Exactly one parent source pin represents the deliberately patched writer');
 eq(pins.after_source_md5[resetPin[0]],'8c341bb00650cab35b1fa23b34e69eae','Parent writer pin was unchanged before the explicit candidate composition');
 eq(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',[fq(resetPin[0])]),'075b62ee12e02f4aeb04f6c20bbfd3d3','Reviewed four-CASE candidate is the only new intended writer body');
 pins.after_source_md5[resetPin[0]]='075b62ee12e02f4aeb04f6c20bbfd3d3';
 await exec('begin');
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
 await exec('savepoint wrong_pc_sid');
 await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[U,otherSid]);
 await exec('set role authenticated');
 let pcSidError;
 try {await q("select public.save_daily_report_destination_draft($1,$2,null,$3,$4,$5::jsonb) v",[pcRid,SITE,pcDate,pcDescription,pcRows]);}catch(error){pcSidError=error;}
 await exec('rollback to wrong_pc_sid');
 assert.ok(pcSidError,'Different live session must be denied');assert.match(pcSidError.message,/exact_actor_session_required|reset_proof|exact_session/);

 await pcSave();
 eq(await q('select to_jsonb(s) v from shared_report_edit_private.sessions s where report_id=$1',[pcRid]),pcSession,'Retry cannot consume another request or replace the old signature history');
 eq(await q("select to_jsonb(p)-'prosrc' v from pg_proc p where oid='public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'::regprocedure"),fixedAttrs,'Ownership grants and security attributes remain unchanged');
 for(const f of resetSource.history_functions)eq(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',
  [f.schema_name+'.'+f.proname+(f.proname==='begin_reset'?'(jsonb,jsonb)':'()')]),
  md5(dbBody(f.definition)),'Exact deployed history capture/reset guard is unchanged');
 // Legacy non-protocol draft: ordinary unchanged PC saves still retain an
 // already collected reporter signature. The patch is NOT a global clear.
 await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[U,id(80)]);
 const ordinaryPc=await draft('2025-09-17',reportWorker,[resetPcChoice]);
 eq(await q('select shared_daily_report_private.report_enabled($1) v',[ordinaryPc]),false,'Ordinary draft is outside the shared-consent rollout, not an unauthorized shared-report edit');
 await sharedCall(U,id(80),"select public.save_daily_report_signature($1,'representative','合成通常報告者',$2::jsonb) v",[ordinaryPc,signature]);
 const ordinarySig=await q('select representative_signature_json v from daily_reports where id=$1',[ordinaryPc]);
 await draft('2025-09-17',reportWorker,[resetPcChoice],{reportId:ordinaryPc});
 eq(await q('select representative_signature_json v from daily_reports where id=$1',[ordinaryPc]),ordinarySig,'Ordinary unchanged PC draft preserves its signature');
 await exec('rollback');
 await client.query('delete from public.daily_report_edit_requests where id=$1',[pcRequest]);
 eq(await q('select to_jsonb(r) v from daily_reports r where id=$1',[pcRid]),pcReportBefore,'Disposable regression leaves the parent v2 report exactly unchanged');
 console.log(JSON.stringify({pass:true,actual_v2_PC_receipt:true,unchanged_PC_old_retained_signatures_reproduced:true,approved_reset_current_roles_cleared:true,original_report_roster_annex_and_receipts_preserved:true,ordinary_draft_preserved:true,production_changed:false}));
`;
const folder=await mkdtemp(join(tmpdir(),'approved-pc-reset-proof-'));
try {
 const file=join(folder,'proof.mjs');await writeFile(file,base.replace(marker,()=>unit+marker));
 const syntax=spawnSync(process.execPath,['--check',file],{stdio:'inherit'});
 assert.equal(syntax.status,0,'Generated v2 wrapper syntax');
 if(process.argv[2]==='--syntax-only'){console.log('Generated v2 wrapper syntax valid');}
 else {
 const result=spawnSync(process.execPath,[file,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
 }
} finally {await rm(folder,{recursive:true,force:true});}
