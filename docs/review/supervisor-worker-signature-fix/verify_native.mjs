// Focused PG17 regression. Reuse source-bound installers/financial producers,
// not the previous 247-case suite. Never connect to a production database.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const here=fileURLToPath(new URL('.',import.meta.url));
const ordinary=resolve(here,'../explicit-finalization-candidate');
const folder=await mkdtemp(join(tmpdir(),'supervisor-worker-regression-'));
try {
 const emitted=join(folder,'ordinary.mjs');
 const result=spawnSync(process.execPath,[ordinary+'/verify_ordinary_explicit_finalization.mjs'],{
  stdio:'inherit',env:{...process.env,SKO_ORDINARY_EXPLICIT_EMIT_ONLY:emitted}});
 assert.equal(result.status,0,'Reuse existing source-bound fixture emitter');
 const source=await readFile(emitted,'utf8'),cut=" phase='ordinary-default-off-install';";
 assert.equal(source.split(cut).length,2);
 const prefix=source.slice(0,source.indexOf(cut));
 const tail=source.slice(source.indexOf('}catch(error){'));
 const unit=String.raw`
 phase='exact-observed-worker-clear-and-permit';
 const regressionRoot=process.env.SKO_SUPERVISOR_WORKER_ROOT;
 const oldClear=JSON.parse(await readFile(regressionRoot+'/original-worker-clear.json','utf8'));
 eq(md5(dbBody(oldClear.definition)),'16e44fa84d4855055a24cbc50c94afbe','Observed production legacy clear body is exact');
 eq(await q("select md5(prosrc) v from pg_proc where oid='private.clear_daily_report_signatures_on_workers()'::regprocedure"),oldClear.body_md5,'Inherited fixture already contains the observed AFTER clear trigger body');
 eq(await q("select count(*)::int v from pg_trigger where tgrelid='public.daily_report_workers'::regclass and tgfoid='private.clear_daily_report_signatures_on_workers()'::regprocedure and not tgisinternal and tgenabled='O' and (tgtype & 2)=0 and (tgtype & 1)=1 and (tgtype & 4)=4 and (tgtype & 8)=8 and (tgtype & 16)=16"),1,'Exact legacy row AFTER INSERT/UPDATE/DELETE trigger is present');
 eq(await q("select md5(prosrc) v from pg_proc where oid='checkout_shared_hours_private.permits_worker_materialization(uuid,uuid,jsonb,jsonb)'::regprocedure"),'1f458f0223c16e5b73c0cb957d467048','Existing trusted materialization permission is exact production source');
 const originalClearCatalog=await q("select to_jsonb(p) v from pg_proc p where oid='private.clear_daily_report_signatures_on_workers()'::regprocedure");
 const reportSignature=rid=>q("select jsonb_build_object('name',representative_signer_name,'signature_bytes',representative_signature_json::text) v from daily_reports where id=$1",[rid]);
 const financial=()=>q("select jsonb_build_object('entries',(select jsonb_agg(to_jsonb(x) order by id) from attendance_entries x),'ledger',(select jsonb_agg(to_jsonb(x) order by id) from checkout_shared_hours_private.ledger x),'payroll',(select jsonb_agg(to_jsonb(x) order by worker_id,period_start) from payroll_statements x),'invoices',(select jsonb_agg(to_jsonb(x) order by id) from invoices x)) v");
 const caseContext=(rid,actor,sid)=>sharedCall(actor,sid,'select public.read_shared_daily_report_context($1) v',[rid]);
 async function legacyNullableCase(n,day,{admin=false}={}){
  await client.query("update company_members set role=$1 where company_id=$2 and user_id=$3",[admin?'owner':'worker',A,U]);
  await client.query("update company_members set role='worker' where company_id=$1 and user_id=$2",[A,memberB]);
  await mkShift(n,reportWorker,day);await mkShift(n+2,W2,day);
  const payload=JSON.stringify([worker(reportWorker,[days[0]],{work_category:null}),worker(W2,[],{work_category:null})]);
  const work='旧NULL勤務区分を本人確認後に正規化する合成作業';
  const idReport=await sharedCall(U,id(80),'select public.save_daily_report_destination_draft(null,$1,null,$2,$3,$4::jsonb) v',[SITE,day,work,payload]);
  await sharedCall(U,id(80),'select public.reuse_my_shared_daily_report($1) v',[id(n)]);
  await sharedCall(memberB,sidB,'select public.reuse_my_shared_daily_report($1) v',[id(n+2)]);
  let c=await caseContext(idReport,U,id(80));
  await sharedCall(U,id(80),'select public.submit_shared_daily_report($1,$2::timestamptz,$3,$4::jsonb,$5,$6::jsonb,$7) v',[id(n),c.report_updated_at,work,payload,'合成の実報告者',signature,c.signature_scope_fingerprint]);
  eq(await q('select bool_and(work_category is null) v from daily_report_workers where report_id=$1',[idReport]),true,'Reporter signed the existing NULL category source without silently changing it');
  // In the old enabled shared protocol, peers attach their own source when
  // resuming AFTER the first reporter save. A pre-sign read is not enrollment.
  await sharedCall(memberB,sidB,'select public.reuse_my_shared_daily_report($1) v',[id(n+2)]);
  for(const [wid,actor,sid] of [[reportWorker,U,id(80)],[W2,memberB,sidB]]){
   phase='nullable-case-confirm-'+(admin?'admin-':'ordinary-')+(wid===reportWorker?'reporter':'peer');
   const own=await sharedCall(actor,sid,'select public.read_shared_worker_facts($1,$2) v',[idReport,wid]);
   eq(own.editable,true,'Actual own-source confirmation ready '+JSON.stringify({blocked:own.source_blocked,reasons:own.source_reasons,kind:own.source_kind,own:own.own_worker,enrolling:own.enrollment_pending}));
   // A legacy NULL category deliberately makes proposed_worker_facts null.
   // Build the same explicit 11-field form as the client, preserving every
   // existing saved amount/choice/vehicle value and selecting day explicitly.
   const savedWorker=await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2',[idReport,wid]);
   const facts={schema:1,...Object.fromEntries(['overtime_hours','early_hours','night_hours',
    'allowance_amount','allowance_label','company_allowance_selections','vehicle_id',
    'route_assignment_id','odometer_km'].map(key=>[key,savedWorker[key]??null])),work_category:'day'};
   await sharedCall(actor,sid,'select public.confirm_shared_worker_facts($1,$2,$3::jsonb,$4,$5,$6) v',[idReport,wid,JSON.stringify(facts),own.required?8:null,own.revision,own.scope_fingerprint]);
  }
  eq(await q('select bool_and(work_category is null) v from daily_report_workers where report_id=$1',[idReport]),true,'Confirmations preserve the nullable signed source until trusted supervisor materialization');
  eq(await q("select bool_and(worker_facts->>'work_category'='day') v from checkout_shared_hours_private.confirmations where report_id=$1 and worker_id=any($2::uuid[])",[idReport,[reportWorker,W2]]),true,'Actual self-confirmation APIs saved explicit day facts');
  const actor=admin?U:memberB,sid=admin?id(80):sidB;
  c=await caseContext(idReport,actor,sid);
  eq(c.supervisor_ready,true,'Completed actual facts authorize supervisor capture');
  const request=admin?[idReport,'supervisor','合成の現場責任者',signature,c.report_updated_at,c.signature_scope_fingerprint]:[idReport,id(n+2),'合成の現場責任者',signature,c.report_updated_at,c.signature_scope_fingerprint];
  const rpc=admin?'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v':'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v';
  return {idReport,actor,sid,request,collect:()=>sharedCall(actor,sid,rpc,request)};
 }
 phase='baseline-null-category-confirmed-day-reproduces-refusal';
 const ordinaryCase=await legacyNullableCase(9800,'2026-10-23');
 phase='baseline-null-category-confirmed-day-reproduces-refusal';
 const beforeFailure=await business(),signatureBefore=await reportSignature(ordinaryCase.idReport);
 await reject(ordinaryCase.collect,/shared_report_signed_facts_require_approved_edit/);
 eq(await business(),beforeFailure,'Baseline failure rolls back materialization, signatures and financial writes');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.supervisor_contexts'),0,'Baseline failure leaves no reusable supervisor context');
 await reject(()=>client.query('update daily_report_workers set work_category=work_category where report_id=$1',[ordinaryCase.idReport]),/shared_report_signed_facts_require_approved_edit/);
 eq(await reportSignature(ordinaryCase.idReport),signatureBefore,'Baseline no-op failure also preserves reporter signature bytes');
 phase='minimal-root-fix-keeps-catalogue-permissions';
 await exec(await readFile(regressionRoot+'/fix.sql.review-only','utf8'));
 const patchedClearCatalog=await q("select to_jsonb(p) v from pg_proc p where oid='private.clear_daily_report_signatures_on_workers()'::regprocedure");
 for(const key of ['oid','proowner','proacl','proconfig','prosecdef','provolatile'])eq(patchedClearCatalog[key],originalClearCatalog[key],'Minimal replacement preserves function '+key);
 await client.query('update daily_report_workers set work_category=work_category where report_id=$1',[ordinaryCase.idReport]);
 eq(await reportSignature(ordinaryCase.idReport),signatureBefore,'No-op UPDATE preserves every reporter signature byte');
 await reject(()=>client.query("update daily_report_workers set work_category='night' where report_id=$1",[ordinaryCase.idReport]),/shared_report_roster_requires_approved_edit/);
 eq(await business(),beforeFailure,'Unpermitted signed-fact change still fails without changing source or finances');
 eq(await q("select has_table_privilege('authenticated','checkout_shared_hours_private.supervisor_contexts','INSERT,UPDATE,DELETE') v"),false,'Authenticated caller cannot mint materialization context');
 phase='ordinary-supervisor-success-and-exact-financial-retry';
 await ordinaryCase.collect();
 eq(await reportSignature(ordinaryCase.idReport),signatureBefore,'Ordinary capture preserves the genuine reporter signature bytes');
 eq(await q("select status='signed' and supervisor_signature_json is not null v from daily_reports where id=$1",[ordinaryCase.idReport]),true,'Actual ordinary supervisor capture completes the saved source');
 eq(await q("select bool_and(work_category='day') v from daily_report_workers where report_id=$1",[ordinaryCase.idReport]),true,'Only actual confirmed day facts are materialized');
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[ordinaryCase.idReport]),2,'One formal attendance per actual participant');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.ledger where report_id=$1',[ordinaryCase.idReport]),2,'One ledger projection per actual participant');
 const ordinaryFinancial=await financial();await ordinaryCase.collect();eq(await financial(),ordinaryFinancial,'Ordinary lost-ACK retry duplicates no attendance, ledger, payroll or invoice');
 phase='administrator-supervisor-success-without-permission-forgery';
 const adminCase=await legacyNullableCase(9820,'2026-10-24',{admin:true});
 const adminReporter=await reportSignature(adminCase.idReport);
 await adminCase.collect();
 eq(await reportSignature(adminCase.idReport),adminReporter,'Actual management RPC also preserves genuine reporter signature bytes');
 eq(await q("select status='signed' and supervisor_signature_json is not null v from daily_reports where id=$1",[adminCase.idReport]),true,'Actual authorized manager stores supervisor capture');
 const adminFinancial=await financial();await adminCase.collect();eq(await financial(),adminFinancial,'Management capture retry duplicates no financial projection');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.materialization_permits'),0,'Successful calls leave no reusable materialization permit');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.supervisor_contexts where transaction_id=txid_current()'),0,'Persistent audit contexts do not authorize a later transaction');
 phase='ordinary-legacy-edit-still-clears-consent';
 const legacyRid=await sharedCall(U,id(80),'select public.save_daily_report_destination_draft(null,$1,null,$2,$3,$4::jsonb) v',[SITE,'2020-10-02','通常旧日報の合成編集',JSON.stringify([worker(reportWorker,[])])]);
 const legacySign=()=>sharedCall(U,id(80),"select public.save_daily_report_signature($1,'representative','通常旧報告者',$2::jsonb) v",[legacyRid,signature]);
 await legacySign();await client.query('update daily_report_workers set overtime_hours=1 where report_id=$1',[legacyRid]);
 eq(await q('select representative_signature_json is null v from daily_reports where id=$1',[legacyRid]),true,'Unpermitted legacy work edit still invalidates old consent');
 await legacySign();await client.query('insert into daily_report_workers(report_id,worker_id,overtime_hours,early_hours,night_hours,allowance_amount) values($1,$2,0,0,0,0)',[legacyRid,W2]);
 eq(await q('select representative_signature_json is null v from daily_reports where id=$1',[legacyRid]),true,'Legacy INSERT still invalidates old consent');
 await legacySign();await client.query('delete from daily_report_workers where report_id=$1 and worker_id=$2',[legacyRid,W2]);
 eq(await q('select representative_signature_json is null v from daily_reports where id=$1',[legacyRid]),true,'Legacy DELETE still invalidates old consent');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,exact_legacy_after_trigger_inherited:true,previous_nullable_shape_uncovered:true,baseline_reproduced:true,ordinary_and_admin_actual_supervisor_capture:true,reporter_signature_bytes_preserved:true,untrusted_fact_edits_denied:true,real_financial_producers_and_retry:true,production_changed:false}));
`;
 const proof=join(folder,'proof.mjs');await writeFile(proof,prefix+unit+tail);
 if(process.env.SKO_SUPERVISOR_WORKER_EMIT_ONLY){await writeFile(process.env.SKO_SUPERVISOR_WORKER_EMIT_ONLY,prefix+unit+tail);}
 else {
  const run=spawnSync(process.execPath,[proof,process.argv[2]],{stdio:'inherit',env:{...process.env,
   SKO_ORDINARY_EXPLICIT_ROOT:ordinary,SKO_SUPERVISOR_WORKER_ROOT:here,
   SKO_DOCUMENT_CANDIDATE:resolve(here,'../supervisor-document-candidate/document-signature-and-edit.sql.review-only'),
   SKO_DOCUMENT_TRIGGER_PINS:resolve(here,'../supervisor-document-candidate/trigger-source-pins.json'),
   SKO_ADMIN_CANDIDATE:resolve(here,'../attendance-admin-override-candidate/attendance-admin-override.sql.review-only'),
   SKO_ADMIN_ORIGINALS:resolve(here,'../attendance-admin-override-candidate/native-original-sources.sql')}});
  if(run.error)throw run.error;process.exitCode=run.status??1;
 }
}finally{await rm(folder,{recursive:true,force:true});}
