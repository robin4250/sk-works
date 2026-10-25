// Focused native PG17 proof: reuse source-bound INSTALLERS, not old test cases.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const here=fileURLToPath(new URL('.',import.meta.url));
const base=await readFile('tool/verify_company_checkout_integration.mjs','utf8');
const extension=(await readFile('tool/verify_checkout_registration_source_chain.mjs','utf8')).split('const extension=String.raw`')[1]?.split('`;')[0];
assert.ok(extension);
const prefixEnd=" phase='old-legacy-original-and-new-typed-company-choice';";
assert.equal(base.split(prefixEnd).length,3,'Two original phase labels: only setup prefix is reused');
let setup=base.slice(0,base.indexOf(prefixEnd));
const authStart=' const reportWorker=W5;';
const authEnd=' // Exact observed production legacy body, no new vehicle foundation installed.';
assert.equal(extension.split(authStart).length,2);assert.equal(extension.split(authEnd).length,2);
setup+=extension.slice(extension.indexOf(authStart),extension.indexOf(authEnd));
const sharedSource=await readFile('tool/verify_shared_daily_report.mjs','utf8');
const sharedUnit=sharedSource.split('const addition=String.raw`')[1]?.split('`;')[0];
assert.ok(sharedUnit);
const actorStart=' await exec("create function private.has_company_feature';
const actorEnd=' await mkShift(8100';
assert.equal(sharedUnit.split(actorStart).length,2);assert.equal(sharedUnit.split(actorEnd).length,2);
setup+=sharedUnit.slice(sharedUnit.indexOf(actorStart),sharedUnit.indexOf(actorEnd));
const unit=String.raw`
 phase='document-only-exact-source-installers';
 await exec("create table private.vehicle_usage_rollout(company_id uuid,enabled boolean);alter table route_assignments add column route_name text;alter table public.daily_report_edit_requests add column company_id uuid;revoke insert,update,delete on public.daily_report_edit_requests from authenticated,anon;");
 const v2Sources=JSON.parse(await readFile('tool/fixtures/checkout_paid_hours_actual_sources.json','utf8'));
 for(const f of v2Sources.functions.filter(f=>/report_basis|\.aggregate\(|\.resolve\(|^sign_daily_report/.test(f.signature))){
  eq(md5(dbBody(f.definition)),f.source_md5,'Exact actual v2 producer input');await exec(f.definition);
 }
 await exec("create table if not exists private.route_journey_captures(id uuid,source_clock_in_id uuid);create table if not exists private.route_journey_visit_events(capture_id uuid,source_clock_in_id uuid,start_capture_id uuid,kind text,route_stop_id uuid);create table if not exists route_stops(id uuid,route_assignment_id uuid);");
 await exec(await readFile('docs/candidates/shared_daily_report.sql.review-only','utf8'));
 await exec(await readFile('docs/candidates/closed_day_paid_hours_scope.sql.review-only','utf8'));
 await exec(await readFile('docs/candidates/checkout_paid_hours_ledger.sql.review-only','utf8'));
 await exec(await readFile(process.env.SKO_PAID_HOURS_PATCHES,'utf8'));
 await exec(await readFile('docs/candidates/checkout_paid_hours_api.sql.review-only','utf8'));
 await exec(await readFile('docs/candidates/checkout_shared_worker_facts.sql.review-only','utf8'));
 await exec(await readFile('docs/candidates/checkout_shared_hours_v2.sql.review-only','utf8'));
 await exec(await readFile(process.env.SKO_SHARED_HOURS_V2_PATCHES,'utf8'));
 await exec(await readFile('docs/candidates/checkout_shared_hours_v2_api.sql.review-only','utf8'));
 await exec(await readFile('docs/candidates/shared_daily_report_approved_edit.sql.review-only','utf8'));
 await client.query("insert into shared_daily_report_private.rollout(company_id,starts_on,enabled) values($1,'2026-10-01',true)",[A]);
 await client.query("insert into checkout_shared_hours_private.rollout(company_id,starts_on,enabled) values($1,'2026-10-01',true)",[A]);
 const docDay='2026-10-26',docStart=id(9300);
 await mkShift(9300,reportWorker,docDay);await mkShift(9302,W2,docDay,false);
 const docRoster=JSON.stringify([worker(reportWorker,[days[0]]),worker(W2,[])]);
 const rid=await q('select public.save_daily_report_destination_draft(null,$1,null,$2,$3,$4::jsonb) v',[SITE,docDay,'保存済み手当を含む日報',docRoster]);
 const offBefore=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 const beforeInstall=await q("select jsonb_build_object('r',(select to_jsonb(r) from daily_reports r where id=$1),'w',(select jsonb_agg(to_jsonb(w) order by worker_id) from daily_report_workers w where report_id=$1),'settings',(select jsonb_agg(to_jsonb(s) order by worker_id) from worker_payroll_settings s)) v",[rid]);
 await exec(await readFile(process.env.SKO_DOCUMENT_CANDIDATE,'utf8'));
 eq(await q('select count(*)::int v from shared_daily_report_private.document_rollout'),0,'Installation is OFF and creates no company activation');
 eq(await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]),offBefore,'OFF context and finance readiness unchanged');
 eq(await q("select jsonb_build_object('r',(select to_jsonb(r) from daily_reports r where id=$1),'w',(select jsonb_agg(to_jsonb(w) order by worker_id) from daily_report_workers w where report_id=$1),'settings',(select jsonb_agg(to_jsonb(s) order by worker_id) from worker_payroll_settings s)) v",[rid]),beforeInstall,'OFF install preserves source records and settings');
 // Reproduce monthly pay type versus an already-saved daily selection exactly.
 await client.query("update worker_payroll_settings set pay_type='monthly' where company_id=$1 and worker_id=$2",[A,reportWorker]);
 await reject(()=>client.query('select company_checkout_allowance_private.registered_item($1,$2,$3::jsonb)',[A,reportWorker,JSON.stringify(days[0])]),/registration changed/);
 const financial=()=>q("select jsonb_build_object('attendance',(select coalesce(jsonb_agg(to_jsonb(a) order by id),'[]') from attendance_entries a),'payroll',(select coalesce(jsonb_agg(to_jsonb(s) order by worker_id,period_start),'[]') from payroll_statements s),'hours_ledger',(select coalesce(jsonb_agg(to_jsonb(l) order by id),'[]') from checkout_shared_hours_private.ledger l),'confirmations',(select coalesce(jsonb_agg(to_jsonb(c) order by id),'[]') from checkout_shared_hours_private.confirmations c),'settings',(select coalesce(jsonb_agg(to_jsonb(s) order by worker_id),'[]') from worker_payroll_settings s)) v");
 const financialBefore=await financial();
 const foreignSid=id(9399),otherEditorSid=id(9398);
 await client.query('insert into auth.users(id) values($1)',[OTHER]);
 await client.query('insert into auth.sessions(id,user_id) values($1,$2),($3,$4)',[foreignSid,OTHER,otherEditorSid,U]);
 await client.query("insert into shared_daily_report_private.document_rollout values($1,$2,'2026-10-01',true)",[A,rid]);
 await exec("select set_config('fixture.manager','on',false)");
 let context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 eq(context.document_only,true,'Explicit document mode without financial recalculation');
 eq(context.document_basis.workers.length,2,'Actual saved roster exposed for signature review');
 eq(context.document_basis.workers.find(w=>w.worker_id===reportWorker).company_allowance_selections.items[0].id,DAYS[0],'Daily selection source preserved despite current monthly salary');
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,'representative','実報告者',signature,context.report_updated_at,context.signature_scope_fingerprint]);
 await exec("select set_config('fixture.manager','off',false)");
 context=await sharedCall(U,id(80),'select public.read_my_shared_daily_report($1) v',[docStart]);
 eq(context.supervisor_ready,true,'Personal confirmations and open peer shift do not block document signature');
 eq(context.hours_annex,null,'Document scope does not call payroll annex calculator');
 eq(context.document_editable,true,'Original reporting actor can explicitly start a revision');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.confirmations where report_id=$1',[rid]),0,'No self confirmation fabricated');
 // Existing read_context intentionally conceals cross-company report existence.
 await reject(()=>sharedCall(OTHER,foreignSid,'select public.read_shared_daily_report_context($1) v',[rid]),{code:'42501',message:'shared_report_unavailable'});
 await reject(()=>sharedCall(memberB,sidB,'select public.start_shared_report_document_edit($1,$2::timestamptz,$3,$4) v',[rid,context.report_updated_at,context.signature_scope_fingerprint,'他の作業者による変更']),/reporter_or_manager/);
 await reject(()=>sharedCall(U,id(80),'select public.start_shared_report_document_edit($1,$2::timestamptz,$3,$4) v',[rid,context.report_updated_at,'stale-scope','理由']),/signature_scope_changed/);
 // Owner SQL is not an authenticated application call; assert that boundary separately.
 await reject(()=>client.query("update daily_report_workers set overtime_hours=2 where report_id=$1 and worker_id=$2",[rid,reportWorker]),{code:'42501',message:'checkout_report_actor_access_unavailable'});
 // Isolated SECURITY DEFINER surrounding models a legacy trusted writer without
 // granting direct table UPDATE or changing any production guard/ACL.
 await exec("create function public.fixture_document_roster_attempt(rid uuid,wid uuid) returns void language sql security definer set search_path='' as $$update public.daily_report_workers set overtime_hours=2 where report_id=rid and worker_id=wid$$;revoke all on function public.fixture_document_roster_attempt(uuid,uuid) from public;grant execute on function public.fixture_document_roster_attempt(uuid,uuid) to authenticated;");
 await reject(()=>sharedCall(U,id(80),'select public.fixture_document_roster_attempt($1,$2) v',[rid,reportWorker]),{code:'55000',message:'document_roster_requires_explicit_edit_writer'});
 await sharedCall(U,id(80),'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,docStart,'実現場責任者',signature,context.report_updated_at,context.signature_scope_fingerprint]);
 let completed=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 eq(completed.document_complete,true,'Actual supervisor strokes complete the document');
 eq(completed.report_status,'draft','Document completion is not financial signed status');
 eq(completed.document_editable,true,'Document-complete draft may enter a recorded explicit correction');
 eq(await financial(),financialBefore,'Document signatures preserve entries, payroll, ledger, confirmations and settings');
 const eventCount=await q('select count(*)::int v from shared_daily_report_private.signature_events where report_id=$1',[rid]);
 eq((await sharedCall(U,id(80),'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,docStart,'実現場責任者',signature,context.report_updated_at,context.signature_scope_fingerprint])).state,'already_saved','Exact duplicate saves no new signature');
 eq(await q('select count(*)::int v from shared_daily_report_private.signature_events where report_id=$1',[rid]),eventCount,'Duplicate retry does not append a second event');
 await reject(()=>sharedCall(U,id(80),"select public.sign_daily_report($1,'偽の給与確定',$2::jsonb) v",[rid,signature]),/document_only|confirmation|pending|registration changed/);
 eq(await financial(),financialBefore,'Old financial entry point cannot bypass confirmations');
 const historyBefore=await q('select jsonb_agg(to_jsonb(e) order by id) v from shared_daily_report_private.signature_events e where report_id=$1',[rid]);
 const edited=await sharedCall(U,id(80),'select public.start_shared_report_document_edit($1,$2::timestamptz,$3,$4) v',[rid,completed.report_updated_at,completed.signature_scope_fingerprint,'作業内容を手直しして再署名']);
 eq(edited.reporter_saved,false,'Explicit edit clears reporter signature');eq(edited.supervisor_saved,false,'Explicit edit clears supervisor signature');
 eq(edited.document_complete,false,'Prior document signature cannot complete revised work');
 eq(await q('select count(*)::int v from shared_report_edit_private.document_edit_permits'),0,'Permit is transaction-local and removed before commit');
 const cleared=await q("select jsonb_agg(to_jsonb(e) order by id) v from shared_daily_report_private.signature_events e where report_id=$1 and event='cleared'",[rid]);
 eq(cleared.length,2,'Both signature clear events recorded');
 eq(cleared.every(e=>e.signature_snapshot!==null&&e.prior_report.supervisor_signature_json!==null&&e.prior_roster.length===2&&e.edit_reason==='作業内容を手直しして再署名'),true,'Original strokes, report, roster and reason preserved');
 eq(await q('select jsonb_agg(to_jsonb(e) order by id) v from shared_daily_report_private.signature_events e where report_id=$1 and id=any($2::bigint[])',[rid,historyBefore.map(e=>e.id)]),historyBefore,'Prior audit rows remain byte-identical');
 eq(await financial(),financialBefore,'Editing permission resets no financial source or attestation');
 await reject(()=>sharedCall(U,id(80),'select public.start_shared_report_document_edit($1,$2::timestamptz,$3,$4) v',[rid,completed.report_updated_at,completed.signature_scope_fingerprint,'再送']),/reporter_or_manager|scope_changed/);
 eq(await q("select has_table_privilege('authenticated','shared_report_edit_private.document_edit_permits','insert,update,delete') v"),false,'Client cannot forge reset permits');
 // A corrected report must receive new actual signatures. No old signature copy.
 const correctedRoster=JSON.stringify([worker(reportWorker,[days[0]],{overtime_hours:1.25}),worker(W2,[])]);
 await reject(()=>sharedCall(U,otherEditorSid,'select public.save_shared_report_document_draft($1,$2::timestamptz,$3,$4,$5::jsonb) v',[rid,edited.report_updated_at,edited.signature_scope_fingerprint,'別sessionでは編集不可',correctedRoster]),/actor/);
 const savedDoc=await sharedCall(U,id(80),'select public.save_shared_report_document_draft($1,$2::timestamptz,$3,$4,$5::jsonb) v',[rid,edited.report_updated_at,edited.signature_scope_fingerprint,'明示的に手直しした本文',correctedRoster]);
 eq(savedDoc.document_basis.report.work_description,'明示的に手直しした本文','Document writer persists explicit corrected description');
 eq(savedDoc.document_basis.workers.find(w=>w.worker_id===reportWorker).overtime_hours,1.25,'Explicit quantity persists without changing existing pay category');
 eq(savedDoc.document_basis.workers.find(w=>w.worker_id===reportWorker).company_allowance_selections.items[0].id,DAYS[0],'Unchanged stale selection stays a raw saved value, never repriced');
 await reject(()=>sharedCall(U,id(80),'select public.save_shared_report_document_draft($1,$2::timestamptz,$3,$4,$5::jsonb) v',[rid,savedDoc.report_updated_at,savedDoc.signature_scope_fingerprint,'手当を変えた場合は再検証',JSON.stringify([worker(reportWorker,[days[1]]),worker(W2,[])])]),/registration changed/);
 await reject(()=>sharedCall(U,id(80),'select public.save_shared_report_document_draft($1,$2::timestamptz,$3,$4,$5::jsonb) v',[rid,savedDoc.report_updated_at,savedDoc.signature_scope_fingerprint,'数量範囲の拒否',JSON.stringify([worker(reportWorker,[days[0]],{overtime_hours:25}),worker(W2,[])])]),/quantity_out_of_range/);
 await reject(()=>sharedCall(U,id(80),'select public.save_shared_report_document_draft($1,$2::timestamptz,$3,$4,$5::jsonb) v',[rid,savedDoc.report_updated_at,savedDoc.signature_scope_fingerprint,'金額変更拒否',JSON.stringify([worker(reportWorker,[days[0]],{allowance_amount:1000}),worker(W2,[])])]),/amount_or_label/);
 await exec("select set_config('fixture.manager','on',false)");
 context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 await sharedCall(U,id(80),'select public.submit_shared_daily_report($1,$2::timestamptz,$3,$4::jsonb,$5,$6::jsonb,$7) v',[docStart,context.report_updated_at,'明示的に手直しした本文',correctedRoster,'再署名報告者',signature,context.signature_scope_fingerprint]);
 context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 await sharedCall(memberC,sidC,'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,'supervisor','再署名責任者',signature,context.report_updated_at,context.signature_scope_fingerprint]);
 eq((await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid])).document_complete,true,'Fresh signatures finish the corrected document');
 eq(await financial(),financialBefore,'Correction and re-signing never finalize financial rows');
 console.log(JSON.stringify({pass:true,checks,scope:'document-only-signature-and-revision',native_pg17:true,actual_source_writers:true,unchanged_broad_suites_replayed:false,synthetic_auth:true,production_changed:false}));
`;
const tail=base.slice(base.indexOf('}catch(error){'));
const folder=await mkdtemp(join(tmpdir(),'document-only-native-'));
try {
 const script=join(folder,'proof.mjs');await writeFile(script,setup+unit+tail);
 if(process.env.SKO_DOCUMENT_EMIT_ONLY){
  await writeFile(process.env.SKO_DOCUMENT_EMIT_ONLY,setup+unit+tail);
 }else{
  const result=spawnSync(process.execPath,[script,process.argv[2]],{stdio:'inherit',env:{...process.env,SKO_DOCUMENT_CANDIDATE:resolve(here,'document-signature-and-edit.sql.review-only')}});
  if(result.error)throw result.error;process.exitCode=result.status??1;
 }
}finally{await rm(folder,{recursive:true,force:true});}
