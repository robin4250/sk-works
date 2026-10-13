-- Expose approved paid leave as an attendance-safe read model.
-- This deliberately does not mutate attendance records; consumers can merge
-- approved leave into calendars/statements without duplicating source data.

create or replace view public.approved_paid_leave_attendance as
select
  r.id as paid_leave_request_id,
  r.company_id,
  r.person_id,
  r.leave_date as attendance_date,
  r.days as paid_leave_days,
  r.approved_by,
  r.approved_at,
  r.note
from public.paid_leave_requests r
where r.status = 'approved';

comment on view public.approved_paid_leave_attendance is
  'Approved paid leave projected for attendance/payroll consumers; source of truth remains paid_leave_requests.';

grant select on public.approved_paid_leave_attendance to authenticated;
