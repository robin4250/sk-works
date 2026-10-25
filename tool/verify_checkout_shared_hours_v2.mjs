// Review-only v2 proof, composed AFTER all existing shared/report/payroll cases.
// Synthetic authentication surrounds original deployed writer definitions.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const original=await readFile('tool/verify_shared_daily_report.mjs','utf8');
const marker=' console.log(JSON.stringify({pass:true,shared_report_actual_save_sign:true,normal_member_and_management_separate:true,real_gotrue:false,production_changed:false}));';
assert.equal(original.split(marker).length,2,'Exact end of independent shared-report suite');
const addition=String.raw`
 phase='versioned-work-consent-and-individual-hours-annex';
 for(const [signature,expected]of Object.entries(pins.after_source_md5))eq(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',[signature]),expected,'Original parent source pins hold before explicit hours-v2 composition');
 const v2HoursSources=JSON.parse(await readFile('tool/fixtures/checkout_paid_hours_actual_sources.json','utf8'));
 const v2ClockSources=JSON.parse(await readFile('tool/fixtures/closed_day_actual_clock_sources.json','utf8'));
 const v2Protected=await q("select jsonb_build_object('settings',(select jsonb_agg(to_jsonb(s) order by worker_id) from worker_payroll_settings s),'old_reports',(select jsonb_agg(to_jsonb(r) order by id) from daily_reports r),'old_roster',(select jsonb_agg(to_jsonb(w) order by report_id,worker_id) from daily_report_workers w)) v");
 for(const source of v2HoursSources.functions.filter(f=>/report_basis|\.aggregate\(|\.resolve\(|^sign_daily_report/.test(f.signature))){
  eq(md5(dbBody(source.definition)),source.source_md5,'V2 starts from exact existing hour-producer source');
  await exec(source.definition);
 }
 await exec('create table if not exists private.route_journey_captures(id uuid,source_clock_in_id uuid);create table if not exists private.route_journey_visit_events(capture_id uuid,source_clock_in_id uuid,start_capture_id uuid,kind text,route_stop_id uuid);create table if not exists route_stops(id uuid,route_assignment_id uuid);');
 await exec(v2ClockSources.functions.find(f=>f.signature==='private.validate_attendance_shift_evidence()').definition);
 await exec('create trigger v2_fixture_real_clock_guard before insert or update on attendance_verifications for each row execute function private.validate_attendance_shift_evidence()');
 await exec(await readFile('docs/candidates/closed_day_paid_hours_scope.sql.review-only','utf8'));
 await exec(await readFile('docs/candidates/checkout_paid_hours_ledger.sql.review-only','utf8'));
 await exec(await readFile(process.env.SKO_PAID_HOURS_PATCHES,'utf8'));
 await exec(await readFile('docs/candidates/checkout_paid_hours_api.sql.review-only','utf8'));
 await exec(await readFile('docs/candidates/checkout_shared_worker_facts.sql.review-only','utf8'));
 const v2LegacyBodies=await q("select jsonb_object_agg(oid::regprocedure::text,md5(prosrc)) v from pg_proc where pronamespace in('company_checkout_allowance_private'::regnamespace,'checkout_paid_hours_candidate_private'::regnamespace)");
 await exec(await readFile('docs/candidates/checkout_shared_hours_v2.sql.review-only','utf8'));
 await exec(await readFile(process.env.SKO_SHARED_HOURS_V2_PATCHES,'utf8'));
 await exec(await readFile('docs/candidates/checkout_shared_hours_v2_api.sql.review-only','utf8'));
 // The parent proof resumes after this extension. Keep its complete source
 // preservation check, replacing only the three source-pinned, intentional
 // connection bodies with hashes independently derived from exact generated SQL.
 const v2ExpectedBodies=new Map();
 for(const script of [process.env.SKO_PAID_HOURS_PATCHES,process.env.SKO_SHARED_HOURS_V2_PATCHES]){
  const sql=await readFile(script,'utf8');
  const definitions=/^create(?: or replace)? function\s+([a-z0-9_.]+)\([\s\S]*?\bAS\s+(\$[a-z0-9_]*\$)([\s\S]*?)\2\s*;/gmi;
  for(const definition of sql.matchAll(definitions))v2ExpectedBodies.set(definition[1].toLowerCase(),md5(definition[3]));
 }
 const v2AllowedConnections=new Set(['public.sign_daily_report','company_checkout_allowance_private.report_basis','company_checkout_allowance_private.resolve']);
 let v2UpdatedPins=0;
 for(const signature of Object.keys(pins.after_source_md5)){
  const rawName=signature.split('(')[0],name=rawName.includes('.')?rawName:'public.'+rawName;
  if(!v2AllowedConnections.has(name))continue;
  assert.ok(v2ExpectedBodies.has(name),'Every allowed connection has an independently generated exact body');
  eq(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',[signature]),v2ExpectedBodies.get(name),'Installed intended connection matches exact generated SQL');
  pins.after_source_md5[signature]=v2ExpectedBodies.get(name);v2UpdatedPins++;
 }
 eq(v2UpdatedPins,3,'Only the three intentional original connection functions receive new expected pins');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.work_protocol'),0,'V2 installation never converts v1 or shared history');
 await client.query("insert into checkout_shared_hours_private.rollout(company_id,starts_on,enabled) values($1,'2026-10-01',true)",[A]);
 const v2Day='2026-10-20';
 const v2StartA=id(8900),v2EndA=id(8901),v2StartB=id(8902),v2EndB=id(8903);
 await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at) values($1,$2,$3,$4,'clock_in',$5::timestamptz)",[v2StartA,A,reportWorker,SITE,v2Day+'T08:00:00+09:00']);
 await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id) values($1,$2,$3,$4,'clock_out',$5::timestamptz,$6)",[v2EndA,A,reportWorker,SITE,v2Day+'T17:00:00+09:00',v2StartA]);
 await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at) values($1,$2,$3,$4,'clock_in',$5::timestamptz)",[v2StartB,A,W2,SITE,v2Day+'T08:00:00+09:00']);
 const v2Roster=JSON.stringify([worker(reportWorker,[]),worker(W2,[])]);
 const v2Draft=await sharedCall(U,id(80),'select public.save_daily_report_destination_draft(null,$1,null,$2,$3,$4::jsonb) v',[SITE,v2Day,'凍結する共同作業',v2Roster]);
 const v2Preview=await sharedCall(U,id(80),'select public.read_checkout_paid_work_hours($1,$2) v',[v2Draft,W2]);
 const v2OwnPreview=await sharedCall(U,id(80),'select public.read_checkout_paid_work_hours($1,$2) v',[v2Draft,reportWorker]);
 eq(v2Preview.contract_version,2,'Authoritative preview avoids missing-hours/first-work-sign cycle');
 eq(v2Preview.enrollment_pending,true,'Preview is not a consent enrollment');
 eq(v2Preview.first_reporter_covers_work_only,true,'Preview explicitly names limited work consent');
 eq(v2Preview.editable,false,'Preview cannot confirm facts before actual enrollment');
 eq(await q('select count(*)::int v from checkout_shared_hours_private.work_protocol'),0,'Reading preview never creates protocol state');
 const v2FirstContext=await sharedCall(U,id(80),'select public.read_my_shared_daily_report($1) v',[v2StartA]);
 const v2First=await sharedCall(U,id(80),'select public.submit_shared_daily_report($1,$2::timestamptz,$3,$4::jsonb,$5,$6::jsonb,$7) v',[v2StartA,v2FirstContext.report_updated_at,'凍結する共同作業',v2Roster,'先着作業報告者',signature,v2FirstContext.signature_scope_fingerprint]);
 const v2Rid=v2First.report_id;
 eq(await q('select checkout_shared_hours_private.uses_contract($1) v',[v2Rid]),true,'Only newly submitted report explicitly enrolls v2 before first signature');
 const v2Frozen=await q("select jsonb_build_object('report',to_jsonb(r),'roster',(select jsonb_agg(to_jsonb(w) order by worker_id) from daily_report_workers w where report_id=r.id)) v from daily_reports r where id=$1",[v2Rid]);
 const v2Pending=await sharedCall(memberB,sidB,'select public.read_shared_daily_report_context($1) v',[v2Rid]);
 eq(v2Pending.hours_annex.enabled,true,'Shared context includes authoritative v2 annex');
 eq(v2Pending.hours_annex.ready,false,'First work signature never invents still-working peer hours');
 await reject(()=>sharedCall(memberB,sidB,'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[v2Rid,v2StartB,'未確認責任者',signature,v2Pending.report_updated_at,v2Pending.signature_scope_fingerprint]),/not_ready|pending/);
 const v2Own=await sharedCall(U,id(80),'select public.read_shared_worker_facts($1,$2) v',[v2Rid,reportWorker]);
 eq(v2Own.contract_version,2,'Reader never mistakes work-only consent for v1 complete consent');
 eq(v2Own.editable,true,'Reporter confirms only their completed personal hours after work sign');
 eq(v2Own.hours_required_outside_current_report,false,'Prospective own choice editing receives explicit server other-report requirement');
 const v2FactsInput=value=>{const facts={...value.proposed_worker_facts};delete facts.company_allowance_legacy_labels;return facts;};
 const v2SelectedHours={contract_version:1,items:[choice('company_common',HOUR,'合成時間手当','hour')]};
 const v2FactsA={...v2FactsInput(v2Own),allowance_label:'合成時間手当',company_allowance_selections:v2SelectedHours};
 await reject(()=>sharedCall(U,id(80),'select public.confirm_shared_worker_facts($1,$2,$3::jsonb,7.25,0,$4) v',
  [v2Rid,reportWorker,JSON.stringify(v2FactsA),v2OwnPreview.scope_fingerprint]),/paid_hours_input_conflict/);
 eq(await q('select count(*)::int v from checkout_shared_hours_private.confirmations where report_id=$1',[v2Rid]),0,'A pre-sign scope cannot attest to an unseen later first-work receipt');
 await reject(()=>sharedCall(U,id(80),'select public.confirm_shared_worker_facts($1,$2,$3::jsonb,7.25,0,$4) v',
  [v2Rid,reportWorker,JSON.stringify({...v2FactsA,allowance_amount:100000}),v2Own.scope_fingerprint]),/shared_worker_manual_amount_change_not_allowed/);
 await sharedCall(U,id(80),'select public.confirm_shared_worker_facts($1,$2,$3::jsonb,7.25,0,$4) v',[v2Rid,reportWorker,JSON.stringify(v2FactsA),v2Own.scope_fingerprint]);
 await reject(()=>sharedCall(U,id(80),'select public.confirm_shared_worker_facts($1,$2,$3::jsonb,7,0,$4) v',[v2Rid,W2,JSON.stringify(v2FactsA),v2Own.scope_fingerprint]),/not_editable/);
 await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id) values($1,$2,$3,$4,'clock_out',$5::timestamptz,$6)",[v2EndB,A,W2,SITE,v2Day+'T17:30:00+09:00',v2StartB]);
 await sharedCall(memberB,sidB,'select public.reuse_my_shared_daily_report($1) v',[v2StartB]);
 const v2Peer=await sharedCall(memberB,sidB,'select public.read_shared_worker_facts($1,$2) v',[v2Rid,W2]);
 eq(v2Peer.editable,true,'Peer confirms own real closed-shift hours without editing work facts');
 const v2FactsB={...v2FactsInput(v2Peer),overtime_hours:1.5,early_hours:0.25,
  allowance_label:'合成時間手当',company_allowance_selections:v2SelectedHours};
 await sharedCall(memberB,sidB,'select public.confirm_shared_worker_facts($1,$2,$3::jsonb,6.5,0,$4) v',[v2Rid,W2,JSON.stringify(v2FactsB),v2Peer.scope_fingerprint]);
 eq(await q("select jsonb_build_object('report',to_jsonb(r),'roster',(select jsonb_agg(to_jsonb(w) order by worker_id) from daily_report_workers w where report_id=r.id)) v from daily_reports r where id=$1",[v2Rid]),v2Frozen,'Late confirmations preserve every work fact, roster and first signature byte');
 const v2Before=await sharedCall(memberB,sidB,'select public.read_shared_daily_report_context($1) v',[v2Rid]);
 eq(v2Before.hours_annex.ready,true,'All explicit personal confirmations make final annex ready');
 eq(v2Before.hours_annex.inputs.every(i=>i.hours_required),true,'Confirmed private choices create hour requirement before public work-row materialization');
 await reject(()=>sharedCall(memberB,sidB,"select public.save_daily_report_signature($1,'supervisor',$2,$3::jsonb) v",[v2Rid,'旧経路の責任者',signature]),/shared_hours_supervisor_confirmation_required/);
 const v2PeerSaved=await sharedCall(memberB,sidB,'select public.read_shared_worker_facts($1,$2) v',[v2Rid,W2]);
 await sharedCall(memberB,sidB,'select public.confirm_shared_worker_facts($1,$2,$3::jsonb,null,$4,$5) v',
  [v2Rid,W2,JSON.stringify({...v2FactsB,allowance_label:null,company_allowance_selections:{contract_version:1,items:[]}}),v2PeerSaved.revision,v2PeerSaved.scope_fingerprint]);
 const v2Deselected=await sharedCall(memberB,sidB,'select public.read_shared_worker_facts($1,$2) v',[v2Rid,W2]);
 eq(v2Deselected.required,false,'Deselecting the private hour item does not reuse the earlier selection');
 eq(v2Deselected.hours,null,'No-hour confirmation never fabricates or carries an old quantity');
 await sharedCall(memberB,sidB,'select public.confirm_shared_worker_facts($1,$2,$3::jsonb,6.75,$4,$5) v',
  [v2Rid,W2,JSON.stringify(v2FactsB),v2Deselected.revision,v2Deselected.scope_fingerprint]);
 await reject(()=>sharedCall(memberB,sidB,'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[v2Rid,v2StartB,'古い確認画面',signature,v2Before.report_updated_at,v2Before.signature_scope_fingerprint]),/signature_scope_changed/);
 const v2Latest=await sharedCall(memberB,sidB,'select public.read_shared_daily_report_context($1) v',[v2Rid]);
 await sharedCall(memberB,sidB,'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[v2Rid,v2StartB,'実際の現場責任者',signature,v2Latest.report_updated_at,v2Latest.signature_scope_fingerprint]);
 eq(await q('select count(*)::int v from checkout_shared_hours_private.ledger where report_id=$1',[v2Rid]),2,'Final actual supervisor signature captures two separate version2 confirmations');
 eq(await q('select to_jsonb(overtime_hours) v from daily_report_workers where report_id=$1 and worker_id=$2',[v2Rid,W2]),1.5,'Final normal materialization uses peer-confirmed overtime instead of initial zero');
 eq(await q('select to_jsonb(early_hours) v from attendance_entries where source_report_id=$1 and worker_id=$2',[v2Rid,W2]),0.25,'Peer facts reach original formal attendance writer');
 const v2Amounts=await q("select jsonb_agg(jsonb_build_object('worker_id',p.worker_id,'line',i) order by p.worker_id) v from payroll_statements p cross join lateral jsonb_array_elements(p.detail#>'{unit_resolution,items}') i where p.company_id=$1 and p.period_start='2026-10-01' and p.worker_id=any($2::uuid[]) and i->>'id'=$3",[A,[reportWorker,W2],HOUR]);
 eq(v2Amounts.map(x=>x.line.amount_yen).sort((a,b)=>a-b),[6750,7250],'Normal payroll receives each exact separately confirmed quantity');
 eq(v2Amounts.every(x=>x.line.quantity_basis==='shared_work_report_individual_hours_annex_v2'),true,'Saved evidence explicitly distinguishes v2 consent from legacy dual-signature basis');
 eq(await q("select jsonb_agg(to_jsonb(s) order by worker_id) v from worker_payroll_settings s"),v2Protected.settings,'No wage, insurance or personal allowance setting was rewritten');
 eq(await q("select jsonb_agg(to_jsonb(r) order by id) v from daily_reports r where id=any($1::uuid[])",[v2Protected.old_reports.map(x=>x.id)]),v2Protected.old_reports,'All earlier report signatures and content remain byte-identical');
 for(const fn of ['begin_work_report(uuid)','prepare_supervisor(uuid,text)','capture_report(uuid,jsonb)','supervisor_snapshot(uuid)']){
  eq(await q("select has_function_privilege('authenticated',$1,'execute') v",['checkout_shared_hours_private.'+fn]),false,'Authenticated cannot call internal consent capability directly');
 }
 console.log(JSON.stringify({pass:true,versioned_work_report_then_individual_hours:true,first_work_signature_preserved:true,stale_and_direct_supervisor_bypass_denied:true,actual_payroll_quantities:[7.25,6.75],legacy_reports_preserved:true,real_gotrue:false,production_changed:false}));
`;
const folder=await mkdtemp(join(tmpdir(),'shared-hours-v2-proof-'));
try{
 const path=join(folder,'proof.mjs');await writeFile(path,original.replace(marker,()=>addition+marker));
 const result=spawnSync(process.execPath,[path,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally{await rm(folder,{recursive:true,force:true});}
