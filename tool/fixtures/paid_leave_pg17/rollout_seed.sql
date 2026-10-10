-- Synthetic monetary values/UUIDs only. Disposable isolated DB only.
delete from public.paid_leave_requests;
delete from public.payroll_statements;
delete from public.attendance_entries;
update public.worker_payroll_settings set pay_type='daily',day_daily=12000,
 monthly_salary_yen=0,rate_formula='{}',custom_earnings='[]',custom_deductions='[]',
 family_monthly=0,transport_monthly=0,income_tax_monthly=0,resident_tax_monthly=0,
 social_insurance_monthly=0,other_deduction_monthly=0;
insert into public.workers(id,company_id,name,status,affiliation)
values ('40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','Synthetic finalized auto','active','employee'),
 ('40000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','Synthetic finalized manual','active','employee');
insert into public.worker_payroll_settings
select (jsonb_populate_record(null::public.worker_payroll_settings,to_jsonb(s)||jsonb_build_object('worker_id',v.id))).*
from public.worker_payroll_settings s
cross join (values ('40000000-0000-0000-0000-000000000003'::uuid),('40000000-0000-0000-0000-000000000004'::uuid)) v(id)
where s.worker_id='40000000-0000-0000-0000-000000000001';
insert into public.payroll_statements(worker_id,company_id,period_start,period_end,gross_pay,deductions,net_pay,detail,automatic_calculation,workflow_state,calculation_fingerprint)
select id,'10000000-0000-0000-0000-000000000001',
 date_trunc('month',now() at time zone 'Asia/Tokyo')::date,
 (date_trunc('month',now() at time zone 'Asia/Tokyo')+interval '1 month - 1 day')::date,
 amount,0,amount,jsonb_build_object('probe',probe),automatic,state,'synthetic-before'
from (values
 ('40000000-0000-0000-0000-000000000001'::uuid,10000,'automatic-draft',true,'draft'),
 ('40000000-0000-0000-0000-000000000002'::uuid,42000,'manual-draft',false,'draft'),
 ('40000000-0000-0000-0000-000000000003'::uuid,55000,'automatic-finalized',true,'finalized'),
 ('40000000-0000-0000-0000-000000000004'::uuid,66000,'manual-finalized',false,'finalized')) v(id,amount,probe,automatic,state);
insert into public.payroll_statements(worker_id,company_id,period_start,period_end,gross_pay,deductions,net_pay,detail,automatic_calculation,workflow_state)
values ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
 (date_trunc('month',now() at time zone 'Asia/Tokyo')-interval '1 month')::date,
 (date_trunc('month',now() at time zone 'Asia/Tokyo')-interval '1 day')::date,
 7000,0,7000,'{"probe":"past"}',true,'draft');
insert into public.paid_leave_requests(company_id,worker_id,leave_date,status)
select company_id,id,(now() at time zone 'Asia/Tokyo')::date,'approved' from public.workers;
