-- Run only in the disposable harness. Real monthly normalization trigger is installed.
do $$
declare
  cid uuid := '10000000-0000-0000-0000-000000000001';
  wid uuid := '40000000-0000-0000-0000-000000000002';
  today date := (current_timestamp at time zone 'Asia/Tokyo')::date;
  next_month date := (date_trunc('month',today)+interval '1 month')::date;
  ps public.payroll_statements%rowtype;
  rev int; audits int;
begin
  delete from public.payroll_statements where company_id=cid and worker_id=wid;
  delete from public.payroll_audit;
  delete from public.attendance_entries where company_id=cid and worker_id=wid;
  update public.worker_payroll_settings set pay_type='monthly', monthly_salary_yen=300000,
    day_daily=10000,day_overtime=2000,day_early=2000,custom_earnings='[]',custom_deductions='[]'
  where company_id=cid and worker_id=wid;
  insert into public.attendance_entries(company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
  values(cid,wid,today,'day',1,1,0),(cid,wid,next_month,'day',1,8,0);
  if date_trunc('month',today+1)=date_trunc('month',today) then
    insert into public.attendance_entries(company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
    values(cid,wid,today+1,'day',2,5,0);
  end if;
  perform private.refresh_automatic_payroll_internal(cid,wid,today);
  select * into ps from public.payroll_statements where company_id=cid and worker_id=wid
    and period_start=date_trunc('month',today)::date;
  if ps.gross_pay<>302000 or ps.net_pay<>302000 then
    raise exception 'eligible ordinary day replacement lost monthly/overtime: %/%',ps.gross_pay,ps.net_pay;
  end if;
  -- Always future even when today is the last day of a month. No attendance earns wages.
  perform private.refresh_automatic_payroll_internal(cid,wid,next_month);
  select * into ps from public.payroll_statements where company_id=cid and worker_id=wid and period_start=next_month;
  if ps.gross_pay<>300000 or ps.net_pay<>300000 or (ps.detail->>'出勤日数')::numeric<>0 then
    raise exception 'future attendance reduced fixed monthly salary: %',row_to_json(ps);
  end if;
  rev:=ps.revision; select count(*) into audits from public.payroll_audit;
  update public.payroll_statements set approved_ids=array['00000000-0000-0000-0000-000000000002'::uuid] where id=ps.id;
  perform private.refresh_automatic_payroll_internal(cid,wid,next_month);
  select * into ps from public.payroll_statements where id=ps.id;
  if ps.revision<>rev or cardinality(ps.approved_ids)<>1 or
      (select count(*) from public.payroll_audit)<>audits then
    raise exception 'same future month refresh changed approvals/revision/audit';
  end if;
  -- Future attendance changes remain irrelevant to the current calculation fingerprint.
  update public.attendance_entries set base_man_days=3,overtime_hours=12
    where company_id=cid and worker_id=wid and work_date=next_month;
  perform private.refresh_automatic_payroll_internal(cid,wid,next_month);
  select * into ps from public.payroll_statements where id=ps.id;
  if ps.gross_pay<>300000 or ps.revision<>rev or cardinality(ps.approved_ids)<>1 then
    raise exception 'future attendance edit changed monthly draft';
  end if;
  -- Frozen and manual payroll remain untouched by the internal calculator.
  update public.payroll_statements set workflow_state='finalized' where id=ps.id;
  update public.worker_payroll_settings set monthly_salary_yen=350000 where company_id=cid and worker_id=wid;
  perform private.refresh_automatic_payroll_internal(cid,wid,next_month);
  if (select gross_pay from public.payroll_statements where id=ps.id)<>300000 then
    raise exception 'finalized monthly statement was rewritten';
  end if;
end $$;
