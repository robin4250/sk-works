\set ON_ERROR_STOP on
begin;
create schema private;
create schema payroll_unit_private;
create schema resident_tax_private;
create schema company_checkout_allowance_private;
create table public.worker_payroll_settings(company_id uuid,worker_id uuid,pay_type text,
 day_daily numeric,night_daily numeric,holiday_daily numeric,holiday_night_daily numeric,
 day_overtime numeric,night_overtime numeric,holiday_overtime numeric,holiday_night_overtime numeric,
 day_early numeric,night_early numeric,holiday_early numeric,holiday_night_early numeric,
 monthly_salary_yen numeric,family_monthly numeric,transport_monthly numeric,income_tax_monthly numeric,
 social_insurance_monthly numeric,other_deduction_monthly numeric,custom_deductions jsonb default '[]'::jsonb,rate_formula jsonb default '{}'::jsonb,
 allowance_name_1 text,allowance_1 numeric,allowance_name_2 text,allowance_2 numeric,
 allowance_name_3 text,allowance_3 numeric);
create table public.attendance_entries(company_id uuid,worker_id uuid,site_id uuid,
 work_date date,work_category text,base_man_days numeric,overtime_hours numeric,
 early_hours numeric,night_hours numeric,allowance_names text[]);
create table public.site_calculation_source_preferences(company_id uuid,site_id uuid,output_type text,source text);
create table public.paid_leave_requests(company_id uuid,worker_id uuid,leave_date date,status text);
create table public.payroll_statements(company_id uuid,worker_id uuid,period_start date,period_end date,
 gross_pay integer,deductions integer,net_pay integer,automatic_calculation boolean,workflow_state text,detail jsonb,updated_at timestamptz);
create function payroll_unit_private.resolve_company_common(uuid,uuid,date,date) returns jsonb language sql as $$select '{}'::jsonb$$;
create function resident_tax_private.resolve(uuid,uuid,date) returns jsonb language sql as $$select '{"amount_yen":0}'::jsonb$$;
create function company_checkout_allowance_private.covers_legacy(uuid,uuid,date,integer) returns boolean language sql as $$select false$$;
\ir source-before.sql
alter function private.sync_payroll_attendance_detail(uuid,uuid,date) rename to baseline_sync;
\ir source-after.sql

-- UI save-equivalent payload supplied as a psql quoted JSON value. Synthetic only.
create temp table fixture_input(payload jsonb);
insert into fixture_input values(:'ui_payload'::jsonb);
insert into public.worker_payroll_settings
select (jsonb_populate_record(null::public.worker_payroll_settings,payload||jsonb_build_object(
 'company_id','00000000-0000-4000-8000-000000000001',
 'worker_id','00000000-0000-4000-8000-000000000002'))).* from fixture_input;
insert into public.attendance_entries
select '00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002',
 '00000000-0000-4000-8000-000000000003',date '2026-09-01'+n,'day',1,1.25,0,0,array['役職手当','勤務手当']
from generate_series(0,19)n;
insert into public.payroll_statements values
('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002',
 '2026-09-01','2026-09-30',241000,10000,231000,true,'draft','{"company_seal_enabled":false}',now());
create temp table fixture_results(name text primary key,saved jsonb);
do $$
declare c uuid:='00000000-0000-4000-8000-000000000001';w uuid:='00000000-0000-4000-8000-000000000002';
 b jsonb;r jsonb;
begin
 perform private.baseline_sync(c,w,'2026-09-01');
 select to_jsonb(p)-'updated_at' into b from public.payroll_statements p;
 perform private.sync_payroll_attendance_detail(c,w,'2026-09-01');
 select to_jsonb(p)-'updated_at' into r from public.payroll_statements p;
 assert (r-'detail')=(b-'detail'),'daily totals/state changed';
 assert (r->'detail')-'position_transfer_snapshot'=b->'detail','daily existing detail changed';
 assert (r#>>'{detail,基本給}')::int=200000 and (r#>>'{detail,残業手当}')::int=25000,'daily actual calculation disconnected';
 assert (r#>>'{detail,役職手当}')::int=11000 and (r#>>'{detail,勤務手当}')::int=5000,'saved allowances disconnected';
 assert r#>'{detail,position_transfer_snapshot,items}'=(select payload#>'{rate_formula,position_transfer,items}'from fixture_input),'saved UI payload disconnected';
 insert into fixture_results values('daily',r);
 update public.payroll_statements set workflow_state='finalized';
 select to_jsonb(p) into b from public.payroll_statements p;
 update public.worker_payroll_settings set rate_formula='{}',day_daily=99999;
 update public.attendance_entries set overtime_hours=99;
 perform private.sync_payroll_attendance_detail(c,w,'2026-09-01');
 select to_jsonb(p) into r from public.payroll_statements p;
 assert r=b,'finalized snapshot/original row changed';
 insert into fixture_results values('finalized',r-'updated_at');
 update public.attendance_entries set overtime_hours=1.25;
 update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=290000,
 rate_formula=(select payload->'rate_formula'from fixture_input);
 update public.payroll_statements set workflow_state='draft',gross_pay=331000,net_pay=321000;
 perform private.baseline_sync(c,w,'2026-09-01');
 select to_jsonb(p)-'updated_at' into b from public.payroll_statements p;
 perform private.sync_payroll_attendance_detail(c,w,'2026-09-01');
 select to_jsonb(p)-'updated_at' into r from public.payroll_statements p;
 assert (r-'detail')=(b-'detail'),'monthly totals/state changed';
 assert (r->'detail')-'position_transfer_snapshot'=(b->'detail')-'position_transfer_snapshot','monthly existing detail changed';
 assert (r#>>'{detail,基本給}')::int=290000 and (r#>>'{detail,残業手当}')::int=25000,'monthly actual calculation disconnected';
 insert into fixture_results values('monthly_saved_enabled',r);
 -- Invalid transfer does not invalidate payroll; renderer must refuse transfer.
 update public.worker_payroll_settings set pay_type='daily',day_daily=10000,
 rate_formula=jsonb_set(rate_formula,'{position_transfer,items,0,amount_yen}','11001');
 update public.payroll_statements set gross_pay=241000,net_pay=231000;
 perform private.sync_payroll_attendance_detail(c,w,'2026-09-01');
 select to_jsonb(p)-'updated_at' into r from public.payroll_statements p;
 insert into fixture_results values('invalid_amount',r);
end$$;
select jsonb_build_object('ui_payload',(select payload from fixture_input),
 'statements',(select jsonb_object_agg(name,saved)from fixture_results));
rollback;
