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
 await exec("create table attendance_verifications(id uuid primary key,company_id uuid,worker_id uuid,site_id uuid,route_assignment_id uuid,event_type text,confirmed_at timestamptz,work_date date,source_clock_in_id uuid,daily_report_id uuid,vehicle_id uuid);create table vehicles(id uuid,company_id uuid,display_name text,odometer_km numeric,is_active boolean default true,updated_by uuid,updated_at timestamptz);");
 const scopeSource=await readFile('supabase/migrations/20261009171504_payroll_refresh_scope_order.sql','utf8');
 const originalLock=/create function payroll_scope_private\.lock_scopes\([\s\S]*?end \$\$;/.exec(scopeSource)?.[0];assert.ok(originalLock);
 await exec('drop function payroll_scope_private.lock_scopes(jsonb,boolean)');await exec(originalLock);
 await exec('revoke all on function payroll_scope_private.lock_scopes(jsonb,boolean) from public,anon,authenticated');
 await exec("create table app_notifications(id uuid primary key default gen_random_uuid(),company_id uuid,recipient_user_id uuid,kind text,title text,body text,action_key text,action_id uuid,read_at timestamptz);create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language plpgsql as $$declare n uuid;begin insert into public.app_notifications(company_id,recipient_user_id,kind,title,body,action_key,action_id) values($1,$2,$3,$4,$5,$6,$7) returning id into n;return n;end$$;");
 for(const suffix of ['', '_validators','_reminders','_schedule'])await exec(await readFile('docs/candidates/checkout_report_registration'+suffix+'.sql.review-only','utf8'));
 await client.query("insert into checkout_report_registration_private.rollout values($1,'2026-10-01',true)",[A]);
 // Exact observed production legacy body, no new vehicle foundation installed.
 await exec("CREATE OR REPLACE FUNCTION private.save_daily_report_vehicle_usage(p_report_id uuid, p_worker_id uuid, p_vehicle_id uuid, p_route_assignment_id uuid, p_odometer_km numeric)\n RETURNS void\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO ''\nAS $function$\ndeclare\n  v_user uuid:=auth.uid();\n  v_company uuid;\n  v_status text;\n  v_current numeric;\n  scope_before jsonb;\nbegin\n  if v_user is null then raise exception '\u30ed\u30b0\u30a4\u30f3\u304c\u5fc5\u8981\u3067\u3059'; end if;\n\n  select m.company_id into v_company\n  from public.company_members m\n  where m.user_id=v_user\n  limit 1;\n  if v_company is null then raise exception '\u4f1a\u793e\u3078\u306e\u6240\u5c5e\u304c\u5fc5\u8981\u3067\u3059'; end if;\n\n  if not exists(select 1 from public.daily_reports where id=p_report_id and company_id=v_company) then raise exception '\u65e5\u5831\u3092\u78ba\u8a8d\u3067\u304d\u307e\u305b\u3093'; end if;\n  scope_before:=payroll_scope_private.report_sources(p_report_id);\n  perform payroll_scope_private.lock_scopes(scope_before->'scopes');\n  select d.status into v_status\n  from public.daily_reports d\n  where d.id=p_report_id and d.company_id=v_company\n  for update;\n  if payroll_scope_private.report_sources(p_report_id) is distinct from scope_before then raise exception 'daily report payroll scope changed' using errcode='40001'; end if;\n  if v_status is null then raise exception '\u65e5\u5831\u3092\u78ba\u8a8d\u3067\u304d\u307e\u305b\u3093'; end if;\n  if v_status<>'draft' then raise exception '\u78ba\u5b9a\u6e08\u307f\u65e5\u5831\u306f\u76f4\u63a5\u5909\u66f4\u3067\u304d\u307e\u305b\u3093'; end if;\n\n  if not exists(\n    select 1 from public.daily_report_workers w\n    where w.report_id=p_report_id and w.worker_id=p_worker_id\n  ) then\n    raise exception '\u65e5\u5831\u306e\u793e\u54e1\u60c5\u5831\u3092\u78ba\u8a8d\u3067\u304d\u307e\u305b\u3093';\n  end if;\n\n  if p_vehicle_id is not null and not exists(\n    select 1 from public.vehicles v\n    where v.id=p_vehicle_id and v.company_id=v_company and v.is_active=true\n  ) then\n    raise exception '\u8eca\u4e21\u3092\u78ba\u8a8d\u3067\u304d\u307e\u305b\u3093';\n  end if;\n\n  if p_route_assignment_id is not null and not exists(\n    select 1 from public.route_assignments r\n    where r.id=p_route_assignment_id\n      and r.company_id=v_company\n      and r.is_active=true\n  ) then\n    raise exception '\u30eb\u30fc\u30c8\u3092\u78ba\u8a8d\u3067\u304d\u307e\u305b\u3093';\n  end if;\n\n  if p_odometer_km is not null and p_odometer_km<0 then\n    raise exception '\u8d70\u884c\u8ddd\u96e2\u3092\u78ba\u8a8d\u3057\u3066\u304f\u3060\u3055\u3044';\n  end if;\n\n  if p_vehicle_id is not null and p_odometer_km is not null then\n    select v.odometer_km into v_current\n    from public.vehicles v\n    where v.id=p_vehicle_id and v.company_id=v_company\n    for update;\n\n    if p_odometer_km<v_current then\n      raise exception '\u73fe\u5728\u306e\u8d70\u884c\u8ddd\u96e2\u3088\u308a\u5c0f\u3055\u3044\u6570\u5024\u306f\u767b\u9332\u3067\u304d\u307e\u305b\u3093';\n    end if;\n\n    update public.vehicles\n    set odometer_km=p_odometer_km,\n        updated_by=v_user,\n        updated_at=now()\n    where id=p_vehicle_id and company_id=v_company;\n  end if;\n\n  update public.daily_report_workers\n  set vehicle_id=p_vehicle_id,\n      route_assignment_id=p_route_assignment_id,\n      odometer_km=p_odometer_km\n  where report_id=p_report_id and worker_id=p_worker_id;\nend\n$function$\n;");
 eq(await q("select md5(prosrc) v from pg_proc where oid='private.save_daily_report_vehicle_usage(uuid,uuid,uuid,uuid,numeric)'::regprocedure"),'f78e35bf948cc4702f9d65d28d0ac0e6','Observed legacy vehicle writer exact source');
 const legacyIn=id(720),legacyOut=id(721),legacyVehicle=id(722);
 await client.query("insert into vehicles(id,company_id,display_name,odometer_km) values($1,$2,'Legacy test',100)",[legacyVehicle,A]);
 await client.query("insert into attendance_verifications values($1,$3,$4,$5,null,'clock_in','2026-10-22 08:00Z','2026-10-22',null,null,$6),($2,$3,$4,$5,null,'clock_out','2026-10-22 17:00Z','2026-10-22',$1,null,$6)",[legacyIn,legacyOut,A,W,SITE,legacyVehicle]);
 const legacyReport=await draft('2026-10-22',W,[]);
 await client.query('update attendance_verifications set daily_report_id=$1 where id=any($2::uuid[])',[legacyReport,[legacyIn,legacyOut]]);
 eq(await q('select checkout_report_registration_private.inputs_complete($1) v',[legacyReport]),false,'Legacy clock vehicle requires saved same vehicle and odometer');
 await client.query('select private.save_daily_report_vehicle_usage($1,$2,$3,null,110)',[legacyReport,W,legacyVehicle]);
 eq(await q('select checkout_report_registration_private.inputs_complete($1) v',[legacyReport]),true,'Legacy saved vehicle works without claims/framework');
 await exec('alter function private.save_daily_report_vehicle_usage(uuid,uuid,uuid,uuid,numeric) set search_path=public');
 eq(await q('select checkout_report_registration_private.inputs_complete($1) v',[legacyReport]),false,'Changed legacy writer contract cannot unlock');
 await exec("alter function private.save_daily_report_vehicle_usage(uuid,uuid,uuid,uuid,numeric) set search_path=''");

 await client.query("select public.save_daily_report_signature($1,'representative','Legacy reporter',$2::jsonb)",[legacyReport,signature]);
 eq((await q('select public.read_pending_checkout_report_registration() v')).items.find(x=>x.report_id===legacyReport).blocking,false,'Legacy original save/sign unlocks reporter gate');
 await client.query("select public.save_daily_report_signature($1,'supervisor','Legacy supervisor',$2::jsonb)",[legacyReport,signature]);
 await exec("create table private.vehicle_usage_rollout(company_id uuid,enabled boolean);create table vehicle_usage_claims(source_clock_in_id uuid,company_id uuid,driver_worker_id uuid,vehicle_id uuid,work_date date,ended_at timestamptz);create table vehicle_meter_events(id uuid primary key,source_clock_in_id uuid,company_id uuid,driver_worker_id uuid,vehicle_id uuid,work_date date,previous_km numeric,current_km numeric,distance_km numeric);");
 await exec(await readFile('supabase/migrations/20261008162618_attach_vehicle_meter_to_report.sql','utf8'));

 const sourceIn=id(700),sourceOut=id(701),vehicle=id(702),event=id(703);
 await client.query("insert into attendance_verifications values($1,$3,$4,$5,null,'clock_in','2026-10-24 08:00Z','2026-10-24',null,null,$6),($2,$3,$4,$5,null,'clock_out','2026-10-24 17:00Z','2026-10-24',$1,null,$6)",[sourceIn,sourceOut,A,W,SITE,vehicle]);
 const gate=()=>q('select public.read_pending_checkout_report_registration() v');
 eq((await gate()).items[0].registration_state,'report_missing','Source-chain report initially missing');
 const sourceReport=await draft('2026-10-24',W,[]);
 await client.query('update attendance_verifications set daily_report_id=$1',[sourceReport]);
 await client.query("insert into vehicles(id,company_id,display_name,odometer_km) values($1,$2,'Strong test',100)",[vehicle,A]);
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
 eq(await q('select checkout_report_registration_private.projection_complete($1,$2) v',[sourceReport,W]),true,'Original dual sign creates formal attendance and normal payroll detail: '+JSON.stringify(await q("select jsonb_build_object('report',to_jsonb(r),'worker',to_jsonb(w),'attendance',(select jsonb_agg(to_jsonb(a)) from attendance_entries a where a.worker_id=w.worker_id and a.work_date between date_trunc('month',r.report_date)::date and (date_trunc('month',r.report_date)+interval '1 month - 1 day')::date),'payroll',(select jsonb_agg(to_jsonb(p)) from payroll_statements p where p.worker_id=w.worker_id and p.period_start=date_trunc('month',r.report_date)::date)) v from daily_reports r join daily_report_workers w on w.report_id=r.id where r.id=$1",[sourceReport])));
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
