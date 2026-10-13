// Reproduce PDF regression fixtures from disposable PostgreSQL table writes.
// Never connects to Supabase. See test/fixtures/payroll_persisted_money/README.md.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const cid='10000000-0000-0000-0000-000000000001';
const wid='40000000-0000-0000-0000-000000000001';
let failures=0;
function check(condition,label,actual){if(condition) console.log(`PASS ${label}`);else {failures++;console.error(`FAIL ${label}: ${JSON.stringify(actual)}`);}}
const db=new PGlite();
try {
 await db.exec(read('supabase/tests/invoice_stamp_approval_workflow.sql'));
 await db.exec(read('supabase/tests/payroll_private_bank_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/payroll_pay_type_metadata_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/payroll_calculation_invariant_fixture.sql'));
 await db.exec(read('supabase/migrations/20261006162510_payroll_flexible_earnings_deductions_payment_day.sql'));
 await db.exec(read('supabase/migrations/20261007021000_worker_monthly_salary_mode.sql'));
 await db.exec(read('supabase/migrations/20261008001025_payroll_statement_pay_type_metadata.sql'));
 await db.exec(read('supabase/migrations/20261008035104_stabilize_automatic_payroll_totals.sql'));
 await db.exec(`create table public.paid_leave_requests(company_id uuid,worker_id uuid,leave_date date,status text); alter table public.workers add column status text default 'active',add column affiliation text default 'employee',add column hire_date date;`);
 await db.exec(read('supabase/migrations/20261008040428_generate_fixed_monthly_payroll_without_attendance.sql'));

 await db.exec(`alter table public.attendance_entries add primary key(id),add column night_hours numeric default 0;
 alter table public.worker_payroll_settings add column night_daily numeric default 15000,
 add column night_overtime numeric default 2000,add column night_early numeric default 2000,
 add column holiday_daily numeric default 13500,add column holiday_overtime numeric default 2000,
 add column holiday_early numeric default 2000,add column holiday_night_daily numeric default 16000,
 add column holiday_night_overtime numeric default 2500,add column holiday_night_early numeric default 2500,
 add column allowance_name_1 text,add column allowance_1 numeric default 0;
 delete from public.payroll_statements; delete from public.attendance_entries;
 update public.worker_payroll_settings set pay_type='daily',day_daily=10000,day_overtime=1563,day_early=1563,
 monthly_salary_yen=0,custom_earnings='[]',custom_deductions='[]' where worker_id='${wid}';`);
 await db.exec(read('supabase/tests/payroll_live_linkage_snapshot.sql'));
 await db.exec(`create trigger attendance_refresh_payroll after insert or update or delete on public.attendance_entries
 for each row execute function private.attendance_refresh_payroll();
 create trigger attendance_sync_payroll_detail after insert or update or delete on public.attendance_entries
 for each row execute function private.attendance_sync_payroll_detail();
 create trigger settings_refresh_payroll after insert or update on public.worker_payroll_settings
 for each row execute function private.settings_refresh_payroll();
 create trigger paid_leave_sync_payroll_detail after insert or update or delete on public.paid_leave_requests
 for each row execute function private.paid_leave_sync_payroll_detail();`);
 // Optional reviewed migration(s) under test can override snapshots without editing them.
 for(const migration of process.argv.slice(3)) await db.exec(read(migration));
 const row=async()=> (await db.query(`select id,gross_pay,deductions,net_pay,revision,approved_ids,detail from public.payroll_statements
 where company_id='${cid}' and worker_id='${wid}' and period_start='2026-08-01'`)).rows[0];
 const audits=async()=> (await db.query('select count(*)::int n from public.payroll_audit')).rows[0].n;
 const insert=async(id,date,category,units,ot=0)=>db.exec(`insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
 values('${id}','${cid}','${wid}','70000000-0000-0000-0000-000000000001','${date}','${category}',${units},${ot},0);`);
 const entry='90000000-0000-0000-0000-000000000001';
 await insert(entry,'2026-08-03','day',1,2);
 let before=await row();check(before.gross_pay===13126&&Number(before.detail['出勤日数'])===1&&Number(before.detail['残業時間'])===2,'attendance INSERT persists amount and detail',before);
 await db.exec(`update public.payroll_statements set approved_ids=array['00000000-0000-0000-0000-000000000002'::uuid] where id='${before.id}';`);
 before=await row();
 const beforeAudit=await audits();
 await db.exec(`update public.attendance_entries set overtime_hours=2 where id='${entry}';`);
 let after=await row();check(after.revision===before.revision&&(await audits())===beforeAudit,'same-value attendance UPDATE adds no revision/audit',after);
 check(JSON.stringify(after.approved_ids)===JSON.stringify(before.approved_ids),'same-value attendance keeps actual assigned confirmations',after);
 await db.exec(`update public.attendance_entries set overtime_hours=3 where id='${entry}';`);
 after=await row();check(after.gross_pay===14689&&after.revision===before.revision+1,'attendance UPDATE recalculates exactly once through old/new trigger calls',after);
 check(after.approved_ids.length===0,'material attendance edit clears previous confirmations',after);
 check(Number(after.detail['残業時間'])===3,'edited overtime detail matches persisted amount',after);
 before=after;
 await db.exec(`insert into public.worker_payroll_settings(worker_id,company_id,pay_type,day_daily,day_overtime,day_early,monthly_salary_yen,custom_earnings,custom_deductions)
 values('${wid}','${cid}','daily',12000,1875,1875,0,'[]','[{"name":"道具代","amount_yen":1100}]')
 on conflict(worker_id,company_id) do update set day_daily=excluded.day_daily,day_overtime=excluded.day_overtime,day_early=excluded.day_early,custom_deductions=excluded.custom_deductions;`);
 after=await row();check(after.gross_pay===17625&&after.deductions===1100&&after.net_pay===16525&&after.revision===before.revision+1,'settings UPSERT recalculates amount/deduction once',after);
 check(Number(after.detail['基本給'])===12000&&Number(after.detail['道具代'])===-1100,'settings UPSERT refreshes named persisted detail',after);
 before=after;
 await db.exec(`update public.worker_payroll_settings set day_daily=12000 where worker_id='${wid}';`);
 after=await row();check(after.revision===before.revision&&after.gross_pay===before.gross_pay,'repeat settings save is idempotent',after);
 await db.exec(`insert into public.paid_leave_requests(company_id,worker_id,leave_date,status) values('${cid}','${wid}','2026-08-04','pending');`);
 check(Number((await row()).detail['有給日数'])===0,'pending leave is excluded');
 await db.exec(`update public.paid_leave_requests set status='approved' where leave_date='2026-08-04';`);
 after=await row();check(Number(after.detail['有給日数'])===1&&after.gross_pay===before.gross_pay,'approved leave refreshes count without inventing amount',after);
 await db.exec(`update public.paid_leave_requests set status='cancelled' where leave_date='2026-08-04';`);
 check(Number((await row()).detail['有給日数'])===0,'cancelled leave clears persisted count');
 const half='90000000-0000-0000-0000-000000000002';
 await insert(half,'2026-08-05','holiday',.5);
 after=await row();check(Number(after.detail['出勤日数'])===1.5&&Number(after.detail['休出日数'])===.5,'half-day holiday units retained in detail',after);
 before=after;
 await db.exec(`delete from public.attendance_entries where id='${half}';`);
 after=await row();check(after.gross_pay===17625&&Number(after.detail['休出日数'])===0&&after.revision===before.revision+1,'attendance DELETE removes amount and holiday detail once',after);
 await db.exec(`delete from public.attendance_entries where id='${entry}';`);
 check((await row())===undefined,'deleting final daily attendance removes empty automatic draft');
 await db.exec(`update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=300000,day_daily=10000,day_overtime=2000,day_early=2000,custom_deductions='[]' where worker_id='${wid}';`);
 await insert(entry,'2026-08-03','day',1,2);
 before=await row();check(before.gross_pay===304000&&Number(before.detail['基本給'])===300000,'monthly table INSERT preserves fixed base and overtime once',before);
 const monthlyAudit=await audits();
 await db.exec(`update public.attendance_entries set overtime_hours=2 where id='${entry}';`);
 after=await row();check(after.revision===before.revision&&after.gross_pay===304000&&(await audits())===monthlyAudit,'monthly repeat trigger calls are stable',after);
 await db.exec(`update public.attendance_entries set overtime_hours=3 where id='${entry}';`);
 after=await row();check(after.gross_pay===306000&&after.revision===before.revision+1,'monthly actual edit increments revision and amount once',after);
 // Persist actual rows generated by the preceding attendance/settings triggers.
 const saveFixture=async(name)=>{
  const value=await row(); delete value.id;
  const dir=path.join(root,'test/fixtures/payroll_persisted_money');
  fs.mkdirSync(dir,{recursive:true});
  fs.writeFileSync(path.join(dir,name+'.json'),JSON.stringify(value,null,2)+'\n');
 };
 await saveFixture('actual_monthly');
 await db.exec(`update public.worker_payroll_settings set custom_deductions='[{"name":"道具代","amount_yen":1100}]' where worker_id='${wid}';`);
 await saveFixture('actual_deduction');
 for (const mode of ['daily','hourly','monthly']) {
  await db.exec(`delete from public.attendance_entries; delete from public.payroll_statements;
   update public.worker_payroll_settings set pay_type='${mode}',monthly_salary_yen=${mode==='monthly'?300000:0},
   day_daily=${mode==='hourly'?12000:10000},day_overtime=1563,day_early=1563,
   family_monthly=2000,transport_monthly=1000,custom_earnings='[{"name":"資格手当","amount_yen":5000},{"name":"資格手当","amount_yen":2000}]',
   custom_deductions='[{"name":"道具代","amount_yen":1100},{"name":"道具代","amount_yen":400}]'
   where worker_id='${wid}';`);
  let index=0;
  for (const category of ['day','night','holiday','holiday_night']) {
   index++;
   await insert(`90000000-0000-0000-0000-00000000000${index}`,`2026-08-0${index+2}`,category,.5,1);
  }
  await db.exec(`update public.attendance_entries set early_hours=.5 where company_id='${cid}' and worker_id='${wid}';`);
  console.log('EXTENDED_PDF_FIXTURE',mode,JSON.stringify(await row()));
  await saveFixture('actual_'+mode+'_categories');
 }
 console.log('Actual notification functions were not provided: notice delivery/count is outside this harness.');
} finally {await db.close();}
if(failures) process.exitCode=1;
