-- Disposable fixtures required by existing generation issue queries and document metadata.
alter table public.worker_payroll_settings add column night_daily numeric default 0,add column night_overtime numeric default 0,add column night_early numeric default 0,
 add column holiday_daily numeric default 0,add column holiday_overtime numeric default 0,add column holiday_early numeric default 0,
 add column holiday_night_daily numeric default 0,add column holiday_night_overtime numeric default 0,add column holiday_night_early numeric default 0;
alter table public.workers add column partner_company_id uuid,add column employee_number text,add column department text,add column role text,add column hire_date date;
alter table public.companies add column bank_name text,add column bank_branch text,add column bank_account_number text,add column bank_account_holder text;
create table public.sites(id uuid,company_id uuid,name text,customer_id uuid);
create table public.site_financial_settings(site_id uuid,company_id uuid,billing_unit_price_yen numeric,billing_square_meter_unit_price_yen numeric,billing_square_meter_quantity numeric,billing_contract_amount_yen numeric,billing_monthly_rate_yen numeric);
create table public.partner_companies(id uuid,company_id uuid,name text);
create table public.partner_payment_settings(company_id uuid,partner_company_id uuid);
create table public.payroll_confirmers(company_id uuid,user_id uuid,position int);
create table public.payroll_statement_reviews(statement_id uuid,reviewer_id uuid,confirmed_revision int,confirmed_at timestamptz);
create function private.payroll_payment_date(date,uuid,jsonb) returns date language sql as $$select $1$$;
-- ASSERTIONS
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
insert into public.paid_leave_requests(company_id,worker_id,leave_date,status,reviewed_at)
values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-04','approved','2026-08-01T12:34:56Z');
insert into public.attendance_entries(company_id,worker_id,work_date,work_category,base_man_days,night_hours,site_id)
values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-03','day',1,2,'70000000-0000-0000-0000-000000000001');
select private.refresh_automatic_payroll_internal('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-03');
do $$declare a text[]; before_amount int; begin
 select gross_pay into before_amount from public.payroll_statements where period_start='2026-08-01';
 a:=private.payroll_condition_warnings('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-01','2026-08-31');
 if cardinality(a)<>2 then raise exception 'daily/hourly leave and normal-night warnings missing'; end if;
 perform private.refresh_generation_setting_issues('10000000-0000-0000-0000-000000000001');
 perform private.refresh_generation_setting_issues('10000000-0000-0000-0000-000000000001');
 if (select count(*) from public.generation_setting_issues where issue_key like 'payroll-condition:%' and resolved_at is null)<>1 then raise exception 'existing issue dedupe'; end if;
 if (select gross_pay from public.payroll_statements where period_start='2026-08-01')<>before_amount then raise exception 'warning changed monetary total'; end if;
 if jsonb_array_length((select private.payroll_document_metadata(id)->'calculation_warnings' from public.payroll_statements where period_start='2026-08-01'))<>2 then raise exception 'preview warning missing'; end if;
 update public.payroll_statements set workflow_state='finalized' where period_start='2026-08-01';
 if jsonb_array_length((select private.payroll_document_metadata(id)->'calculation_warnings' from public.payroll_statements where period_start='2026-08-01'))<>0 then raise exception 'finalized history warning changed'; end if;
 perform private.refresh_generation_setting_issues('10000000-0000-0000-0000-000000000001');
 if exists(select 1 from public.generation_setting_issues where issue_key like 'payroll-condition:%' and resolved_at is null) then raise exception 'finalized issue unresolved'; end if;
end $$;
-- Valid registered monthly category rates are preserved without a blanket warning.
insert into public.attendance_entries(company_id,worker_id,work_date,work_category,base_man_days,site_id)
values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002','2026-08-03','holiday',1,'70000000-0000-0000-0000-000000000001');
do $$begin
 if cardinality(private.payroll_condition_warnings('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002','2026-08-01','2026-08-31'))<>1 then raise exception 'missing monthly actual rate warning'; end if;
 update public.worker_payroll_settings set holiday_daily=13500 where worker_id='40000000-0000-0000-0000-000000000002';
 if cardinality(private.payroll_condition_warnings('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002','2026-08-01','2026-08-31'))<>0 then raise exception 'registered monthly rates wrongly warned'; end if;
 if cardinality(private.payroll_condition_warnings('10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002','2026-08-01','2026-08-31'))<>0 then raise exception 'cross company condition leak'; end if;
 if has_function_privilege('authenticated','private.payroll_condition_warnings(uuid,uuid,date,date)','EXECUTE') then raise exception 'private financial condition helper exposed'; end if;
end $$;

-- Leave-only month must notify without fabricating a monetary statement.
insert into public.paid_leave_requests(company_id,worker_id,leave_date,status)
values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-07-04','approved');
do $$begin
 if not exists(select 1 from public.generation_setting_issues where issue_key='payroll-condition:40000000-0000-0000-0000-000000000001:2026-07-01' and resolved_at is null) then raise exception 'leave-only issue missing'; end if;
 if exists(select 1 from public.payroll_statements where period_start='2026-07-01') then raise exception 'warning fabricated financial record'; end if;
end $$;
-- Existing registered monthly billing is a complete site mode.
insert into public.sites values('70000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Monthly site','80000000-0000-0000-0000-000000000001');
insert into public.site_financial_settings(site_id,company_id,billing_monthly_rate_yen) values('70000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',500000);
insert into public.attendance_entries(company_id,worker_id,work_date,work_category,base_man_days,site_id)
values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',date_trunc('month',current_date)::date,'day',1,'70000000-0000-0000-0000-000000000001');
select private.refresh_generation_setting_issues('10000000-0000-0000-0000-000000000001');
do $$begin if exists(select 1 from public.generation_setting_issues where issue_key like 'invoice-site:%' and resolved_at is null) then raise exception 'valid monthly site falsely missing'; end if;end $$;
update public.site_financial_settings set billing_monthly_rate_yen=0;
insert into public.trade_companies values('90000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001');
insert into public.trade_company_contracts(company_id,trade_company_id,contract_method,monthly_rate_yen) values('10000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','monthly',500000);
insert into public.site_calculation_source_preferences values('10000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','invoice','trade_company','90000000-0000-0000-0000-000000000001');
select private.refresh_generation_setting_issues('10000000-0000-0000-0000-000000000001');
do $$begin if exists(select 1 from public.generation_setting_issues where issue_key like 'invoice-site:%' and resolved_at is null) then raise exception 'valid selected trade contract falsely missing'; end if;end $$;
