// Disposable PG17; source installers only, no old 91/96/255/331 case replay.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';import {join,resolve} from 'node:path';import {fileURLToPath} from 'node:url';import {spawnSync} from 'node:child_process';
const here=fileURLToPath(new URL('.',import.meta.url)),admin=resolve(here,'../attendance-admin-override-candidate'),doc=resolve(here,'../supervisor-document-candidate');
const folder=await mkdtemp(join(tmpdir(),'management-registered-native-'));
try{
 const emitted=join(folder,'admin.mjs');
 const result=spawnSync(process.execPath,[resolve(admin,'verify_admin_override.mjs')],{stdio:'inherit',env:{...process.env,SKO_ADMIN_EMIT_ONLY:emitted}});assert.equal(result.status,0);
 const source=await readFile(emitted,'utf8'),marker=" eq(await q('select count(*)::int v from attendance_admin_override_private.rollout'),0,";
 assert.equal(source.split(marker).length,2);const prefix=source.slice(0,source.indexOf(marker)),tail=source.slice(source.indexOf('}catch(error){'));
 const unit=String.raw`
 phase='registered-management-install';
 await exec('alter table company_common_allowance_private.items add column if not exists position integer default 0');
 for(const row of JSON.parse(await readFile(process.env.SKO_MANAGEMENT_READER_SOURCES,'utf8'))){eq(md5(dbBody(row.definition)),row.source_md5,'Observed names reader source');await exec(row.definition);}
 await exec("create function public.read_company_registered_allowance_labels(p_company_id uuid) returns jsonb language sql stable set search_path='' as $$select company_common_allowance_private.registered_labels(p_company_id)$$");
 await exec(await readFile(process.env.SKO_MANAGEMENT_REGISTERED_SQL,'utf8'));
 eq(await q('select count(*)::int v from management_registered_allowance_private.rollout'),0,'Installation is OFF');
 await exec("select set_config('fixture.manager','on',false)");await client.query('insert into attendance_admin_override_private.rollout values($1,true)',[A]);
 const cell=(wid,date,more={})=>({worker_id:wid,date,mode:'work',site_id:SITE,man_days:1,overtime_hours:0,early_hours:0,night_hours:0,allowance_names:[],work_description:'管理者の明示登録',clock_in:'08:00',clock_out:'17:00',...more});
 const typed=(items,legacy='')=>({company_allowance_selections:choices(items),company_allowance_legacy_labels:legacy});
 const force=items=>sharedCall(U,id(80),'select public.force_manage_attendance($1,$2::jsonb) v',['upsert',JSON.stringify(items)]);
 const options=(workers=[W],actor=U,sid=id(80))=>sharedCall(actor,sid,'select public.read_management_company_allowance_options($1::uuid[]) v',[workers]);
 await reject(()=>options(),{code:'42501',message:'management_registered_allowances_disabled'});
 await reject(()=>force([cell(W,'2026-10-24',typed([days[0]]))]),{code:'42501',message:'management_registered_allowances_disabled'});
 await reject(()=>force([cell(W,'2026-10-24',{company_allowance_legacy_labels:'free'})]),{code:'42501',message:'management_registered_allowances_disabled'});
 eq(await q('select count(*)::int v from attendance_admin_override_private.operations'),0,'OFF rejection makes no mutation/audit');
 await client.query('insert into management_registered_allowance_private.rollout values($1,true)',[A]);
 let opt=await options([W,W2]);eq(opt.contract_version,1,'Versioned options');eq(opt.company_id,A,'Current company');eq(opt.workers.length,2,'Exact worker set');eq(opt.labels.registration_scope,'current','Exact current names');
 eq(opt.labels.items.some(x=>x.id===MONTH),true,'Month labels remain visible');eq(opt.workers.every(x=>!x.items.some(i=>i.id===MONTH)),true,'Month items are never day/hour selections');eq(opt.workers.every(x=>x.items.some(i=>i.id===DAYS[0])),true,'Eligible registered ID is selectable');
 await reject(()=>options([W,W]),{code:'42501',message:'management_allowance_worker_scope_invalid'});await reject(()=>options([OTHER]),{code:'42501',message:'management_allowance_worker_scope_invalid'});
 phase='registered-management-create-and-preserve';
 eq(await force([cell(W,'2026-10-24',typed([days[0]],'任意の記録名\nもう一つの記録名'))]),1,'Explicit typed registration saved');
 const reportId=await q("select id v from daily_reports where company_id=$1 and site_id=$2 and report_date='2026-10-24'",[A,SITE]);
 const workerRow=()=>q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2',[reportId,W]);
 const receiptId=()=>q('select company_allowance_receipt_id v from attendance_entries where source_report_id=$1 and worker_id=$2',[reportId,W]);
 const receipt=()=>q('select r.snapshot v from attendance_entries a join company_checkout_allowance_private.receipts r on r.id=a.company_allowance_receipt_id where a.source_report_id=$1 and a.worker_id=$2',[reportId,W]);
 eq((await workerRow()).company_allowance_selections,choices([days[0]]),'Exact ID/version/unit stays typed');eq((await workerRow()).company_allowance_legacy_labels,'任意の記録名\nもう一つの記録名','Free names are separate');
 const firstId=await receiptId(),first=await receipt();eq(first.items[0].rate_yen,100,'Price comes from trusted catalog');eq(first.authority.kind,'attendance_management','Not a supervisor-signature receipt');eq(first.authority.actor_id,U,'Actual manager');eq(first.authority.session_id,id(80),'Actual live session');eq(await q('select state v from attendance_admin_override_private.operations where id=$1',[first.authority.operation_id]),'committed','Receipt ties to committed exact operation');
 eq(await q('select representative_signature_json is null and supervisor_signature_json is null v from daily_reports where id=$1',[reportId]),true,'No fake handwritten signatures');
 let resolved=await q("select company_checkout_allowance_private.resolve($1,$2,'2026-10-01','2026-10-31') v",[A,W]);eq(resolved.blocked,false,'Existing day consumer is usable');eq(resolved.items[0].amount_yen,100,'Existing rate-times-day formula');
 await client.query('update company_common_allowance_private.state set version=2 where company_id=$1',[A]);await client.query('update company_common_allowance_private.items set amount_yen=200 where id=$1',[DAYS[0]]);
 eq(await force([cell(W,'2026-10-24',{overtime_hours:1})]),1,'Old API time edit still works');eq((await workerRow()).company_allowance_selections,choices([days[0]]),'Absent keys preserve stale-but-original identity');eq((await workerRow()).company_allowance_legacy_labels,'任意の記録名\nもう一つの記録名','Absent legacy preserves original');eq(await receiptId(),firstId,'No repricing on unrelated change');eq(await receipt(),first,'Original receipt unchanged');
 const fresh={...days[0],registration_version:2};eq(await force([cell(W,'2026-10-24',typed([fresh],'新しい任意名'))]),1,'Explicit changed choice revalidated');const secondId=await receiptId();eq(secondId!==firstId,true,'New version receives new receipt');eq((await receipt()).items[0].rate_yen,200,'New registry price captured');eq(await q('select snapshot v from company_checkout_allowance_private.receipts where id=$1',[firstId]),first,'Old receipt history retained');
 const beforeInvalid=await workerRow(),beforeCount=await q('select count(*)::int v from attendance_admin_override_private.operations');
 await reject(()=>force([cell(W,'2026-10-24',typed([days[0]]))]),{code:'40001',message:'company allowance registration changed; reload report choices'});eq(await workerRow(),beforeInvalid,'Stale request rolls back');eq(await receiptId(),secondId,'Stale request keeps current pointer');eq(await q('select count(*)::int v from attendance_admin_override_private.operations'),beforeCount,'No fake successful audit');
 await reject(()=>force([cell(W,'2026-10-24',{company_allowance_selections:null})]),{code:'22023',message:'management_allowances_use_explicit_empty_selection'});
 await client.query("update worker_payroll_settings set pay_type='monthly' where company_id=$1 and worker_id=$2",[A,W2]);opt=await options([W,W2]);eq(opt.workers.find(x=>x.worker_id===W2).items.some(x=>x.id===DAYS[0]),false,'Worker payroll eligibility respected');await reject(()=>force([cell(W2,'2026-10-23',typed([fresh]))]),{code:'40001',message:'company allowance registration changed; reload report choices'});
 phase='actual-prior-signature-receipt-preservation';
 await client.query('update company_common_allowance_private.state set version=1 where company_id=$1',[A]);
 const historical=await draft('2020-10-15',W4,[days[1]]);await sign(historical);
 const oldReceipt=await q('select company_allowance_receipt_id v from attendance_entries where source_report_id=$1 and worker_id=$2',[historical,W4]);const oldSnapshot=await q('select snapshot v from company_checkout_allowance_private.receipts where id=$1',[oldReceipt]);eq(oldSnapshot.authority,undefined,'Old receipt is the actual signature contract');
 await client.query('update company_common_allowance_private.state set version=2 where company_id=$1',[A]);eq(await force([cell(W4,'2020-10-15',{night_hours:1})]),1,'Edit a truly signed historical source');eq(await q('select company_allowance_receipt_id v from attendance_entries where source_report_id=$1 and worker_id=$2',[historical,W4]),oldReceipt,'Actual prior signature receipt ID kept');eq(await q('select snapshot v from company_checkout_allowance_private.receipts where id=$1',[oldReceipt]),oldSnapshot,'Actual prior receipt bytes kept');eq(await q('select representative_signature_json is null and supervisor_signature_json is null v from daily_reports where id=$1',[historical]),true,'Changed current content is unsigned');
 phase='hourly-hold-and-atomic-batch';
 const hour={...choice('company_common',HOUR,'合成時間手当','hour'),registration_version:2};eq(await force([cell(W3,'2026-10-23',typed([hour]))]),1,'Hour identity saved');const hourResult=await q("select company_checkout_allowance_private.resolve($1,$2,'2026-10-01','2026-10-31') v",[A,W3]);eq(hourResult.blocked,true,'No guessed paid hours');eq(hourResult.items.some(x=>x.unit==='hour'&&x.quantity===null),true,'Missing hours stay uncalculated');
 eq(await force([cell(W6,'2026-10-22',{allowance_names:['追加会社手当0']})]),1,'Explicit free-name input stays supported');eq(await q("select w.company_allowance_selections is null and a.company_allowance_receipt_id is null v from daily_reports r join daily_report_workers w on w.report_id=r.id join attendance_entries a on a.source_report_id=r.id and a.worker_id=w.worker_id where r.report_date='2026-10-22' and w.worker_id=$1",[W6]),true,'Matching free string is never masqueraded as registered ID/receipt');
 const snapshotSQL="select jsonb_build_object('reports',(select jsonb_agg(to_jsonb(r) order by id) from daily_reports r),'workers',(select jsonb_agg(to_jsonb(w) order by report_id,worker_id) from daily_report_workers w),'receipts',(select jsonb_agg(to_jsonb(c) order by id) from company_checkout_allowance_private.receipts c)) v";
 const beforeRollback=await q(snapshotSQL),auditBefore=await q('select count(*)::int v from attendance_admin_override_private.operations');await reject(()=>force([cell(W3,'2026-10-21',typed([fresh])),cell(W7,'2026-10-20',{clock_in:'not-a-time'})]),/time zone "not-a-time" not recognized/);eq(await q(snapshotSQL),beforeRollback,'Late failure rolls back earlier receipt and source changes');eq(await q('select count(*)::int v from attendance_admin_override_private.operations'),auditBefore,'Failed batch has no success audit');eq(await q('select count(*)::int v from attendance_admin_override_private.contexts'),0,'No stale operation permit');
 await exec("select set_config('fixture.manager','off',false)");await reject(()=>options(),{code:'42501',message:'attendance_admin_current_management_required'});await exec("select set_config('fixture.manager','on',false)");eq(await q("select has_schema_privilege('authenticated','management_registered_allowance_private','usage') v"),false,'Private helpers inaccessible');eq(await q("select has_function_privilege('anon','public.read_management_company_allowance_options(uuid[])','execute') v"),false,'Anonymous API unavailable');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,management_authority_explicit:true,signature_writers_unchanged:true,old_broad_suites_replayed:false,production_changed:false}));
`;

 const restoreUnit=String.raw`
 phase='independent-unused-install-restore';
 const signatures=['public.force_manage_attendance(text,jsonb)','attendance_admin_override_private.permit_roster(text,jsonb,jsonb)'];
 const metadata=async()=>Promise.all(signatures.map(sig=>q("select jsonb_build_object('definition',pg_get_functiondef(oid),'body',prosrc,'owner',pg_get_userbyid(proowner),'acl',proacl::text,'config',proconfig,'definer',prosecdef) v from pg_proc where oid=to_regprocedure($1)",[sig])));
 const originals=await metadata();
 const business=()=>q("select jsonb_build_object('reports',(select jsonb_agg(to_jsonb(x) order by id) from daily_reports x),'workers',(select jsonb_agg(to_jsonb(x) order by report_id,worker_id) from daily_report_workers x),'entries',(select jsonb_agg(to_jsonb(x) order by id) from attendance_entries x),'receipts',(select jsonb_agg(to_jsonb(x) order by id) from company_checkout_allowance_private.receipts x),'operations',(select jsonb_agg(to_jsonb(x) order by id) from attendance_admin_override_private.operations x)) v");
 const before=await business();
 await exec(await readFile(process.env.SKO_MANAGEMENT_REGISTERED_SQL,'utf8'));
 eq(await q('select count(*)::int v from management_registered_allowance_private.rollout'),0,'New independent module stays default OFF');
 const restore=await readFile(process.env.SKO_MANAGEMENT_UNUSED_RESTORE_SQL,'utf8');
 await client.query('insert into management_registered_allowance_private.rollout values($1,false)',[A]);
 await reject(()=>exec(restore),/management_allowance_restore_requires_never_enabled/);await exec('rollback');
 eq(await q("select to_regprocedure('public.read_management_company_allowance_options(uuid[])') is not null v"),true,'Rejected restore keeps module installed');
 await client.query('delete from management_registered_allowance_private.rollout where company_id=$1',[A]);
 await exec(restore);
 eq(await metadata(),originals,'Exact original definitions, bodies, owners, ACL, config and security mode restored');
 eq(await q("select to_regnamespace('management_registered_allowance_private') is null and to_regprocedure('public.read_management_company_allowance_options(uuid[])') is null v"),true,'Only unused module objects removed');
 eq(await business(),before,'Independent unused restore changes no business rows or audit/receipt history');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,independent_unused_fixture:true,exact_original_routines_restored:true,production_changed:false}));
 `;
 const selected=process.env.SKO_MANAGEMENT_UNUSED_RESTORE==='true'?restoreUnit:unit;
 const proof=join(folder,'proof.mjs');await writeFile(proof,prefix+selected+tail);
 if(process.env.SKO_MANAGEMENT_REGISTERED_EMIT_ONLY){await writeFile(process.env.SKO_MANAGEMENT_REGISTERED_EMIT_ONLY,prefix+selected+tail);}else{
 const execution=spawnSync(process.execPath,[proof,process.argv[2]],{stdio:'inherit',env:{...process.env,SKO_DOCUMENT_CANDIDATE:resolve(doc,'document-signature-and-edit.sql.review-only'),SKO_DOCUMENT_TRIGGER_PINS:resolve(doc,'trigger-source-pins.json'),SKO_ADMIN_CANDIDATE:resolve(admin,'attendance-admin-override.sql.review-only'),SKO_ADMIN_ORIGINALS:resolve(admin,'native-original-sources.sql'),SKO_MANAGEMENT_REGISTERED_SQL:resolve(here,'management-registered-allowances.sql.review-only'),SKO_MANAGEMENT_READER_SOURCES:resolve(here,'native-reader-sources.json'),SKO_MANAGEMENT_UNUSED_RESTORE_SQL:resolve(here,'management-registered-allowances.unused-restore.sql.review-only')}});if(execution.error)throw execution.error;process.exitCode=execution.status??1;
 }
}finally{await rm(folder,{recursive:true,force:true});}
