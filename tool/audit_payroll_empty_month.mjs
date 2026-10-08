// Read-only production-source audit in a disposable database. No production access.
// This describes current unsupported cases; it does not define paid-leave policy.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const db=new PGlite();
const cid='10000000-0000-0000-0000-000000000001';
const wid='40000000-0000-0000-0000-000000000002';
try {
 await db.exec(read('supabase/tests/invoice_stamp_approval_workflow.sql'));
 await db.exec(read('supabase/tests/payroll_private_bank_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/payroll_pay_type_metadata_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/payroll_calculation_invariant_fixture.sql'));
 await db.exec(read('supabase/migrations/20261006162510_payroll_flexible_earnings_deductions_payment_day.sql'));
 await db.exec(read('supabase/migrations/20261007021000_worker_monthly_salary_mode.sql'));
 await db.exec(read('supabase/migrations/20261008001025_payroll_statement_pay_type_metadata.sql'));
 await db.exec(read('supabase/migrations/20261008035104_stabilize_automatic_payroll_totals.sql'));
 await db.exec(`alter table public.workers add column status text default 'active',add column affiliation text default 'employee',add column hire_date date; create schema cron; create table cron.job(jobname text primary key,schedule text,command text); create function cron.schedule(text,text,text) returns bigint language sql as $$insert into cron.job values($1,$2,$3) on conflict(jobname) do update set schedule=excluded.schedule,command=excluded.command returning 1::bigint$$; create table public.paid_leave_requests(company_id uuid,worker_id uuid,leave_date date,status text); alter table public.attendance_entries add column night_hours numeric;`);
 const detailSource=read('supabase/migrations/20261006114652_link_payroll_statement_breakdown.sql');
 await db.exec(detailSource.substring(detailSource.indexOf('create or replace function private.sync_payroll_attendance_detail'),detailSource.indexOf('revoke all on function private.sync_payroll_attendance_detail')));
 await db.exec(read('supabase/migrations/20261008040428_generate_fixed_monthly_payroll_without_attendance.sql'));
 let failures=0;
 function check(ok,label,actual) {if(ok)console.log(`PASS ${label}`);else {failures++;console.error(`FAIL ${label}: ${JSON.stringify(actual)}`);}}

 const acl=(await db.query(`select has_function_privilege('authenticated','private.refresh_automatic_payroll_internal(uuid,uuid,date)','EXECUTE') client_internal,has_function_privilege('anon','private.ensure_monthly_payroll_drafts(date)','EXECUTE') anon_scheduler,has_function_privilege('authenticated','private.ensure_monthly_payroll_drafts(date)','EXECUTE') client_scheduler`)).rows[0];
 check(!acl.client_internal && !acl.anon_scheduler && !acl.client_scheduler,'private calculator/scheduler denied to clients',acl);
 check((await db.query(`select count(*)::int n from cron.job where jobname='payroll-confirmation-daily-jst' and command like '%ensure_monthly_payroll_drafts%enqueue_payroll_confirmation_notifications%'`)).rows[0].n===1,'one cron job generates drafts before notifications');
 const refresh=()=>db.exec(`select private.refresh_automatic_payroll('${cid}','${wid}','2026-08-03');`);
 const rows=async()=>(await db.query(`select gross_pay,net_pay,revision from public.payroll_statements where company_id='${cid}' and worker_id='${wid}' and period_start='2026-08-01'`)).rows;
 await refresh();
 check((await rows())[0]?.gross_pay===300000,'monthly fixed salary without attendance',await rows());
 await db.exec(`insert into public.paid_leave_requests values('${cid}','${wid}','2026-08-03','approved');`);
 await refresh();
 check((await rows())[0]?.gross_pay===300000,'monthly fixed salary with approved leave only',await rows());
 check((await db.query(`select detail->>'有給日数' days,detail->>'出勤日数' work_days from public.payroll_statements where period_start='2026-08-01' and worker_id='${wid}'`)).rows[0].days==='1','approved leave count retained');
 await db.exec(`insert into public.attendance_entries(company_id,worker_id,site_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
 values('${cid}','${wid}','70000000-0000-0000-0000-000000000001','2026-08-03','day',1,0,0);`);
 await refresh(); const before=await rows();
 await db.exec('delete from public.attendance_entries;'); await refresh();
 check(before[0].gross_pay===300000 && (await rows())[0]?.gross_pay===300000,'removing last attendance retains monthly fixed salary',await rows());
 const beforeStable=await rows();await refresh();check(JSON.stringify(await rows())===JSON.stringify(beforeStable),'empty monthly refresh is stable',await rows());
 await db.exec(`create trigger settings_refresh_payroll after insert or update on public.worker_payroll_settings for each row execute function private.settings_refresh_payroll(); update public.worker_payroll_settings set monthly_salary_yen=310000 where worker_id='${wid}';`);
 const currentMonth=(await db.query(`select date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date as month`)).rows[0].month;
 check((await db.query(`select count(*)::int n from public.payroll_statements where company_id='${cid}' and worker_id='${wid}' and period_start=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date and gross_pay=310000`)).rows[0].n===1,'monthly settings save creates current month before attendance',currentMonth);
 await db.exec(`update public.worker_payroll_settings set pay_type='daily',day_daily=10000 where worker_id='${wid}';`);
 await refresh();
 console.log(JSON.stringify({case:'daily approved leave only',policy:'Unimplemented: approved_paid_leave_payroll_rows explicitly defers amount policy',actual:await rows()}));
 await db.exec(`insert into public.attendance_entries(company_id,worker_id,site_id,work_date,work_category,base_man_days,overtime_hours,early_hours,night_hours)
 values('${cid}','${wid}','70000000-0000-0000-0000-000000000001','2026-08-03','day',1,0,0,0);`);
 await refresh(); const beforeNight=await rows();
 await db.exec('update public.attendance_entries set night_hours=3;'); await refresh();
 console.log(JSON.stringify({case:'day category night_hours 0 -> 3',meaning:'UI labels independent 夜間時間 field; monetary calculator does not read night_hours',before:beforeNight,after:await rows()}));

 // A scheduler without an end-user JWT creates eligible current-month salary only.
 await db.exec(`drop trigger settings_refresh_payroll on public.worker_payroll_settings; update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=320000 where worker_id='${wid}'; delete from public.payroll_statements where period_start=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date; select set_config('request.jwt.claim.sub','',false);`);
 await db.exec(`select private.refresh_automatic_payroll('${cid}','${wid}',(current_timestamp at time zone 'Asia/Tokyo')::date);`);
 check((await db.query(`select count(*)::int n from public.payroll_statements where period_start=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date`)).rows[0].n===0,'existing wrapper still ignores missing JWT');
 await db.exec('select private.ensure_monthly_payroll_drafts();');
 check((await db.query(`select count(*)::int n from public.payroll_statements where worker_id='${wid}' and period_start=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date and gross_pay=320000`)).rows[0].n===1,'private scheduler creates monthly draft without fabricated JWT');
 check((await db.query(`select count(*)::int n from public.payroll_audit a join public.payroll_statements ps on ps.id=a.statement_id where ps.period_start=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date and a.actor_id is null`)).rows[0].n===1,'system audit actor is NULL');
 for(const blocked of ["status='inactive'", "status='active',affiliation='partner_company'", "affiliation='employee',hire_date=((date_trunc('month',current_date)+interval '2 months')::date)"]) {
  await db.exec(`delete from public.payroll_statements where period_start=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date; update public.workers set ${blocked} where id='${wid}'; select private.ensure_monthly_payroll_drafts();`);
  check((await db.query(`select count(*)::int n from public.payroll_statements where period_start=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date`)).rows[0].n===0,`scheduler skips ineligible worker: ${blocked}`);
 }
 await db.exec(`update public.workers set status='active',affiliation='employee',hire_date=null where id='${wid}';`);
 const historical=await rows(); await db.exec("select private.ensure_monthly_payroll_drafts('2026-08-03');");
 check(JSON.stringify(await rows())===JSON.stringify(historical),'scheduler does not backfill historical months');
 await db.exec('select private.ensure_monthly_payroll_drafts();');
 await db.exec(`update public.payroll_statements set workflow_state='finalized' where period_start=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date; update public.worker_payroll_settings set monthly_salary_yen=330000 where worker_id='${wid}';`);
 await db.exec('select private.ensure_monthly_payroll_drafts();');
 check((await db.query(`select count(*)::int n from public.payroll_statements where period_start=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date and gross_pay=320000 and workflow_state='finalized'`)).rows[0].n===1,'scheduler protects finalized monthly statement');
 if(failures)process.exitCode=1;
} finally {await db.close();}
