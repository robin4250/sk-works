alter policy "users can mark own notifications read"
on public.app_notifications
using (recipient_user_id = (select auth.uid()))
with check (recipient_user_id = (select auth.uid()));

alter policy "users can read own notifications"
on public.app_notifications
using (recipient_user_id = (select auth.uid()));

alter policy "worker or attendance manager can read attendance entries"
on public.attendance_entries
using (
  exists (
    select 1
    from public.workers w
    where w.id = attendance_entries.worker_id
      and w.company_id = attendance_entries.company_id
      and w.user_id = (select auth.uid())
  )
  or private.has_company_feature(
    attendance_entries.company_id,
    'can_manage_attendance'
  )
);

alter policy "company members can read daily reports"
on public.daily_reports
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = daily_reports.company_id
      and cm.user_id = (select auth.uid())
  )
);

alter policy "worker or authorized manager can read payroll statements"
on public.payroll_statements
using (
  exists (
    select 1
    from public.workers w
    where w.id = payroll_statements.worker_id
      and w.user_id = (select auth.uid())
  )
  or private.has_company_feature(
    payroll_statements.company_id,
    'can_manage_payroll'
  )
);

alter policy "users can insert own profile"
on public.user_profiles
with check (user_id = (select auth.uid()));

alter policy "users can read own profile"
on public.user_profiles
using (user_id = (select auth.uid()));

alter policy "users can update own profile"
on public.user_profiles
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
