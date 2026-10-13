-- Disposable prerequisites only. Never apply this fixture to a real database.
create role anon;
create role authenticated;
create schema auth;
create schema private;
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
create function private.account_access_allowed() returns boolean language sql stable as $$
 select auth.uid() is not null and coalesce(current_setting('test.account_access_denied',true),'')<>'1'
$$;
create table public.companies(id uuid primary key,name text,postal_code text,address text,phone text,fax text,
 tax_rate numeric,default_welfare_rate numeric,invoice_template_title text,invoice_footer_note text,
 payroll_payment_day integer,updated_at timestamptz);
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.company_private_billing_settings(company_id uuid,bank_name text,bank_branch text,bank_account_type text,
 bank_account_number text,bank_account_holder text,invoice_subject text,invoice_contact_name text,payment_due_text text,
 invoice_logo_base64 text,invoice_seal_base64 text);
create function private.has_company_feature(cid uuid,feature text) returns boolean language sql stable as $$
 select exists(select 1 from public.company_members cm where cm.company_id=cid and cm.user_id=auth.uid() and cm.role in ('owner','admin','manager'))
$$;
create table public.workers(id uuid primary key,company_id uuid,employee_number text,department text,role text,hire_date date);
create table public.payroll_statements(id uuid primary key,worker_id uuid,company_id uuid,workflow_state text,
 automatic_calculation boolean,detail jsonb,period_start date,period_end date,revision integer,gross_pay integer,deductions integer,net_pay integer);
create table public.worker_payroll_settings(worker_id uuid,company_id uuid,pay_type text,rate_formula jsonb,hourly_rate_yen numeric);
create table public.payroll_confirmers(company_id uuid,user_id uuid,position integer);
create table public.user_profiles(user_id uuid,display_name text);
create table public.payroll_statement_reviews(statement_id uuid,reviewer_id uuid,confirmed_revision integer,confirmed_at timestamptz);
create function private.payroll_condition_warnings(uuid,uuid,date,date) returns text[] language sql stable as $$select array['Keep warning']::text[]$$;
create function private.payroll_payment_date(date,uuid,jsonb) returns date language sql stable as $$select '2026-11-25'::date$$;
insert into public.companies(id,name,tax_rate,default_welfare_rate,payroll_payment_day) values
 ('10000000-0000-0000-0000-000000000001','Example One',10,3,25),
 ('10000000-0000-0000-0000-000000000002','Example Two',8,2,20);
insert into public.company_members values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','owner'),
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','admin'),
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','manager'),
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000004','viewer'),
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005','member'),
 ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000006','owner');
insert into public.workers values
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','E001','Construction','Worker','2020-01-01'),
 ('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','E002','Accounts','Clerk','2021-01-01');
insert into public.payroll_statements values
 ('50000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','draft',true,'{"pay_type":"monthly","hourly_rate_yen":777,"rate_formula":{"overtime_multiplier":1.7}}','2026-10-01','2026-10-31',2,300000,10000,290000),
 ('50000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','finalized',true,'{}','2026-10-01','2026-10-31',1,200000,20000,180000);
insert into public.worker_payroll_settings values
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','daily','{}',1500),
 ('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','monthly','{}',0);
insert into public.payroll_confirmers values('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001',1);
insert into public.user_profiles values('00000000-0000-0000-0000-000000000001','Owner One');
insert into public.payroll_statement_reviews values('50000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001',2,'2026-10-31T12:34:56Z');
alter table public.companies enable row level security;
create policy company_member_read on public.companies for select to authenticated using(
 exists(select 1 from public.company_members cm where cm.company_id=companies.id and cm.user_id=(select auth.uid())));
create policy company_admin_update on public.companies for update to authenticated using(
 exists(select 1 from public.company_members cm where cm.company_id=companies.id and cm.user_id=(select auth.uid()) and cm.role in ('owner','admin')))
with check(exists(select 1 from public.company_members cm where cm.company_id=companies.id and cm.user_id=(select auth.uid()) and cm.role in ('owner','admin')));
grant usage on schema auth to authenticated;
grant select(id,name) on public.companies to authenticated;
grant select on public.company_members to authenticated;
grant update on public.companies to authenticated;
revoke all on function private.account_access_allowed() from public,anon,authenticated;
