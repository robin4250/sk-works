-- Default new payroll adjustments to the latest existing payslip period for
-- the selected worker so deductions/additions are visible on that statement.

create or replace function public.payroll_adjustment_latest_statement_period(
  p_worker_id uuid
)
returns table(
  period_start date,
  period_end date
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  access jsonb := public.payroll_adjustment_access();
  cid uuid;
begin
  if coalesce((access ->> 'can_manage')::boolean, false) is not true then
    raise exception 'payroll adjustment manage permission required';
  end if;

  cid := (access ->> 'company_id')::uuid;

  return query
  select ps.period_start, ps.period_end
  from public.payroll_statements ps
  where ps.company_id = cid
    and ps.worker_id = p_worker_id
  order by ps.period_end desc, ps.created_at desc
  limit 1;
end;
$function$;

revoke execute on function public.payroll_adjustment_latest_statement_period(uuid)
  from public, anon;
grant execute on function public.payroll_adjustment_latest_statement_period(uuid)
  to authenticated;
