-- Apply existing disposable invoice/payroll fixtures first (runner documents them).
alter table public.worker_payroll_settings add column paid_leave_granted_days numeric default 10;
alter table public.attendance_entries add column night_hours numeric default 0;
alter table public.companies add column payroll_payment_day integer default 25,
 add column payroll_payment_month_offset integer default 1,add column payroll_closing_day integer default 31;
create table public.paid_leave_requests(id uuid primary key default gen_random_uuid(),batch_id uuid,company_id uuid,worker_id uuid,requested_by uuid,leave_date date,status text,
 reviewed_by uuid,reviewed_at timestamptz,review_note text,updated_at timestamptz);
-- ASSERTIONS
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
insert into public.attendance_entries(company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-03','day',1,0,0);
insert into public.paid_leave_requests(batch_id,company_id,worker_id,requested_by,leave_date,status)
values('80000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','2026-08-03','pending'),
('80000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','2026-08-04','pending');
do $$begin
 begin perform public.decide_paid_leave_request('80000000-0000-0000-0000-000000000001','approve'); raise exception 'worked leave approval allowed'; exception when others then if sqlerrm<>'attendance exists for requested paid leave, use attendance correction first' then raise; end if; end;
 if exists(select 1 from public.paid_leave_requests where leave_date='2026-08-03' and (status<>'pending' or reviewed_at is not null)) then raise exception 'rejected overlap changed history'; end if;
 if public.decide_paid_leave_request('80000000-0000-0000-0000-000000000002','approve')<>'approved' then raise exception 'clean leave approval rejected'; end if;
end $$;
-- Legacy overlaps remain historically approved, but are excluded from payroll day counts.
insert into public.paid_leave_requests(batch_id,company_id,worker_id,requested_by,leave_date,status,reviewed_at)
values('80000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','2026-08-03','approved','2026-08-01T12:34:56Z');
select private.refresh_automatic_payroll_internal('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-03');
select private.sync_payroll_attendance_detail('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-03');
do $$begin
 if (select detail->>'有給日数' from public.payroll_statements where period_start='2026-08-01')<>'1' then raise exception 'overlap counted as paid leave'; end if;
 if (select reviewed_at from public.paid_leave_requests where batch_id='80000000-0000-0000-0000-000000000003')<>'2026-08-01T12:34:56Z'::timestamptz then raise exception 'historical approval timestamp rewritten'; end if;
end $$;
-- Positive overtime alone also counts as work, even when base attendance is zero.
insert into public.attendance_entries(company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-04','day',0,1,0);
select private.sync_payroll_attendance_detail('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-03');
do $$begin
 if (select detail->>'有給日数' from public.payroll_statements where period_start='2026-08-01')<>'0' then raise exception 'overtime-only overlap'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false);
do $$begin
 begin perform public.decide_paid_leave_request('80000000-0000-0000-0000-000000000001','reject'); raise exception 'cross-company leave decision'; exception when others then if sqlerrm<>'management permission required' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
-- Zero-work placeholders do not hide a historical approved leave in payroll.
insert into public.attendance_entries(company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-05','day',0,0,0);
insert into public.paid_leave_requests(company_id,worker_id,leave_date,status,reviewed_at)
values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-05','approved','2026-08-01T12:34:56Z');
select private.sync_payroll_attendance_detail('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2026-08-03');
do $$begin if (select detail->>'有給日数' from public.payroll_statements where period_start='2026-08-01')<>'1' then raise exception 'zero-work placeholder suppressed leave'; end if; end $$;
-- Future records do not enter today's payroll attendance/leave counters.
insert into public.payroll_statements(worker_id,company_id,period_start,period_end,gross_pay,deductions,net_pay,detail)
values('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','2099-01-01','2099-01-31',0,0,0,'{}');
insert into public.attendance_entries(company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2099-01-03','day',1,1,0);
insert into public.paid_leave_requests(company_id,worker_id,leave_date,status)
values('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2099-01-04','approved');
select private.sync_payroll_attendance_detail('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','2099-01-03');
do $$declare d jsonb; begin
 select detail into d from public.payroll_statements where period_start='2099-01-01';
 if d->>'出勤日数'<>'0' or d->>'残業時間'<>'0' or d->>'有給日数'<>'0' then raise exception 'future payroll counters'; end if;
end $$;
select set_config('request.jwt.claim.sub','',false);
do $$begin
 begin perform public.decide_paid_leave_request('80000000-0000-0000-0000-000000000001','approve'); raise exception 'unauthenticated leave decision'; exception when others then if sqlerrm<>'management permission required' then raise; end if; end;
end $$;
