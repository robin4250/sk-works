-- Disposable full-trigger integration: actual attendance/settings table writes.
do $$declare
 cid uuid:='10000000-0000-0000-0000-000000000001';
 wid uuid:='40000000-0000-0000-0000-000000000001';
 r public.payroll_statements%rowtype; before_row jsonb; before_audit int;
 mode text; gross_expected int; sum_rows int;
begin
 foreach mode in array array['daily','hourly','monthly'] loop
  delete from public.attendance_entries; delete from public.payroll_statements;
  update public.worker_payroll_settings set pay_type=mode,monthly_salary_yen=case when mode='monthly' then 300000 else 0 end,
   day_daily=case when mode='hourly' then 12000 else 10000 end,day_overtime=1563,day_early=1563,
   family_monthly=2000,transport_monthly=1000,
   custom_earnings='[{"name":"資格手当","amount_yen":5000},{"name":"資格手当","amount_yen":2000}]',
   custom_deductions='[{"name":"道具代","amount_yen":1100},{"name":"道具代","amount_yen":400}]'
  where worker_id=wid;
  insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
  select gen_random_uuid(),cid,wid,'70000000-0000-0000-0000-000000000001',date '2026-08-02'+i::int,
   category,.5,1,.5 from unnest(array['day','night','holiday','holiday_night']) with ordinality c(category,i);
  select * into r from public.payroll_statements where company_id=cid and worker_id=wid and period_start='2026-08-01';
  gross_expected:=case mode when 'daily' then 49345 when 'hourly' then 50345 else 344345 end;
  if r.gross_pay<>gross_expected or r.deductions<>1500 or r.net_pay<>gross_expected-1500 then
   raise exception '% monetary policy changed: %',mode,row_to_json(r); end if;
  if r.detail->>'家族手当'<>'2000' or r.detail->>'道具代'<>'-1500' then
   raise exception '% missing family or grouped deduction',mode; end if;
  sum_rows:=(r.detail->>'基本給')::int+(r.detail->>'残業手当')::int+(r.detail->>'早出手当')::int
   +(r.detail->>'家族手当')::int+(r.detail->>'交通費')::int+7000
   +coalesce((r.detail->>'夜勤基本給')::int,0)+coalesce((r.detail->>'休日基本給')::int,0)
   +coalesce((r.detail->>'休日夜勤基本給')::int,0);
  if sum_rows<>r.gross_pay then raise exception '% named earnings do not reconcile %<>%',mode,sum_rows,r.gross_pay; end if;
  if mode='monthly' and (r.detail->>'基本給'<>'300000' or r.detail->>'夜勤基本給'<>'7500'
   or r.detail->>'休日基本給'<>'6750' or r.detail->>'休日夜勤基本給'<>'8000') then
   raise exception 'monthly non-day bases hidden'; end if;
  update public.payroll_statements set approved_ids=array['00000000-0000-0000-0000-000000000002'::uuid] where id=r.id;
  select to_jsonb(ps) into before_row from public.payroll_statements ps where id=r.id;
  select count(*) into before_audit from public.payroll_audit;
  update public.attendance_entries set early_hours=early_hours where worker_id=wid;
  select * into r from public.payroll_statements where id=r.id;
  if r.gross_pay<>(before_row->>'gross_pay')::int or r.revision<>(before_row->>'revision')::int
   or cardinality(r.approved_ids)<>1 or r.detail is distinct from before_row->'detail'
   or (select count(*) from public.payroll_audit)<>before_audit then raise exception '% noop unstable',mode; end if;
  update public.payroll_statements set workflow_state='finalized' where id=r.id;
  select to_jsonb(ps) into before_row from public.payroll_statements ps where id=r.id;
  update public.worker_payroll_settings set family_monthly=9999,monthly_salary_yen=500000 where worker_id=wid;
  select * into r from public.payroll_statements where id=r.id;
  if to_jsonb(r) is distinct from before_row then raise exception '% finalized history rewritten',mode; end if;
 end loop;
end $$;
