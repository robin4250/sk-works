// Isolated PostgreSQL regression checks. No external database connection.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const {PGlite} = await import(pathToFileURL(path.resolve(process.argv[2])).href);
const db = new PGlite();
try {
  await db.exec(read('supabase/tests/company_seal_visibility_fixture.sql'));
  const originalInvoice = read('supabase/migrations/20261005104500_invoice_branding_images.sql');
  const invoiceStart = originalInvoice.indexOf('create or replace function public.invoice_document_settings()');
  await db.exec(originalInvoice.slice(invoiceStart, originalInvoice.indexOf('-- Register the logo', invoiceStart)));
  const originalPayroll = read('supabase/migrations/20261008044613_payroll_financial_condition_attention.sql');
  const payrollStart = originalPayroll.indexOf('create or replace function private.payroll_document_metadata(');
  await db.exec(originalPayroll.slice(payrollStart, originalPayroll.indexOf('$$;', payrollStart) + 3));
  await db.exec(`select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
    create table test_before_invoice as select public.invoice_document_settings() metadata;
    create table test_before_payroll as select id,private.payroll_document_metadata(id) metadata from public.payroll_statements;
    create table test_before_money as select id,gross_pay,deductions,net_pay,detail from public.payroll_statements;
    create table test_before_policy as select oid from pg_policy where polrelid='public.companies'::regclass;`);
  await db.exec(read('supabase/migrations/20261008072619_company_seal_visibility.sql'));
  await db.exec(read('supabase/tests/company_seal_visibility_assertions.sql'));
  console.log('Company seal visibility permissions, isolation, document metadata and financial/history preservation passed');
} finally {
  await db.close();
}
