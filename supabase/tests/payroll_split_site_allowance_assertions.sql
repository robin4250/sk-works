-- Isolated current-source regression. Company data, rates and date-based allowance
-- semantics are fixtures; no production rows or new financial rules are created.
do $$
declare
 cid uuid := '10000000-0000-0000-0000-000000000001';
 wid uuid := '40000000-0000-0000-0000-000000000001';
 confirmer uuid := '00000000-0000-0000-0000-000000000002';
 a uuid; b uuid; r public.payroll_statements%rowtype; before_row jsonb;
 before_audit integer; reverse_order boolean;
begin
 foreach reverse_order in array array[false,true] loop
  delete from public.attendance_entries; delete from public.payroll_statements;
  update public.worker_payroll_settings set pay_type='daily',day_daily=10000,
   night_daily=15000,day_overtime=0,night_overtime=0,day_early=0,night_early=0,
   monthly_salary_yen=0,custom_earnings='[]',custom_deductions='[]',
   family_monthly=0,transport_monthly=0,income_tax_monthly=0,
   resident_tax_monthly=0,social_insurance_monthly=0,other_deduction_monthly=0,
   allowance_name_1='道具手当',allowance_1=500
  where company_id=cid and worker_id=wid;
  a := gen_random_uuid(); b := gen_random_uuid();
  if reverse_order then
   insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days,allowance_names)
   values(b,cid,wid,'70000000-0000-0000-0000-000000000002','2026-08-02','night',.5,array['道具手当','道具手当']);
  end if;
  insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days,allowance_names)
  values(a,cid,wid,'70000000-0000-0000-0000-000000000001','2026-08-02','day',.5,array['道具手当','道具手当']);
  if not reverse_order then
   insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days,allowance_names)
   values(b,cid,wid,'70000000-0000-0000-0000-000000000002','2026-08-02','night',.5,array['道具手当','道具手当']);
  end if;
  select * into r from public.payroll_statements where company_id=cid and worker_id=wid and period_start='2026-08-01';
  if r.gross_pay<>13000 or r.net_pay<>13000 or r.deductions<>0
    or (r.detail->>'道具手当')::integer<>500 or (r.detail->>'出勤日数')::numeric<>1 then
   raise exception 'split-site allowance counted repeatedly or insertion order changed total (reverse=%): %',reverse_order,row_to_json(r);
  end if;
  if (r.detail->>'基本給')::integer+(r.detail->>'道具手当')::integer<>r.gross_pay then
   raise exception 'persisted display rows do not reconcile with split-site total';
  end if;
  update public.payroll_statements set approved_ids=array[confirmer] where id=r.id;
  select to_jsonb(ps) into before_row from public.payroll_statements ps where id=r.id;
  select count(*) into before_audit from public.payroll_audit;
  update public.attendance_entries set allowance_names=allowance_names,base_man_days=base_man_days where id in (a,b);
  select * into r from public.payroll_statements where id=r.id;
  if r.revision<>(before_row->>'revision')::integer or r.gross_pay<>13000
    or r.approved_ids<>array[confirmer] or r.detail is distinct from before_row->'detail'
    or (select count(*) from public.payroll_audit)<>before_audit then
   raise exception 'unchanged split-site save changed confirmations/revision/detail/audit';
  end if;
  delete from public.attendance_entries where id=a;
  select * into r from public.payroll_statements where id=r.id;
  if r.gross_pay<>8000 or r.net_pay<>8000 or (r.detail->>'道具手当')::integer<>500
    or (r.detail->>'出勤日数')::numeric<>.5 or cardinality(r.approved_ids)<>0 then
   raise exception 'deleting one site lost remaining date allowance or retained obsolete confirmation: %',row_to_json(r);
  end if;
  delete from public.attendance_entries where id=b;
  if exists(select 1 from public.payroll_statements where company_id=cid and worker_id=wid and period_start='2026-08-01') then
   raise exception 'deleting last daily attendance retained a phantom allowance draft';
  end if;
 end loop;
end $$;
