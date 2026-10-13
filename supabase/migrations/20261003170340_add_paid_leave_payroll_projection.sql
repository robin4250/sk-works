create or replace view public.approved_paid_leave_payroll_rows
with (security_invoker = true)
as
select
  r.id as paid_leave_request_id,
  r.company_id,
  r.worker_id,
  r.leave_date,
  1::numeric as paid_leave_days,
  r.reviewed_at as approved_at
from public.paid_leave_requests r
where r.status = 'approved';

revoke all on public.approved_paid_leave_payroll_rows from anon;
grant select on public.approved_paid_leave_payroll_rows to authenticated;

comment on view public.approved_paid_leave_payroll_rows is
  'Approved paid leave source rows for future payroll calculation; amount policy is intentionally not embedded.';
