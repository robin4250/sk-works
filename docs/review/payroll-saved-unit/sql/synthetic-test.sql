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
 social_insurance_monthly numeric,other_deduction_monthly numeric,custom_deductions jsonb default '[]'::jsonb,
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
insert into public.worker_payroll_settings(company_id,worker_id,pay_type,day_daily,night_daily,
 day_overtime,night_overtime,day_early,night_early,allowance_name_1,allowance_1)
values('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','daily',16000,18000,2000,2500,2000,2500,'合成手当',700);
insert into public.attendance_entries values
('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','2026-09-01','day',1,2,0,0,array['合成手当']),
('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','2026-09-02','night',0.5,1,0,0,array['合成手当']);
insert into public.payroll_statements values
('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','2026-09-01','2026-09-30',32900,0,32900,true,'draft','{}',now());
create temp table baseline(detail jsonb,gross integer,deductions integer,net integer);
do $$
declare cid uuid:='00000000-0000-0000-0000-000000000001';wid uuid:='00000000-0000-0000-0000-000000000002';r record;b record;items jsonb;
begin
 perform private.baseline_sync(cid,wid,'2026-09-01');
 insert into baseline select detail,gross_pay,deductions,net_pay from public.payroll_statements;
 perform private.sync_payroll_attendance_detail(cid,wid,'2026-09-01');
 select * into r from public.payroll_statements;select * into b from baseline;
 assert r.detail-'attendance_unit_evidence'=b.detail,'existing detail changed';
 assert (r.gross_pay,r.deductions,r.net_pay)=(b.gross,b.deductions,b.net),'money changed';
 items:=r.detail#>'{attendance_unit_evidence,items}';
 assert (select count(*) from jsonb_array_elements(items) x where x->>'name'='基本給')=2,'category evidence missing';
 assert (select sum((x->>'amount_yen')::numeric) from jsonb_array_elements(items) x where x->>'name'='基本給')=25000,'wrong category sum';
 assert (select (x->>'quantity')::numeric from jsonb_array_elements(items) x where x->>'name'='合成手当')=2,'allowance distinct days missing';
 update public.payroll_statements set workflow_state='finalized';
 perform private.sync_payroll_attendance_detail(cid,wid,'2026-09-01');
 assert (select detail from public.payroll_statements)=r.detail,'finalized detail changed';
 update public.payroll_statements set workflow_state='draft';
 update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=290000;
 perform private.baseline_sync(cid,wid,'2026-09-01');
 truncate baseline;insert into baseline select detail-'attendance_unit_evidence',gross_pay,deductions,net_pay from public.payroll_statements;
 perform private.sync_payroll_attendance_detail(cid,wid,'2026-09-01');
 select * into r from public.payroll_statements;select * into b from baseline;
 assert r.detail-'attendance_unit_evidence'=b.detail,'monthly existing detail changed';
 assert (r.gross_pay,r.deductions,r.net_pay)=(b.gross,b.deductions,b.net),'monthly money changed';
 assert exists(select 1 from jsonb_array_elements(r.detail#>'{attendance_unit_evidence,items}') x where x->>'unit'='month' and (x->>'amount_yen')::numeric=290000),'monthly fixed missing';
end $$;
rollback;
