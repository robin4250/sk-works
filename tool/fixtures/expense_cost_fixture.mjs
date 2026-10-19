import fs from 'node:fs';
import assert from 'node:assert/strict';

export async function setupExpenseCostFixture(db) {
  const read = path => fs.readFileSync(path, 'utf8');
  const source = read('tool/verify_route_billing_invoice_integration.mjs');
  const fixture = source.match(/await db\.exec\(`([\s\S]*?)`\);/)[1];
  assert.ok(!fixture.includes('${'));
  await db.exec(fixture);
  await db.exec(`do $$begin if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role;end if;end $$;`);
  await db.exec(`
    alter table companies add column name text default '検証会社', add column company_seal_style text default 'legacy';
    alter table workers add primary key(id), add column user_id uuid, add column status text default 'active', add column partner_company_id uuid;
    alter table attendance_entries add column worker_id uuid;
    alter table invoices add primary key(id), add column invoice_seal_frozen boolean default false;
    alter table private.route_visit_reports add column created_at timestamptz default now();
    create table attendance_verifications(company_id uuid,source_clock_in_id uuid,event_type text);
    create table company_approval_assignees(company_id uuid,user_id uuid);
    create table partner_companies(id uuid primary key,company_id uuid,name text);
    create table partner_payment_settings(company_id uuid,partner_company_id uuid,
      daily_rate_yen integer default 0,overtime_hour_rate_yen integer default 0,early_hour_rate_yen integer default 0,
      night_day_rate_yen integer default 0,night_overtime_hour_rate_yen integer default 0,
      holiday_day_rate_yen integer default 0,holiday_overtime_hour_rate_yen integer default 0,
      holiday_night_day_rate_yen integer default 0,holiday_night_overtime_hour_rate_yen integer default 0,
      welfare_rate numeric default 0,tax_rate numeric default 10,rate_formula jsonb default '{}',allowances jsonb default '[]');
    create table payment_certificates(id uuid primary key default gen_random_uuid(),company_id uuid,partner_company_id uuid,
      period_start date,period_end date,status text default 'draft',revision integer default 1,
      gross_amount integer,deductions integer,net_amount integer,snapshot jsonb default '{}',
      automatic_calculation boolean default true,calculation_blocked boolean default false,updated_at timestamptz);
    create table payroll_statements(id uuid primary key,company_id uuid,worker_id uuid,period_end date,workflow_state text,revision integer);
    create function public.payroll_manager_visibility(uuid) returns boolean language sql as $$select false$$;
  `);
  const original = read('supabase/migrations/20261006173142_common_rate_formula_invoice_hourly.sql');
  await db.exec(original.slice(0, original.indexOf('CREATE OR REPLACE FUNCTION private.refresh_automatic_invoice')));
  await db.exec(read('supabase/migrations/20261008035509_invoice_registered_method_amounts_and_formula_labels.sql'));
  await db.exec(read('supabase/migrations/20261006180455_fix_rate_formula_combined_multipliers.sql'));
  const seal = JSON.parse(read('supabase/tests/fixtures/route_invoice_foundation_20261012.json'));
  await db.exec(read('supabase/migrations/20261009011357_company_seal_aoyagi_style.sql')
    .match(/create function private\.aoyagi_reisho_name_supported[\s\S]*?\$\$;/)[0]);
  for (const key of ['seal','first_freeze','preserve_seal','manual_override','invoice']) await db.exec(seal[key]);
  await db.exec(`create trigger zz_company_seal_snapshot before insert or update on invoices for each row execute function private.preserve_invoice_company_seal_snapshot();
    create trigger invoice_manual_override before update on invoices for each row execute function private.invoice_manual_override_guard();`);
  await db.exec(read('supabase/migrations/20261012053842_route_customer_billing_connection.sql'));
  for (const path of ['20261010044054_expense_personal_submission.sql','20261010140111_expense_review_allocation.sql',
    '20261010141814_expense_document_details.sql','20261010152829_expense_personal_revision.sql']) {
    await db.exec(read('supabase/migrations/' + path));
  }
  const foundation = JSON.parse(read('supabase/tests/fixtures/expense_cost_foundation_20261012.json'));
  for (const key of ['capture_expense_document','expense_review_command','expense_review_workspace',
    'refresh_automatic_invoice','certificate_calculation_rows','refresh_automatic_payment_certificate']) await db.exec(foundation[key]);
  await db.exec(read('supabase/migrations/20261012112410_expense_settlement_method_choices.sql'));
}
