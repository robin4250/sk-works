revoke all on table public.worker_personnel_change_requests
from anon, authenticated;
revoke all on table public.worker_personnel_change_approvals
from anon, authenticated;

grant select on table public.worker_personnel_profiles
to authenticated;
