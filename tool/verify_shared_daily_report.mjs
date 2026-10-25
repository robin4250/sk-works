// Extends the unchanged original save/sign/payroll and registration proof.
// Auth/permission surroundings are synthetic. No production URL is accepted.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';
const base=await readFile('tool/verify_checkout_registration_source_chain.mjs','utf8');
const marker=' console.log(JSON.stringify({pass:true,authoritative_registration_actual_save_sign_meter_payroll:true,real_gotrue:false,production_changed:false}));';
assert.equal(base.split(marker).length,2);
const addition=String.raw`
 phase='shared-report-contract';
 await exec("create function private.has_company_feature(cid uuid,feature text) returns boolean language sql stable as $$select cid='00000000-0000-0000-0000-000000000001'::uuid and feature='can_manage_attendance' and current_setting('fixture.manager',true)='on'$$;");
 await exec("create or replace function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('role','authenticated','sub',current_setting('fixture.actor',true),'session_id',coalesce(nullif(current_setting('fixture.sid',true),''),'00000000-0000-0000-0000-000000000080'),'is_anonymous',false)$$;");
 const memberB=id(8010),memberC=id(8011),sidB=id(8081),sidC=id(8082);
 await client.query('insert into auth.users(id) values($1),($2)',[memberB,memberC]);
 await client.query('insert into auth.sessions(id,user_id) values($1,$2),($3,$4)',[sidB,memberB,sidC,memberC]);
 await client.query('insert into company_members(company_id,user_id) values($1,$2),($1,$3)',[A,memberB,memberC]);
 await client.query('update workers set user_id=$1 where id=$2',[memberB,W2]);
 await client.query('update workers set user_id=$1 where id=$2',[memberC,W3]);
 const sharedCall=async(actor,sid,sql,args=[])=>{await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[actor,sid]);await exec('set role authenticated');try{return await q(sql,args);}finally{await exec('reset role');}};
 const mkShift=async(n,wid,day,completed=true)=>{
  await client.query("insert into attendance_verifications values($1,$2,$3,$4,null,'clock_in',$5::date+time '08:00','"+day+"',null,null,null)",[id(n),A,wid,SITE,day]);
  if(completed)await client.query("insert into attendance_verifications values($1,$2,$3,$4,null,'clock_out',$5::date+time '17:00',$5,$6,null,null)",[id(n+1),A,wid,SITE,day,id(n)]);
 };
 await mkShift(8100,reportWorker,'2026-10-25');await mkShift(8102,W2,'2026-10-25',false);
 await mkShift(8104,W3,'2026-10-25');
 await mkShift(8180,reportWorker,'2026-10-29');
 const historical=await draft('2026-10-29',reportWorker,[]);await sign(historical);
 const historicalBefore=await q('select to_jsonb(r) v from daily_reports r where id=$1',[historical]);
 await exec(await readFile('docs/candidates/shared_daily_report.sql.review-only','utf8'));
 // Explicit synthetic closing-facts adapter. This proof establishes shared
 // role/locking/freeze/CAS boundaries; the actual per-worker confirmation and
 // final fact materializer are tested by the separately composed v2 suite.
 await exec("create schema checkout_shared_hours_private;create table checkout_shared_hours_private.fixture_confirmations(report_id uuid,worker_id uuid,confirmed_by uuid,primary key(report_id,worker_id));create function checkout_shared_hours_private.begin_work_report(rid uuid) returns void language plpgsql as $$begin if not exists(select 1 from shared_daily_report_private.work_protocol where report_id=rid) then raise exception 'fixture protocol missing';end if;end$$;create function checkout_shared_hours_private.supervisor_snapshot(rid uuid) returns jsonb language plpgsql stable as $$declare active boolean;ready_value boolean;begin active:=exists(select 1 from shared_daily_report_private.work_protocol where report_id=rid);ready_value:=active and (shared_daily_report_private.personal_out_snapshot(rid)->>'ready')::boolean and checkout_report_registration_private.inputs_complete(rid) and not exists(select 1 from daily_report_workers rw where rw.report_id=rid and not exists(select 1 from checkout_shared_hours_private.fixture_confirmations c where c.report_id=rid and c.worker_id=rw.worker_id));return jsonb_build_object('schema',2,'enabled',active,'required',active,'ready',ready_value,'fingerprint',repeat('a',64),'inputs','[]'::jsonb);end$$;create function checkout_shared_hours_private.prepare_supervisor(rid uuid,expectedhash text) returns void language plpgsql as $$begin if expectedhash<>repeat('a',64) or (checkout_shared_hours_private.supervisor_snapshot(rid)->>'ready')::boolean is distinct from true then raise exception 'fixture annex not ready';end if;end$$;");

 eq((await sharedCall(U,id(80),'select public.read_my_shared_daily_report($1) v',[id(8100)])).state,'disabled','Explicit OFF is distinct from missing/error');
 await client.query("insert into shared_daily_report_private.rollout(company_id,starts_on,enabled) values($1,'2026-10-01',true)",[A]);
 eq(await q('select to_jsonb(r) v from daily_reports r where id=$1',[historical]),historicalBefore,'Existing signed v1 report is unchanged after rollout');
 eq(await q('select count(*)::int v from shared_daily_report_private.work_protocol where report_id=$1',[historical]),0,'Historical signed report is never enrolled by date');
 const roster=JSON.stringify([worker(reportWorker,[]),worker(W2,[])]);
 const first=await sharedCall(U,id(80),'select public.submit_shared_daily_report($1,null,$2,$3::jsonb,$4,$5::jsonb) v',[id(8100),'共同作業',roster,'最初の報告者',signature]);
 eq(first.state,'reporter_saved_waiting_supervisor','First reporter commits content and own signature atomically');
 const sharedRid=first.report_id;
 await client.query('insert into checkout_shared_hours_private.fixture_confirmations values($1,$2,$3)',[sharedRid,reportWorker,U]);
 eq(await q("select count(*)::int v from daily_reports where company_id=$1 and site_id=$2 and report_date='2026-10-25'",[A,SITE]),1,'One report per destination/day');
 eq(await q("select count(*)::int v from app_notifications where action_key='shared_daily_report' and action_id=$1 and recipient_user_id=$2",[sharedRid,memberB]),1,'Other roster member notified once');
 const frozen=await q('select jsonb_build_object(\'report\',to_jsonb(r),\'roster\',(select jsonb_agg(to_jsonb(w) order by worker_id) from daily_report_workers w where report_id=r.id)) v from daily_reports r where id=$1',[sharedRid]);
 await reject(()=>client.query('select public.save_daily_report_destination_draft($1,$2,null,$3,$4,$5::jsonb)',[sharedRid,SITE,'2026-10-25','消してはいけない',roster]),/signed_facts/);
 await reject(()=>client.query("update daily_reports set representative_signature_json=null where id=$1",[sharedRid]),/signed_facts/);
 await reject(()=>client.query('delete from daily_report_workers where report_id=$1',[sharedRid]),/roster_requires/);
 eq(await q('select jsonb_build_object(\'report\',to_jsonb(r),\'roster\',(select jsonb_agg(to_jsonb(w) order by worker_id) from daily_report_workers w where report_id=r.id)) v from daily_reports r where id=$1',[sharedRid]),frozen,'Rejected legacy save preserved report and roster exactly');
 eq((await sharedCall(memberB,sidB,'select public.read_shared_daily_report_context($1) v',[sharedRid])).can_collect_supervisor,true,'Still-working roster member may access supervisor collection readiness');
 eq((await sharedCall(memberB,sidB,'select public.reuse_my_shared_daily_report($1) v',[id(8102)])).state,'own_checkout_required','Shared report never clocks another member out');
 await reject(()=>sharedCall(memberC,sidC,'select public.read_shared_daily_report_context($1) v',[sharedRid]),/member_required/);
 await reject(()=>sharedCall(memberC,sidC,'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[sharedRid,id(8104),'責任者',signature,null,null]),/member_required/);
 await reject(()=>sharedCall(memberC,sidC,"select public.save_daily_report_signature($1,'supervisor',$2,$3::jsonb) v",[sharedRid,'旧経路からの非対象者',signature]),/signature_actor_required/);
 const openContext=await sharedCall(memberB,sidB,'select public.read_shared_daily_report_context($1) v',[sharedRid]);
 eq(openContext.supervisor_ready,false,'Open coworker shift prevents final signature/projection, not work registration');
 assert.ok(openContext.pending_members.some(x=>x.worker_id===W2));
 await reject(()=>sharedCall(memberB,sidB,'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[sharedRid,id(8102),'現場責任者本人',signature,openContext.report_updated_at,openContext.signature_scope_fingerprint]),/supervisor_not_ready/);
 await reject(()=>sharedCall(memberB,sidB,"select public.save_daily_report_signature($1,'supervisor',$2,$3::jsonb) v",[sharedRid,'旧経路も未退勤を迂回しない',signature]),/supervisor_not_ready/);
 eq(await q('select count(*)::int v from attendance_entries where source_report_id=$1',[sharedRid]),0,'No attendance projection for still-working coworker');
 await client.query("insert into attendance_verifications values($1,$2,$3,$4,null,'clock_out','2026-10-25 18:00Z','2026-10-25',$5,null,null)",[id(8103),A,W2,SITE,id(8102)]);
 eq((await sharedCall(memberB,sidB,'select public.read_shared_daily_report_context($1) v',[sharedRid])).supervisor_ready,false,'Real checkout does not invent an unconfirmed closing-facts receipt');
 await client.query('insert into checkout_shared_hours_private.fixture_confirmations values($1,$2,$3)',[sharedRid,W2,memberB]);
 const beforeSupervisor=await sharedCall(memberB,sidB,'select public.read_shared_daily_report_context($1) v',[sharedRid]);
 eq(beforeSupervisor.supervisor_ready,true,'Ready after all personal checkouts and explicit synthetic confirmation boundary');
 const saved=await sharedCall(memberB,sidB,'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[sharedRid,id(8102),'現場責任者本人',signature,beforeSupervisor.report_updated_at,beforeSupervisor.signature_scope_fingerprint]);
 eq(saved.state,'saved','Any eligible roster member collects final supervisor signature when all facts are ready');
 const signedRow=await q('select to_jsonb(r) v from daily_reports r where id=$1',[sharedRid]);eq(signedRow.status,'signed','Original two-signature writer finalizes only after readiness');
 eq(signedRow.updated_by,memberB,'Collector actor remains distinct from actual signer name');
 const reused=await sharedCall(memberB,sidB,'select public.reuse_my_shared_daily_report($1) v',[id(8102)]);
 eq(reused.source_attached,true,'Later real checkout appends only same-roster source reference after signing');
 eq(await q('select to_jsonb(r) v from daily_reports r where id=$1',[sharedRid]),signedRow,'Source reference append preserves all signed report fields');
 eq((await sharedCall(memberB,sidB,'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[sharedRid,id(8102),'現場責任者本人',signature,beforeSupervisor.report_updated_at,beforeSupervisor.signature_scope_fingerprint])).state,'already_saved','Same signature retry is idempotent');
 await reject(()=>sharedCall(memberB,sidB,'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[sharedRid,id(8102),'別の人',signature,beforeSupervisor.report_updated_at,beforeSupervisor.signature_scope_fingerprint]),/already_saved/);
 eq(await q("select count(*)::int v from shared_daily_report_private.signature_events where report_id=$1 and role='supervisor'",[sharedRid]),1,'Supervisor signature audit is append-only and not duplicated by retry');
 // A real recorded-hours basis hashes source links; it must not silently change.
 await exec('create schema checkout_paid_hours_candidate_private;create table checkout_paid_hours_candidate_private.drafts(company_id uuid,worker_id uuid,work_date date);');
 await mkShift(8110,reportWorker,'2026-10-26');await mkShift(8112,W2,'2026-10-26');
 const legacyPartial=await q("select public.save_daily_report_destination_draft(null,$1,null,'2026-10-26','既存時間basis',$2::jsonb) v",[SITE,roster]);
 await client.query("update daily_reports set created_at=(select new_report_from-interval '1 day' from shared_daily_report_private.rollout where company_id=$2) where id=$1",[legacyPartial,A]);
 await sharedCall(U,id(80),"select public.save_daily_report_signature($1,'representative',$2,$3::jsonb) v",[legacyPartial,'既存v1報告者',signature]);
 const second=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[legacyPartial]);
 await reject(()=>sharedCall(memberB,sidB,'select public.collect_shared_report_supervisor_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',
  [second.report_id,id(8112),'古い画面の責任者',signature,second.report_updated_at,'0'.repeat(64)]),/signature_scope_changed/);
 await client.query("insert into checkout_paid_hours_candidate_private.drafts values($1,$2,'2026-10-26')",[A,W2]);
 eq((await sharedCall(memberB,sidB,'select public.reuse_my_shared_daily_report($1) v',[id(8112)])).state,'recorded_hours_basis_requires_approved_edit','Recorded hours source basis cannot change through harmless-link shortcut');
 eq(await q('select daily_report_id v from attendance_verifications where id=$1',[id(8112)]),null,'Hours-basis hold performs no association write');
 // Management bypasses missing clocks and own roster, not permission or signature evidence.
 await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[U,id(80)]);
 await mkShift(8130,reportWorker,'2026-10-27');
 const managed=await draft('2026-10-27',reportWorker,[]);
 await reject(()=>sharedCall(memberC,sidC,'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[managed,'representative','本人報告者',signature,null,null]),/management_required/);
 await exec("select set_config('fixture.manager','on',false)");
 eq((await sharedCall(memberC,sidC,'select public.read_shared_daily_report_context($1) v',[managed])).can_manage_attendance,true,'Server-confirmed management recovery capability');
 const managedBefore=await sharedCall(memberC,sidC,'select public.read_shared_daily_report_context($1) v',[managed]);
 eq((await sharedCall(memberC,sidC,'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[managed,'representative','本人報告者',signature,managedBefore.report_updated_at,managedBefore.signature_scope_fingerprint])).state,'saved','Authorized manager obtains reporter signature without own shift');
 await client.query('insert into checkout_shared_hours_private.fixture_confirmations values($1,$2,$3)',[managed,reportWorker,memberC]);
 const managedAfterReporter=await sharedCall(memberC,sidC,'select public.read_shared_daily_report_context($1) v',[managed]);
 eq((await sharedCall(memberC,sidC,'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[managed,'supervisor','本人責任者',signature,managedAfterReporter.report_updated_at,managedAfterReporter.signature_scope_fingerprint])).state,'saved','Authorized manager obtains supervisor signature without own roster');
 eq(await q("select count(*)::int v from shared_daily_report_private.signature_events where report_id=$1 and actor_user_id=$2",[managed,memberC]),2,'Both actual signer roles retain management actor audit');
 await exec("select set_config('fixture.manager','off',false)");
 await exec('drop table checkout_paid_hours_candidate_private.drafts;drop schema checkout_paid_hours_candidate_private;');
 // First reporter wins under a real separate-connection race, not a client
 // boolean. The losing caller retries by reading the winner, never replacing.
 await mkShift(8120,reportWorker,'2026-10-28');await mkShift(8122,W2,'2026-10-28');
 await exec('begin');
 let firstRace;
 const sharedRaceClient=new pg.Client({connectionString:destination.href,connectionTimeoutMillis:5000});await sharedRaceClient.connect();
 try {
  firstRace=await sharedCall(U,id(80),'select public.submit_shared_daily_report($1,null,$2,$3::jsonb,$4,$5::jsonb) v',[id(8120),'先着の本文',roster,'先着報告者',signature]);
  await sharedRaceClient.query('begin');await sharedRaceClient.query("set local lock_timeout='100ms'");
  await sharedRaceClient.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[memberB,sidB]);
  await sharedRaceClient.query('set role authenticated');
  await reject(()=>sharedRaceClient.query('select public.submit_shared_daily_report($1,null,$2,$3::jsonb,$4,$5::jsonb)',[id(8122),'上書きしてはいけない本文',roster,'後着報告者',signature]),/lock timeout/);
  await sharedRaceClient.query('rollback');await exec('commit');
 } finally {await sharedRaceClient.query('rollback');await sharedRaceClient.end();await exec('rollback');}
 const secondRace=await sharedCall(memberB,sidB,'select public.submit_shared_daily_report($1,null,$2,$3::jsonb,$4,$5::jsonb) v',[id(8122),'上書きしてはいけない本文',roster,'後着報告者',signature]);
 eq(secondRace.report_id,firstRace.report_id,'Concurrent loser reuses first report');
 eq(await q('select work_description v from daily_reports where id=$1',[firstRace.report_id]),'先着の本文','Concurrent retry does not alter work facts');
 eq(await q("select count(*)::int v from shared_daily_report_private.signature_events where report_id=$1 and role='representative'",[firstRace.report_id]),1,'First-report race creates one reporter event');
 // Fresh reports cannot bypass protocol enrollment through the old API.
 await mkShift(8140,reportWorker,'2026-10-30');
 await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[U,id(80)]);
 const oldClientFresh=await draft('2026-10-30',reportWorker,[]);
 await reject(()=>sharedCall(U,id(80),"select public.save_daily_report_signature($1,'representative',$2,$3::jsonb) v",[oldClientFresh,'旧クライアント',signature]),/updated_app_required/);
 for(const signatureName of ['read_my_shared_daily_report(uuid)','read_shared_daily_report_context(uuid)','reuse_my_shared_daily_report(uuid)','submit_shared_daily_report(uuid,timestamptz,text,jsonb,text,jsonb)','collect_shared_report_supervisor_signature(uuid,uuid,text,jsonb,timestamptz,text)','manage_shared_report_signature(uuid,text,text,jsonb,timestamptz,text)']){
  eq(await q('select has_function_privilege(\'anon\',$1,\'execute\') v',['public.'+signatureName]),false,'Anon cannot call shared APIs');
  eq(await q('select has_function_privilege(\'service_role\',$1,\'execute\') v',['public.'+signatureName]),false,'Default service role cannot call shared APIs');
 }
 await client.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false)",[U,id(80)]);
 await exec('drop function checkout_shared_hours_private.prepare_supervisor(uuid,text);drop function checkout_shared_hours_private.supervisor_snapshot(uuid);drop function checkout_shared_hours_private.begin_work_report(uuid);drop table checkout_shared_hours_private.fixture_confirmations;drop schema checkout_shared_hours_private;');
 console.log(JSON.stringify({pass:true,shared_report_actual_save_sign:true,normal_member_and_management_separate:true,real_gotrue:false,production_changed:false}));
`;
const generated=base.replace(marker,()=>addition+marker);
const folder=await mkdtemp(join(tmpdir(),'shared-report-proof-'));
try {const file=join(folder,'proof.mjs');await writeFile(file,generated);
 const result=spawnSync(process.execPath,[file,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally {await rm(folder,{recursive:true,force:true});}
