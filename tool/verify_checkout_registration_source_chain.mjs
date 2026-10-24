// Runs the unchanged existing source-bound suite plus an appended review unit.
// Only a temporary JS copy is extended. Production SQL/writer bodies are intact.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const original=await readFile('tool/verify_company_checkout_integration.mjs','utf8');
const marker=" phase='source-and-settings-preservation';";
assert.equal(original.split(marker).length,2,'Unique source-bound suite insertion point');
const extension=String.raw`
 phase='authoritative-registration-source-chain';
 await exec("alter table workers add column user_id uuid,add column status text default 'active';alter table daily_report_workers add column vehicle_id uuid,add column route_assignment_id uuid,add column odometer_km numeric;");
 await client.query('update workers set user_id=$1 where id=$2',[U,W]);
 await exec("create table attendance_verifications(id uuid primary key,company_id uuid,worker_id uuid,site_id uuid,route_assignment_id uuid,event_type text,confirmed_at timestamptz,work_date date,source_clock_in_id uuid,daily_report_id uuid,vehicle_id uuid);create table private.vehicle_usage_rollout(company_id uuid,enabled boolean);create table vehicles(id uuid,company_id uuid,display_name text,odometer_km numeric);create table vehicle_usage_claims(source_clock_in_id uuid,company_id uuid,driver_worker_id uuid,vehicle_id uuid,work_date date,ended_at timestamptz);create table vehicle_meter_events(id uuid primary key,source_clock_in_id uuid,company_id uuid,driver_worker_id uuid,vehicle_id uuid,work_date date,previous_km numeric,current_km numeric,distance_km numeric);");
 await exec(await readFile('supabase/migrations/20261008162618_attach_vehicle_meter_to_report.sql','utf8'));
 const scopeSource=await readFile('supabase/migrations/20261009171504_payroll_refresh_scope_order.sql','utf8');
 const originalLock=/create function payroll_scope_private\.lock_scopes\([\s\S]*?end \$\$;/.exec(scopeSource)?.[0];assert.ok(originalLock);
 await exec('drop function payroll_scope_private.lock_scopes(jsonb,boolean)');await exec(originalLock);
 await exec('revoke all on function payroll_scope_private.lock_scopes(jsonb,boolean) from public,anon,authenticated');
 await exec("create table app_notifications(id uuid primary key default gen_random_uuid(),company_id uuid,recipient_user_id uuid,kind text,title text,body text,action_key text,action_id uuid,read_at timestamptz);create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language plpgsql as $$declare n uuid;begin insert into public.app_notifications(company_id,recipient_user_id,kind,title,body,action_key,action_id) values($1,$2,$3,$4,$5,$6,$7) returning id into n;return n;end$$;");
 for(const suffix of ['', '_validators','_reminders','_schedule'])await exec(await readFile('docs/candidates/checkout_report_registration'+suffix+'.sql.review-only','utf8'));
 await client.query("insert into checkout_report_registration_private.rollout values($1,'2026-10-01',true)",[A]);
 const sourceIn=id(700),sourceOut=id(701),vehicle=id(702),event=id(703);
 await client.query("insert into attendance_verifications values($1,$3,$4,$5,null,'clock_in','2026-10-24 08:00Z','2026-10-24',null,null,$6),($2,$3,$4,$5,null,'clock_out','2026-10-24 17:00Z','2026-10-24',$1,null,$6)",[sourceIn,sourceOut,A,W,SITE,vehicle]);
 const gate=()=>q('select public.read_pending_checkout_report_registration() v');
 eq((await gate()).items[0].registration_state,'report_missing','Source-chain report initially missing');
 const sourceReport=await draft('2026-10-24',W,[]);
 await client.query('update attendance_verifications set daily_report_id=$1',[sourceReport]);
 await client.query('insert into private.vehicle_usage_rollout values($1,true)',[A]);
 await client.query("insert into vehicle_usage_claims values($1,$2,$3,$4,'2026-10-24','2026-10-24 17:00Z')",[sourceIn,A,W,vehicle]);
 await reject(()=>client.query("select public.save_daily_report_signature($1,'representative','Synthetic reporter',$2::jsonb)",[sourceReport,signature]),/complete committed vehicle/);
 eq((await gate()).items[0].registration_state,'report_input_incomplete','Existing meter trigger and reader both reject missing event');
 await client.query("insert into vehicle_meter_events values($1,$2,$3,$4,$5,'2026-10-24',100,110,10)",[event,sourceIn,A,W,vehicle]);
 const attached=await q('select public.attach_vehicle_meter_to_report($1,$2) v',[sourceReport,sourceIn]);
 eq(attached.attached,true,'Original vehicle writer attaches immutable event');
 await client.query("select public.save_daily_report_signature($1,'representative','Synthetic reporter',$2::jsonb)",[sourceReport,signature]);
 eq((await gate()).items[0].blocking,false,'Original reporter writer unlocks pending gate');
 eq((await gate()).items[0].registration_state,'reporter_saved_waiting_supervisor','Original reporter save retains supervisor wait');
 eq((await q('select checkout_report_registration_private.deliver_daily() v')).sent,1,'Source-chain daily missing supervisor delivery');
 await client.query("select public.save_daily_report_signature($1,'supervisor','Synthetic supervisor',$2::jsonb)",[sourceReport,signature]);
 eq(await q('select checkout_report_registration_private.projection_complete($1,$2) v',[sourceReport,W]),true,'Original dual sign creates formal attendance and normal payroll detail');
 eq((await gate()).items,[],'Original chain completes pending');
 eq((await q('select checkout_report_registration_private.deliver_daily() v')).sent,0,'Source-chain completion stops daily reminders');
 phase='actual-supervisor-versus-notification-race';
 const raceIn=id(710),raceOut=id(711);
 await client.query("insert into attendance_verifications values($1,$3,$4,$5,null,'clock_in','2026-10-23 08:00Z','2026-10-23',null,null,null),($2,$3,$4,$5,null,'clock_out','2026-10-23 17:00Z','2026-10-23',$1,null,null)",[raceIn,raceOut,A,W,SITE]);
 const raceReport=await draft('2026-10-23',W,[]);
 await client.query('update attendance_verifications set daily_report_id=$1 where id=any($2::uuid[])',[raceReport,[raceIn,raceOut]]);
 await client.query("select public.save_daily_report_signature($1,'representative','Synthetic reporter',$2::jsonb)",[raceReport,signature]);
 const raceClient=new pg.Client({connectionString:destination.href,connectionTimeoutMillis:5000});await raceClient.connect();
 try {
  await raceClient.query('begin');await raceClient.query("select set_config('fixture.actor',$1,true)",[U]);
  // The real signature writer completes its SQL but has not committed. Its
  // canonical worker/month/report locks remain held by the other session.
  await raceClient.query("select public.save_daily_report_signature($1,'supervisor','Concurrent supervisor',$2::jsonb)",[raceReport,signature]);
  eq((await gate()).items[0].registration_state,'reporter_saved_waiting_supervisor','Uncommitted signature is invisible to the initial read');
  const contended=await q('select checkout_report_registration_private.deliver_daily() v');
  eq(contended.sent,0,'No stale missing-signature notification during actual writer transaction');
  eq(contended.failures.map(x=>x.sqlstate),['55P03'],'Contended canonical lock is an explicit retryable failure');
  eq(await q('select count(*)::int v from checkout_report_registration_private.daily_deliveries where source_clock_in_id=$1',[raceIn]),0,'Race creates no false delivery receipt');
  // Negative control in this disposable transaction only: remove just the new
  // lock block. Demonstrate that the exact same held writer otherwise permits
  // stale enqueue, then ROLLBACK both unsafe definition and its notification.
  const hardenedDefinition=await q("select pg_get_functiondef('checkout_report_registration_private.deliver_daily(uuid,integer)'::regprocedure) v");
  const hardenedHash=await q("select md5(prosrc) v from pg_proc where oid='checkout_report_registration_private.deliver_daily(uuid,integer)'::regprocedure");
  const lockBlock=/   perform payroll_scope_private\.lock_scopes\(scopes,false\);[\s\S]*?   perform 1 from public\.attendance_verifications where id=any\(source_ids\) order by id for share;/;
  assert.ok(lockBlock.test(hardenedDefinition));
  await exec('begin');
  try {
   await exec(hardenedDefinition.replace(lockBlock,'   -- Disposable unsafe negative control; always rolled back.'));
   const unsafe=await q('select checkout_report_registration_private.deliver_daily() v');
   eq(unsafe.sent,1,'Negative control proves missing locks would enqueue a stale missing-signature reason');
  } finally {await exec('rollback');}
  eq(await q("select md5(prosrc) v from pg_proc where oid='checkout_report_registration_private.deliver_daily(uuid,integer)'::regprocedure"),hardenedHash,'Hardened source restored exactly after negative control');
  eq(await q('select count(*)::int v from checkout_report_registration_private.daily_deliveries where source_clock_in_id=$1',[raceIn]),0,'Negative-control receipt and notification rolled back');
  await raceClient.query('commit');
 } finally {await raceClient.query('rollback');await raceClient.end();}
 eq((await gate()).items,[],'Committed actual supervisor projection removes pending work');
 eq((await q('select checkout_report_registration_private.deliver_daily() v')).sent,0,'Retry after writer commit does not enqueue stale reason');
 console.log(JSON.stringify({pass:true,authoritative_registration_actual_save_sign_meter_payroll:true,real_gotrue:false,production_changed:false}));
`;
const temp=await mkdtemp(join(tmpdir(),'checkout-registration-source-chain-'));
try {
 const generated=original.replace(marker,()=>extension+marker);
 assert.ok(generated.includes(extension),'Inserted SQL dollar delimiters are preserved exactly');
 const file=join(temp,'proof.mjs');await writeFile(file,generated);
 const result=spawnSync(process.execPath,[file,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;
 process.exitCode=result.status??1;
}finally {await rm(temp,{recursive:true,force:true});}
