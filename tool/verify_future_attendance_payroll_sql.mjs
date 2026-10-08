// Disposable PostgreSQL integration. No Supabase connection or production writes.
// node tool/verify_future_attendance_payroll_sql.mjs /path/to/pglite/dist/index.js
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const {PGlite} = await import(pathToFileURL(path.resolve(process.argv[2])).href);
const db = new PGlite();
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
try {
  await db.exec(read('supabase/tests/invoice_stamp_approval_workflow.sql'));
  await db.exec(read('supabase/tests/payroll_private_bank_assertions.sql').split('-- ASSERTIONS')[0]);
  await db.exec(read('supabase/tests/payroll_pay_type_metadata_assertions.sql').split('-- ASSERTIONS')[0]);
  await db.exec(read('supabase/tests/payroll_calculation_invariant_fixture.sql'));
  await db.exec(read('supabase/migrations/20261006162510_payroll_flexible_earnings_deductions_payment_day.sql'));
  await db.exec(read('supabase/migrations/20261007021000_worker_monthly_salary_mode.sql'));
  await db.exec(read('supabase/migrations/20261008035104_stabilize_automatic_payroll_totals.sql'));
  await db.exec(`create table public.paid_leave_requests(company_id uuid,worker_id uuid,leave_date date,status text);
    alter table public.attendance_entries add column night_hours numeric default 0;
    delete from public.payroll_statements; delete from public.payroll_audit;`);
  await db.exec(read('supabase/migrations/20261008043151_align_future_attendance_monthly_payroll_boundary.sql'));
  await db.exec(read('supabase/tests/future_attendance_payroll_assertions.sql'));
  // A forward migration replay must preserve the same function behavior.
  await db.exec(read('supabase/migrations/20261008043151_align_future_attendance_monthly_payroll_boundary.sql'));
  await db.exec(read('supabase/tests/future_attendance_payroll_assertions.sql'));
  console.log('Future attendance payroll boundary assertions and replay passed');
} finally { await db.close(); }
