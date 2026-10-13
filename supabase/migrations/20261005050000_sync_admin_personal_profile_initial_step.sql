-- Mirrors production migration sync_admin_personal_profile_initial_step.
-- Completing the existing combined personal/company profile step also marks
-- the administrator personal-information step complete.

create or replace function private.sync_initial_personal_profile_progress()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.company_profile_completed then
    new.personal_profile_completed := true;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_initial_personal_profile_progress
on public.company_initial_setup_progress;

create trigger sync_initial_personal_profile_progress
before insert or update of company_profile_completed
on public.company_initial_setup_progress
for each row
execute function private.sync_initial_personal_profile_progress();

revoke execute on function private.sync_initial_personal_profile_progress()
from public, anon, authenticated;

update public.company_initial_setup_progress
set personal_profile_completed = true
where company_profile_completed = true;
