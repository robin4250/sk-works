// Disposable PostgreSQL verification; never connects to Supabase or production.
// npm install --prefix /tmp/sko-sql-runtime --save-exact @electric-sql/pglite@0.3.14
// node tool/verify_invoice_approval_sql.mjs /tmp/sko-sql-runtime/node_modules/@electric-sql/pglite/dist/index.js
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
if(!process.argv[2]) throw Error('Pass installed PGlite module path; see script comments.');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const db=new PGlite();
try {
 await db.exec(read('supabase/tests/invoice_stamp_approval_workflow.sql'));
 await db.exec(read('supabase/migrations/20261005081500_invoice_approval_workflow.sql'));
 await db.exec(read('supabase/migrations/20261007221757_invoice_stamp_policy_and_approval_history.sql'));
 await db.exec(read('supabase/tests/invoice_stamp_approval_assertions.sql'));
 console.log('Invoice approval assertions passed');
 const [fixture,assertions]=read('supabase/tests/payroll_private_bank_assertions.sql').split('-- ASSERTIONS');
 await db.exec(fixture);
 await db.exec(read('supabase/migrations/20261007222051_payroll_statement_private_bank_details.sql'));
 await db.exec(assertions);
 console.log('Payroll private bank assertions passed');
 const [payFixture,payAssertions]=read('supabase/tests/payroll_pay_type_metadata_assertions.sql').split('-- ASSERTIONS');
 await db.exec(payFixture);
 await db.exec(read('supabase/migrations/20261007021000_worker_monthly_salary_mode.sql'));
 await db.exec(read('supabase/migrations/20261008001025_payroll_statement_pay_type_metadata.sql'));
 await db.exec(payAssertions);
 console.log('Payroll pay type metadata assertions passed');
 const [confirmFixture,confirmAssertions]=read('supabase/tests/payroll_assigned_confirmation_assertions.sql').split('-- ASSERTIONS');
 await db.exec(confirmFixture);
 await db.exec(read('supabase/migrations/20261004110609_add_payroll_review_confirmation.sql'));
 await db.exec(read('supabase/migrations/20261004111520_confirm_payroll_review_month.sql'));
 await db.exec(read('supabase/migrations/20261008004129_payroll_assigned_confirmation_notifications.sql'));
 await db.exec(read('supabase/migrations/20261008010518_payroll_confirmation_document_metadata.sql'));
 await db.exec(confirmAssertions);
 console.log('Assigned payroll confirmation assertions passed');
 const [employeeFixture,employeeAssertions]=read('supabase/tests/employee_registered_identity_assertions.sql').split('-- ASSERTIONS');
 const employeeDb=new PGlite();
 try {
 await employeeDb.exec(employeeFixture);
 await employeeDb.exec(read('supabase/migrations/20261008004843_employee_registered_identity.sql'));
 await employeeDb.exec(employeeAssertions);
 await employeeDb.exec(read('supabase/migrations/20261008004843_employee_registered_identity.sql'));
 } finally {await employeeDb.close();}
 console.log('Employee identity assertions and repeat migration passed');
} finally {await db.close();}
