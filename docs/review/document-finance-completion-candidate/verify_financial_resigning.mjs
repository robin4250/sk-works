// Focused PG17: explicit unsigned transition, real re-sign, unchanged source triggers.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const here=fileURLToPath(new URL('.',import.meta.url)),admin=resolve(here,'../attendance-admin-override-candidate'),doc=resolve(here,'../supervisor-document-candidate');
const folder=await mkdtemp(join(tmpdir(),'document-finance-resigning-'));
try{
 const bootstrap=join(folder,'admin-bootstrap.mjs');
 const emitted=spawnSync(process.execPath,[resolve(admin,'verify_admin_override.mjs')],{stdio:'inherit',env:{...process.env,SKO_ADMIN_EMIT_ONLY:bootstrap}});
 assert.equal(emitted.status,0);
 const original=await readFile(bootstrap,'utf8'),marker=" eq(await q('select count(*)::int v from attendance_admin_override_private.rollout'),0,";
 assert.equal(original.split(marker).length,2);
 const setup=original.slice(0,original.indexOf(marker)),tail=original.slice(original.indexOf('}catch(error){'));
 const unit=String.raw`
 phase='document-finance-resigning-default-off';
 const vehicleSource=JSON.parse(await readFile('tool/fixtures/shared_worker_facts_sources.json','utf8')).functions.find(f=>f.signature==='private.save_daily_report_vehicle_usage(uuid,uuid,uuid,uuid,numeric)');
 eq(md5(dbBody(vehicleSource.definition)),vehicleSource.source_md5,'Exact observed legacy vehicle validator dependency');await exec(vehicleSource.definition);
 const snapshot=()=>q("select jsonb_build_object('clocks',(select jsonb_agg(to_jsonb(a) order by id) from attendance_verifications a),'reports',(select jsonb_agg(to_jsonb(r) order by id) from daily_reports r),'workers',(select jsonb_agg(to_jsonb(w) order by report_id,worker_id) from daily_report_workers w),'events',(select jsonb_agg(to_jsonb(e) order by id) from shared_daily_report_private.signature_events e),'protocol',(select jsonb_agg(to_jsonb(p) order by report_id) from checkout_shared_hours_private.work_protocol p),'confirmations',(select jsonb_agg(to_jsonb(c) order by id) from checkout_shared_hours_private.confirmations c),'ledger',(select jsonb_agg(to_jsonb(l) order by id) from checkout_shared_hours_private.ledger l),'entries',(select jsonb_agg(to_jsonb(a) order by id) from attendance_entries a),'payroll',(select jsonb_agg(to_jsonb(s) order by worker_id,period_start) from payroll_statements s),'settings',(select jsonb_agg(to_jsonb(s) order by worker_id) from worker_payroll_settings s)) v");
 const originalSignatures=['shared_daily_report_private.guard_roster()','shared_worker_facts_private.materialize_confirmed_worker(uuid,uuid,jsonb)','shared_daily_report_private.read_context(uuid)','shared_daily_report_private.resolve_own(uuid)'];
 const originalDefinitions=await q("select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid)) order by p.oid) v from pg_proc p where p.oid=any($1::regprocedure[])",[originalSignatures]);
 const routineCatalog=()=>q("select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'owner',p.proowner::regrole::text,'acl',p.proacl,'config',p.proconfig,'definer',p.prosecdef) order by p.oid) v from pg_proc p where p.oid=any($1::regprocedure[])",[[...originalSignatures,'private.clear_daily_report_signatures_on_workers()']]);
 const triggerCatalog=()=>q("select jsonb_agg(jsonb_build_object('name',tgname,'definition',pg_get_triggerdef(oid),'enabled',tgenabled) order by oid) v from pg_trigger where tgrelid in('public.daily_reports'::regclass,'public.daily_report_workers'::regclass) and not tgisinternal");
 const routinesBeforeInstall=await routineCatalog(),triggersBeforeInstall=await triggerCatalog();
 const transitionBeforeInstall=await snapshot();
 await exec(await readFile(process.env.SKO_FINANCE_TRANSITION_CANDIDATE,'utf8'));
 eq(await snapshot(),transitionBeforeInstall,'Default OFF installation preserves all source/financial rows');
 eq(await q('select count(*)::int v from document_finance_completion_private.rollout'),0,'Installer activates nothing');
 const initialContext=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 eq(initialContext.financial_resigning_supported,false,'Default OFF context cannot authorize signature reset');
 eq(initialContext.financial_transition_id??null,null,'Unprepared report never claims staged facts');
 // Independent OFF/unused restoration. Never uninstall a used transition.
 eq(await q('select count(*)::int v from document_finance_completion_private.transitions'),0,'Unused restore requires zero transition audit rows');
 eq(await q('select count(*)::int v from document_finance_completion_private.worker_permits'),0,'Unused restore requires zero permits');
 for(const original of originalDefinitions)await exec(original.definition);
 await exec('drop function public.prepare_shared_report_financial_resigning(uuid,timestamptz,text,jsonb,text);drop schema document_finance_completion_private cascade;');
 eq(await routineCatalog(),routinesBeforeInstall,'Unused restore retains exact four original definitions, owner, config, SECURITY DEFINER and ACL');
 eq(await triggerCatalog(),triggersBeforeInstall,'Unused restore preserves exact signature trigger definitions and enablement');
 eq(await snapshot(),transitionBeforeInstall,'Unused restore preserves all clock/report/signature/financial/settings data');
 eq(await q("select to_regprocedure('public.prepare_shared_report_financial_resigning(uuid,timestamptz,text,jsonb,text)') is null and not exists(select 1 from pg_namespace where nspname='document_finance_completion_private') v"),true,'Unused RPC/private schema fully removed');
 await exec(await readFile(process.env.SKO_FINANCE_TRANSITION_CANDIDATE,'utf8'));
 eq(await snapshot(),transitionBeforeInstall,'Exact-source guarded reinstall after unused restore changes no existing data');

 await exec("select set_config('fixture.manager','on',false)");
 const makeItem=async(wid,changes={})=>{
  const w=await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2',[rid,wid]);
  const state=await sharedCall(U,id(80),'select public.read_shared_worker_facts($1,$2) v',[rid,wid]);
  const keys=['overtime_hours','early_hours','night_hours','work_category','allowance_amount','allowance_label','company_allowance_selections','vehicle_id','route_assignment_id','odometer_km'];
  return {worker_id:wid,facts:{schema:1,...Object.fromEntries(keys.map(k=>[k,w[k]])),...changes},hours:null,expected_revision:state.revision,expected_scope:state.scope_fingerprint};
 };
 const prepare=async(items,{scope,reason='管理者が実際の勤務区分・手当を確認し、旧日報を手直しして新たにサインをもらう'}={})=>{
  const context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
  return sharedCall(U,id(80),'select public.prepare_shared_report_financial_resigning($1,$2::timestamptz,$3,$4::jsonb,$5) v',[rid,context.report_updated_at,scope??context.signature_scope_fingerprint,JSON.stringify(items),reason]);
 };
 await reject(async()=>prepare([await makeItem(reportWorker),await makeItem(W2)]),{code:'55000',message:'document_finance_transition_disabled'});
 // Actual historical NULL/day-pay selection against current monthly settings.
 await client.query("update worker_payroll_settings set pay_type='monthly' where company_id=$1 and worker_id=$2",[A,reportWorker]);
 await client.query('update daily_report_workers set work_category=null where report_id=$1 and worker_id=$2',[rid,reportWorker]);
 await client.query("insert into shared_daily_report_private.document_rollout values($1,$2,'2026-10-01',true)",[A,rid]);
 await client.query('insert into document_finance_completion_private.rollout values($1,$2,true)',[A,rid]);
 let context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 eq(context.financial_resigning_supported,true,'Exact enabled manager/document context advertises deployed transition');
 eq(context.financial_transition_id??null,null,'Capability does not imply a prepared transition');
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,'representative','旧日報の実報告者',signature,context.report_updated_at,context.signature_scope_fingerprint]);
 context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,'supervisor','旧日報の実責任者',signature,context.report_updated_at,context.signature_scope_fingerprint]);
 const signedBefore=await snapshot();
 await reject(async()=>prepare([await makeItem(reportWorker),await makeItem(W2)]),{code:'55000',message:'document_finance_explicit_unsigned_revision_required'});
 eq(await snapshot(),signedBefore,'No hidden reuse of old document signatures');
 eq(await q('select count(*)::int v from document_finance_completion_private.transitions'),0,'Rejected signed conversion has no success audit');
 await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,work_date,source_clock_in_id) values($1,$2,$3,$4,'clock_out',$5::date+time '17:00',$5,$6)",[id(9303),A,W2,SITE,docDay,id(9302)]);
 // Bind each synthetic owner's exact completed source using the original app API.
 await sharedCall(U,id(80),'select public.reuse_my_shared_daily_report($1) v',[docStart]);
 await sharedCall(memberB,sidB,'select public.reuse_my_shared_daily_report($1) v',[id(9302)]);
 phase='explicit-real-revision-and-typed-input-holds';
 context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 await sharedCall(U,id(80),'select public.start_shared_report_document_edit($1,$2::timestamptz,$3,$4) v',[rid,context.report_updated_at,context.signature_scope_fingerprint,'金融連携前に実際の勤務区分と手当を手直しする']);
 const unsignedBefore=await snapshot();
 await reject(async()=>prepare([await makeItem(reportWorker),await makeItem(W2)]),{code:'22023',message:'explicit_shared_worker_category_required'});
 eq(await snapshot(),unsignedBefore,'No inferred day category or partial mutation');
 await reject(async()=>prepare([await makeItem(reportWorker,{work_category:'day'}),await makeItem(W2)]),{code:'40001',message:'company allowance registration changed; reload report choices'});
 eq(await snapshot(),unsignedBefore,'Invalid saved registration is preserved, not repriced or dropped automatically');
 // The SYNTHETIC manager explicitly removes an inapplicable choice in input.
 // Production does not perform that choice; the user must select actual data.
 const explicitChanges={work_category:'day',company_allowance_selections:{contract_version:1,items:[]},allowance_label:null};
 // A synthetic lost source-link scenario must hold the whole writer, independently of UI readiness.
 await client.query('update attendance_verifications set daily_report_id=null where id=$1',[id(9303)]);
 const unboundBefore=await snapshot();
 await reject(async()=>prepare([await makeItem(reportWorker,explicitChanges),await makeItem(W2,{allowance_label:null})]),{code:'55000',message:'document_finance_closed_clocked_source_required'});
 eq(await snapshot(),unboundBefore,'Unbound peer source holds entire batch before any worker update');
 await client.query('update attendance_verifications set daily_report_id=$1 where id=$2',[rid,id(9303)]);
 const payload=[await makeItem(reportWorker,explicitChanges),await makeItem(W2,{allowance_label:null})];
 const beforeTransition=await snapshot();
 await reject(()=>prepare(payload,{scope:'stale-document-scope'}),{code:'40001',message:'shared_report_signature_scope_changed'});
 const stalePayload=structuredClone(payload);stalePayload[0].expected_scope='stale-source-scope';
 await reject(()=>prepare(stalePayload),{code:'PT409',message:'paid_hours_input_conflict'});
 eq(await snapshot(),beforeTransition,'Both document and individual source CAS are enforced');
 const result=await prepare(payload);
 eq(result.new_actual_reporter_and_supervisor_signatures_required,true,'Transition explicitly requires new actual signatures');
 eq(result.document_only??false,false,'Transition returns normal v2, not document-only');
 eq(result.financial_transition_valid,true,'Fresh transition exposes matching persisted facts');
 const reopened=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 eq(reopened.financial_transition_id,result.financial_transition_id,'Reopened context retains transition after app restart');
 eq(reopened.financial_transition_valid,true,'Reopened context validates exact staged rows');
 const sourceReopened=await sharedCall(U,id(80),'select public.read_my_shared_daily_report($1) v',[docStart]);
 eq(sourceReopened.financial_transition_id,result.financial_transition_id,'Source-anchor reopen retains the same staged transition');
 eq(sourceReopened.financial_transition_valid,true,'Source-anchor context validates exact staged facts');
 eq(sourceReopened.source_clock_in_id,docStart,'Source-anchor context preserves actual own-source identity');
 eq(reopened.financial_resigning_supported,false,'Prepared normal report cannot reset document signatures again');
 const unrelatedRid=await draft('2026-10-19',reportWorker,[]);
 const unrelatedContext=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[unrelatedRid]);
 eq(unrelatedContext.financial_transition_id??null,null,'Other report never inherits the staged transition marker');
 eq(unrelatedContext.financial_resigning_supported,false,'Other report never inherits enabled completion rollout');
 await client.query('update document_finance_completion_private.rollout set enabled=false where report_id=$1',[rid]);
 const disabledPrepared=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 eq(disabledPrepared.financial_transition_id,result.financial_transition_id,'Disabling rollout cannot hide staged marker and re-enable legacy writer');
 eq(disabledPrepared.financial_transition_valid,false,'Disabled prepared transition fails closed');
 await client.query('update document_finance_completion_private.rollout set enabled=true where report_id=$1',[rid]);
 eq(await q("select representative_signature_json is null and supervisor_signature_json is null and signature_json is null and status='draft' v from daily_reports where id=$1",[rid]),true,'No signatures or financial status are fabricated');
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[rid]),0,'No financial projection before new real signatures');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.ledger where report_id=$1',[rid]),0,'No ledger before new real signatures');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.confirmations where report_id=$1',[rid]),2,'Explicit management confirmation uses actual existing writer');
 eq(await q('select count(*)::int v from document_finance_completion_private.transitions where report_id=$1 and state=\'ready_for_real_signatures\'',[rid]),1,'Actor/session/reason/source before-state transition audit committed');
 eq(await q('select count(*)::int v from document_finance_completion_private.worker_permits'),0,'No reusable worker permit');
 eq(await q('select work_category v from daily_report_workers where report_id=$1 and worker_id=$2',[rid,reportWorker]),'day','Category comes from explicit input');
 eq(await q('select pay_type v from worker_payroll_settings where worker_id=$1',[reportWorker]),'monthly','Actual salary type is not changed to make old allowance valid');
 eq(await q('select count(*)::int v from shared_daily_report_private.signature_events where report_id=$1 and event=\'cleared\' and signature_snapshot is not null',[rid]),2,'Old actual signatures stay in existing reset history');
 phase='existing-financial-writer-with-observed-clear-triggers';
 context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,'representative','新たな実報告者',signature,context.report_updated_at,context.signature_scope_fingerprint]);
 const reporter=await q('select representative_signature_json v from daily_reports where id=$1',[rid]);
 context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 eq(context.hours_annex.ready,true,'New reporter epoch adopts the newly explicit confirmations');
 eq(await q('select checkout_report_registration_private.inputs_complete($1) v',[rid]),true,'Actual complete-input validator retains all legacy source dependency checks');
 eq(await q("select bool_and(document_finance_completion_private.allow_identical_materialization(w.report_id,w.worker_id,to_jsonb(w),c.worker_facts)) v from daily_report_workers w join checkout_shared_hours_private.confirmations c on c.report_id=w.report_id and c.worker_id=w.worker_id where w.report_id=$1",[rid]),true,'Staged raw facts exactly qualify for scoped no-op materialization');
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,'supervisor','新たな実責任者',signature,context.report_updated_at,context.signature_scope_fingerprint]);
 eq(await q('select status v from daily_reports where id=$1',[rid]),'signed','Existing writer performs actual finalization');
 const finalizedContext=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 eq(finalizedContext.financial_transition_id??null,null,'Finalized normal report does not advertise pending re-sign');
 eq(await q('select representative_signature_json v from daily_reports where id=$1',[rid]),reporter,'Identical staged materialization does not trigger signature clearing');
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[rid]),2,'Exactly one formal attendance entry per actual roster member');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.ledger where report_id=$1',[rid]),2,'Existing v2 writer creates actual confirmation-bound ledgers');
 eq(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,reportWorker]),'1','Existing salary projection counts the explicitly repaired monthly worker day once');
 eq(await q("select (detail->>'出勤日数')::numeric v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,W2]),'1','Existing salary projection counts the other roster member day once');
 const completeBefore=await snapshot();
 context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,'supervisor','新たな実責任者',signature,context.report_updated_at,context.signature_scope_fingerprint]);
 eq(await snapshot(),completeBefore,'Identical signature retry does not duplicate attendance/payment facts');
 eq(await q("select has_function_privilege('anon','public.prepare_shared_report_financial_resigning(uuid,timestamptz,text,jsonb,text)','execute') v"),false,'No anonymous transition endpoint');
 eq(await q("select has_schema_privilege('authenticated','document_finance_completion_private','usage') v"),false,'Audit/private permits unexposed');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,unused_restore_verified:true,explicit_revision_and_real_resigning:true,existing_financial_writers:true,original_clear_trigger_unmodified:true,unchanged_old_suites_replayed:false,production_changed:false}));
`;
 const proof=join(folder,'proof.mjs');await writeFile(proof,setup+unit+tail);
 if(process.env.SKO_FINANCE_TRANSITION_EMIT_ONLY)await writeFile(process.env.SKO_FINANCE_TRANSITION_EMIT_ONLY,setup+unit+tail);
 else{
  const result=spawnSync(process.execPath,[proof,process.argv[2]],{stdio:'inherit',env:{...process.env,SKO_DOCUMENT_CANDIDATE:resolve(doc,'document-signature-and-edit.sql.review-only'),SKO_DOCUMENT_TRIGGER_PINS:resolve(doc,'trigger-source-pins.json'),SKO_ADMIN_CANDIDATE:resolve(admin,'attendance-admin-override.sql.review-only'),SKO_ADMIN_ORIGINALS:resolve(admin,'native-original-sources.sql'),SKO_FINANCE_TRANSITION_CANDIDATE:resolve(here,'financial-resigning-transition.sql.review-only')}});
  if(result.error)throw result.error;process.exitCode=result.status??1;
 }
}finally{await rm(folder,{recursive:true,force:true});}

