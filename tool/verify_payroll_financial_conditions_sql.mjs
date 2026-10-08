// Disposable PostgreSQL regression test; no external database connection.
import fs from 'node:fs';import path from 'node:path';import {fileURLToPath,pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);const db=new PGlite();
try {
 await db.exec(read('supabase/tests/invoice_stamp_approval_workflow.sql'));
 await db.exec(read('supabase/tests/payroll_private_bank_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/payroll_pay_type_metadata_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/paid_leave_attendance_overlap_assertions.sql').split('-- ASSERTIONS')[0]);
 const [fixture,assertions]=read('supabase/tests/payroll_financial_condition_assertions.sql').split('-- ASSERTIONS');
 await db.exec(fixture);
 await db.exec(read('supabase/migrations/20261008042817_prevent_paid_leave_attendance_overlap.sql'));
 await db.exec(read('supabase/migrations/20261004105043_dedupe_generation_setting_notifications.sql'));
 await db.exec(read('supabase/migrations/20261008044613_payroll_financial_condition_attention.sql'));
 const triggerBefore=(await db.query("select oid from pg_catalog.pg_trigger where tgrelid='public.paid_leave_requests'::regclass and tgname='paid_leave_refresh_generation_setting_issues'")).rows[0]?.oid;
 await db.exec(read('supabase/migrations/20261008044613_payroll_financial_condition_attention.sql'));
 const triggerAfter=(await db.query("select oid from pg_catalog.pg_trigger where tgrelid='public.paid_leave_requests'::regclass and tgname='paid_leave_refresh_generation_setting_issues'")).rows[0]?.oid;
 if(!triggerBefore || triggerBefore!==triggerAfter) throw new Error('Reapplying must preserve the existing paid-leave trigger.');
 await db.exec(assertions);
 console.log('Payroll financial condition warnings assertions passed');
}finally{await db.close();}
