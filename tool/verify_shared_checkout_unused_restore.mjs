// One extension of the original source-bound registration/shared proof.
// Original save/sign/payroll cases run unchanged after the complete OFF restore.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const source=await readFile('tool/verify_shared_daily_report.mjs','utf8');
const marker=" await exec(await readFile('docs/candidates/shared_daily_report.sql.review-only','utf8'));";
assert.equal(source.split(marker).length,2,'One original shared install hook');
const addition=String.raw`
 {
 phase='complete-shared-checkout-off-install-and-unused-restore';
 const restoreTools=await import('file://'+process.cwd()+'/tool/security/shared_checkout_unused_restore.mjs');
 // Missing surroundings of this existing minimal fixture are completed BEFORE
 // its baseline. These are not production changes or GPS/Auth feature proofs.
 const restoreGroupFixture=JSON.parse(await readFile('tool/security/shared_group_lock_source_fixture.json','utf8'));
 await exec(restoreGroupFixture.normalizer_definition);await exec(restoreGroupFixture.normalizer_trigger_definition);
 const restoreManagementFixture=JSON.parse(await readFile('tool/security/shared_management_source_fixture.json','utf8'));
 await exec(restoreManagementFixture.definition);
 eq(await q("select md5(prosrc) v from pg_proc where oid='public.force_manage_attendance(text,jsonb)'::regprocedure"),restoreManagementFixture.source_md5,'Exact observed original management writer');
 await exec("create table if not exists private.route_journey_captures(id uuid,source_clock_in_id uuid);create table if not exists private.route_journey_visit_events(capture_id uuid,source_clock_in_id uuid,start_capture_id uuid,kind text,route_stop_id uuid);create table if not exists route_stops(id uuid,route_assignment_id uuid);");
 await exec("create table if not exists public.daily_report_edit_requests(id uuid primary key,report_id uuid,company_id uuid,requested_by uuid,reason text,status text,approvals_required integer default 2,created_at timestamptz default now(),resolved_at timestamptz);alter table public.daily_report_edit_requests add column if not exists company_id uuid;revoke insert,update,delete on public.daily_report_edit_requests from authenticated,anon;");
 await exec("create table public.gps_auto_attendance_schedules(company_id uuid,worker_id uuid primary key,site_id uuid,route_assignment_id uuid,weekdays smallint[],local_time time,timezone text,enabled boolean,updated_by uuid,updated_at timestamptz);create table public.work_attendance_selections(company_id uuid,worker_id uuid,work_date date,mode text,site_id uuid,route_assignment_id uuid,updated_by uuid,updated_at timestamptz);create table public.work_vehicle_route_selections(company_id uuid,worker_id uuid,work_date date,vehicle_id uuid,route_assignment_id uuid,updated_by uuid,updated_at timestamptz);");
 await exec("create schema cron;create table cron.job(jobid bigint primary key,command text);");
 const restoreBefore=await restoreTools.collectSnapshot(client,{nativeAuth:true});
 const installFiles=[
  'docs/candidates/shared_daily_report.sql.review-only',
  'docs/candidates/closed_day_paid_hours_scope.sql.review-only',
  'docs/candidates/checkout_paid_hours_ledger.sql.review-only',
  process.env.SKO_PAID_HOURS_PATCHES,
  'docs/candidates/checkout_paid_hours_api.sql.review-only',
  'docs/candidates/checkout_shared_worker_facts.sql.review-only',
  'docs/candidates/checkout_shared_hours_v2.sql.review-only',
  process.env.SKO_SHARED_HOURS_V2_PATCHES,
  'docs/candidates/checkout_shared_managed_source.sql.review-only',
  'docs/candidates/checkout_shared_hours_v2_api.sql.review-only',
  'docs/candidates/shared_daily_report_group_lock.sql.review-only',
  'docs/candidates/shared_daily_report_management_locks.sql.review-only',
  'docs/candidates/shared_daily_report_approved_edit.sql.review-only',
  'docs/candidates/scheduled_checkout_reminders.sql.review-only'
 ];
 const installModules=[];
 for(const file of installFiles){assert.ok(file,'Exact generated connection SQL is required');installModules.push(await readFile(file,'utf8'));}
 const installSQL=restoreTools.assembleOffInstallSQL(installModules);
 // Failure at the final module must roll back the earlier thirteen modules.
 await assert.rejects(()=>client.query(installSQL.replace(/commit;\s*$/,"select 1/0;commit;")),/division by zero/);
 await exec('rollback');
 eq(await restoreTools.collectSnapshot(client,{nativeAuth:true}),restoreBefore,'Late installation failure leaves exact baseline');
 await exec(installSQL);
 const restoreInstalled=await restoreTools.collectSnapshot(client,{installed:true,nativeAuth:true});
 const unusedRestore=restoreTools.buildRestoreSQL(restoreBefore,restoreInstalled,{nativeAuth:true});
 const refuseRestore=async(setup,pattern)=>{
  await exec('begin');
  try{await setup();await assert.rejects(()=>client.query(unusedRestore),pattern);}finally{await exec('rollback');}
  eq(await restoreTools.collectSnapshot(client,{installed:true,nativeAuth:true}),restoreInstalled,'Refusal/rollback preserves every installed object and protected application/Auth row');
 };
 await refuseRestore(()=>client.query('insert into checkout_shared_hours_private.rollout(company_id,starts_on,enabled) values($1,\'2026-10-01\',false)',[A]),/shared_checkout_restore_used_state/);
 await refuseRestore(()=>exec("insert into cron.job values(1,'select scheduled_checkout_private.read_actor(null)')"),/shared_checkout_restore_cron_present/);
 await refuseRestore(()=>exec("create function shared_worker_facts_private.unreviewed_restore_probe() returns boolean language sql as $$select true$$"),/shared_checkout_restore_catalog_changed/);
 await refuseRestore(()=>exec('create view public.external_checkout_restore_probe as select * from checkout_shared_hours_private.rollout'),/shared_checkout_restore_external_dependency/);
 await refuseRestore(()=>exec('alter function public.sign_daily_report(uuid,text,jsonb) set search_path=public'),/shared_checkout_restore_original_connection_changed/);
 const wrongDataBaseline=structuredClone(restoreBefore);
 wrongDataBaseline.protected_relations['public.daily_reports'].md5='00000000000000000000000000000000';
 // Generation itself rejects a baseline whose existing data differ from the
 // independently captured installed state, before any restore SQL exists.
 assert.throws(()=>restoreTools.buildRestoreSQL(wrongDataBaseline,restoreInstalled,{nativeAuth:true}),/Install cannot mutate/);
 await exec(unusedRestore);
 const restoreAfter=await restoreTools.collectSnapshot(client,{nativeAuth:true});
 eq(restoreAfter,restoreBefore,'Unused restore returns the entire observed catalog and existing application/Auth/foundation state exactly');
 for(const name of restoreTools.schemas)eq(await q('select to_regnamespace($1) is null v',[name]),true,'Only reviewed new schema removed: '+name);
 // A fresh install is deliberately NOT left behind. The unchanged parent
 // shared suite below creates its own candidates and executes its old cases.
 if(process.env.SKO_RESTORE_PROOF_OUTPUT){
  await writeFile(process.env.SKO_RESTORE_PROOF_OUTPUT+'/before.json',JSON.stringify(restoreBefore,null,2)+'\n');
  await writeFile(process.env.SKO_RESTORE_PROOF_OUTPUT+'/installed.json',JSON.stringify(restoreInstalled,null,2)+'\n');
  await writeFile(process.env.SKO_RESTORE_PROOF_OUTPUT+'/after.json',JSON.stringify(restoreAfter,null,2)+'\n');
  await writeFile(process.env.SKO_RESTORE_PROOF_OUTPUT+'/restore-unused.sql.review-only',unusedRestore);
 }
 console.log(JSON.stringify({pass:true,complete_off_install_and_unused_restore:true,new_schemas:7,new_tables:21,original_routines_restored:4,used_cron_unknown_external_and_changed_source_refused:true,app_auth_foundation_unchanged:true,cascade_used:false,auth_gps_surroundings_synthetic:true,real_gotrue:false,production_changed:false}));
 }
`;
const folder=await mkdtemp(join(tmpdir(),'shared-checkout-unused-restore-'));
try{
 const file=join(folder,'proof.mjs');await writeFile(file,source.replace(marker,()=>addition+marker));
 const result=spawnSync(process.execPath,[file,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally{await rm(folder,{recursive:true,force:true});}
