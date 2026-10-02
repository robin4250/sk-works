revoke insert,update,delete on public.company_payroll_adjustment_settings
from authenticated;
revoke insert,update,delete on public.payroll_adjustment_audit_log
from authenticated;
revoke insert,update,delete on public.payroll_adjustment_types
from authenticated;
revoke insert,update,delete on public.payroll_adjustments
from authenticated;
revoke insert,update,delete on public.worker_personnel_profiles
from authenticated;

revoke delete on public.work_attendance_selections from authenticated;
revoke delete on public.work_vehicle_route_selections from authenticated;
