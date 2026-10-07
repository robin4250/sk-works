alter table public.worker_payroll_settings
  add column if not exists pay_type text not null default 'daily',
  add column if not exists monthly_salary_yen numeric not null default 0,
  add column if not exists calculation_daily_base_yen numeric not null default 0;

alter table public.worker_payroll_settings drop constraint if exists worker_payroll_settings_pay_type_check;
alter table public.worker_payroll_settings add constraint worker_payroll_settings_pay_type_check
  check (pay_type in ('daily','hourly','monthly'));

create or replace function private.apply_monthly_salary_to_statement()
returns trigger language plpgsql security definer set search_path=''
as $$
declare s public.worker_payroll_settings%rowtype; regular_day_base integer:=0;
begin
  if not new.automatic_calculation or new.workflow_state<>'draft' then return new; end if;
  select * into s from public.worker_payroll_settings where company_id=new.company_id and worker_id=new.worker_id;
  if s.pay_type<>'monthly' then return new; end if;
  select coalesce(round(sum(coalesce(ae.base_man_days,0)*coalesce(s.day_daily,0))),0)::integer
  into regular_day_base from public.attendance_entries ae
  where ae.company_id=new.company_id and ae.worker_id=new.worker_id
    and ae.work_date between new.period_start and new.period_end
    and coalesce(ae.work_category,'day')='day';
  new.gross_pay:=greatest(coalesce(new.gross_pay,0)-regular_day_base+round(coalesce(s.monthly_salary_yen,0))::integer,0);
  new.net_pay:=greatest(new.gross_pay-coalesce(new.deductions,0),0);
  new.detail:=coalesce(new.detail,'{}'::jsonb)||jsonb_build_object(
    '給与方式','月給','月固定給',round(coalesce(s.monthly_salary_yen,0))::integer,
    '計算用1日基本ベース',round(coalesce(s.calculation_daily_base_yen,0))::integer);
  return new;
end $$;
drop trigger if exists aa_monthly_salary_statement_guard on public.payroll_statements;
create trigger aa_monthly_salary_statement_guard before insert or update of gross_pay on public.payroll_statements
for each row execute function private.apply_monthly_salary_to_statement();

create or replace function private.apply_monthly_salary_detail()
returns trigger language plpgsql security definer set search_path=''
as $$
declare s public.worker_payroll_settings%rowtype;
begin
  if not new.automatic_calculation or new.workflow_state<>'draft' then return new; end if;
  select * into s from public.worker_payroll_settings where company_id=new.company_id and worker_id=new.worker_id;
  if s.pay_type='monthly' then
    new.detail:=coalesce(new.detail,'{}'::jsonb)||jsonb_build_object(
      '基本給',round(coalesce(s.monthly_salary_yen,0))::integer,'給与方式','月給',
      '月固定給',round(coalesce(s.monthly_salary_yen,0))::integer,
      '計算用1日基本ベース',round(coalesce(s.calculation_daily_base_yen,0))::integer);
  end if;
  return new;
end $$;
drop trigger if exists zz_monthly_salary_detail_guard on public.payroll_statements;
create trigger zz_monthly_salary_detail_guard before insert or update of detail on public.payroll_statements
for each row execute function private.apply_monthly_salary_detail();
