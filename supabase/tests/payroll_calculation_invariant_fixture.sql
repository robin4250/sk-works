-- Disposable harness prerequisites only. Never run this fixture in production.
alter table public.worker_payroll_settings
 add column family_monthly numeric default 0,
 add column transport_monthly numeric default 0,
 add column income_tax_monthly numeric default 0,
 add column resident_tax_monthly numeric default 0,
 add column social_insurance_monthly numeric default 0,
 add column other_deduction_monthly numeric default 0,
 add column custom_deductions jsonb default '[]';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
alter table public.companies
 add column payroll_payment_day integer default 25,
 add column payroll_payment_month_offset integer default 1,
 add column payroll_closing_day integer default 31;
