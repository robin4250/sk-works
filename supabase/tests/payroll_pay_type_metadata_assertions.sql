-- Additional disposable prerequisites for the production draft calculator.
create table public.worker_payroll_settings(worker_id uuid,company_id uuid,pay_type text,
 rate_formula jsonb,hourly_rate_yen numeric,day_daily numeric,day_overtime numeric,day_early numeric,
 monthly_salary_yen numeric,calculation_daily_base_yen numeric,primary key(worker_id,company_id));
alter table public.payroll_statements alter column id set default gen_random_uuid();
alter table public.payroll_statements add column automatic_calculation boolean default true,
 add column workflow_state text default 'draft',add column approver_ids uuid[],add column approved_ids uuid[],
 add column calculation_blocked boolean,add column calculation_fingerprint text,add column revision int default 1,
 add column created_at timestamptz default now(),add column updated_at timestamptz;
create table public.attendance_entries(id uuid default gen_random_uuid(),company_id uuid,worker_id uuid,
 site_id uuid,work_date date,work_category text,base_man_days numeric,overtime_hours numeric,early_hours numeric,allowance_names text[]);
create table public.site_calculation_source_preferences(company_id uuid,site_id uuid,output_type text,source text,trade_company_id uuid);
create table public.trade_companies(id uuid,company_id uuid);
create table public.trade_company_contracts(company_id uuid,trade_company_id uuid,contract_method text,
 daily_rate_yen numeric,monthly_rate_yen numeric,square_meter_unit_price_yen numeric,square_meter_quantity numeric,contract_amount_yen numeric);
create table public.payroll_audit(company_id uuid,statement_id uuid,revision int,action text,actor_id uuid);
create function private.payroll_approver_ids(uuid) returns uuid[] language sql as $$select '{}'::uuid[]$$;
insert into public.worker_payroll_settings values
('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','hourly','{"base_mode":"hourly","overtime_multiplier":1.25}',1500,12000,1875,1875,0,0),
('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','monthly','{}',0,10000,2000,2000,300000,10000);
-- ASSERTIONS
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_config('test.account_access_denied','',false);
do $$declare r record; begin
 select * into r from public.my_payroll_statement_rows_with_adjustments();
 if r.detail->>'pay_type'<>'hourly' or r.detail->>'hourly_rate_yen'<>'1500' then raise exception 'hourly settings metadata'; end if;
 if r.gross_pay<>10500 or r.net_pay<>9500 then raise exception 'metadata altered payroll'; end if;
 update public.payroll_statements set detail='{"給与方式":"月給","hourly_rate_yen":777,"rate_formula":{"overtime_multiplier":1.7}}' where id=r.id;
 select * into r from public.my_payroll_statement_rows_with_adjustments();
 if r.detail->>'pay_type'<>'monthly' or r.detail->>'hourly_rate_yen'<>'777' or r.detail->'rate_formula'->>'overtime_multiplier'<>'1.7' then raise exception 'historical metadata overwritten'; end if;
 update public.payroll_statements set detail='{"pay_type":"daily"}' where id=r.id;
 if (select detail->>'pay_type' from public.my_payroll_statement_rows_with_adjustments())<>'daily' then raise exception 'daily historical priority'; end if;
end $$;
-- The production calculator sees already-resolved stored rates: 1500*8 + 1875*2.
insert into public.attendance_entries(company_id,worker_id,site_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','2026-08-03','day',1,2,0),
('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002','70000000-0000-0000-0000-000000000001','2026-08-03','day',1,1,0);
select private.refresh_automatic_payroll('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-03');
do $$declare r record; begin
 select * into r from public.payroll_statements where period_start='2026-08-01' and worker_id='40000000-0000-0000-0000-000000000001';
 if r.gross_pay<>15750 or r.detail->>'pay_type'<>'hourly' then raise exception 'hourly total/metadata'; end if;
 update public.worker_payroll_settings set pay_type='daily' where worker_id=r.worker_id;
 if (select detail->>'pay_type' from public.my_payroll_statement_rows_with_adjustments() where id=r.id)<>'hourly' then raise exception 'future settings relabeled history'; end if;
end $$;
select private.refresh_automatic_payroll('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002','2026-08-03');
do $$begin
 if not exists(select 1 from public.payroll_statements where worker_id='40000000-0000-0000-0000-000000000002' and period_start='2026-08-01' and gross_pay=302000 and detail->>'pay_type'='monthly') then raise exception 'monthly total/metadata'; end if;
end $$;
select set_config('test.account_access_denied','1',false);
do $$begin
 if exists(select 1 from public.my_payroll_statement_rows_with_adjustments() where detail->'bank_account'<>'{}'::jsonb) then raise exception 'metadata bypassed account guard'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false);
do $$begin
 if exists(select 1 from public.my_payroll_statement_rows_with_adjustments()) then raise exception 'cross company metadata'; end if;
end $$;
