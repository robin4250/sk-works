// Disposable current-source payroll regression; never connects to Supabase.
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
 for(const migration of ['supabase/migrations/20261008042817_prevent_paid_leave_attendance_overlap.sql','supabase/migrations/20261008043151_align_future_attendance_monthly_payroll_boundary.sql','supabase/migrations/20261008045401_preserve_payroll_named_financial_details.sql']) await db.exec(read(migration));
 await db.exec(read('supabase/tests/payroll_split_site_allowance_assertions.sql'));
 console.log('PASS split-site allowance real-trigger assertions: duplicate names, insertion order, unchanged confirmations, partial/all deletion');
} finally {await db.close();}
