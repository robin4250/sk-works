-- Mirrors production migration 20261004175148.
-- Remove unintended direct/public-style privileges from recent operational tables
-- without widening RLS or changing application behavior.

revoke all privileges on table public.attendance_correction_items from anon;
revoke all privileges on table public.attendance_correction_requests from anon;
revoke all privileges on table public.generation_setting_issues from anon;
revoke all privileges on table public.partner_payment_settings from anon;
revoke all privileges on table public.payment_certificates from anon;

revoke insert, update, delete, truncate, references, trigger
on table public.approved_paid_leave_payroll_rows from authenticated;

revoke truncate, references, trigger
on table public.attendance_correction_items from authenticated;

revoke delete, truncate, references, trigger
on table public.attendance_correction_requests from authenticated;

revoke truncate, references, trigger
on table public.generation_setting_issues from authenticated;

revoke truncate, references, trigger
on table public.partner_payment_settings from authenticated;

revoke truncate, references, trigger
on table public.payment_certificates from authenticated;
