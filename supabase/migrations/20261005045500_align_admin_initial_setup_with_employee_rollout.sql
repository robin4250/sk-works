-- Mirrors production migration 20261005 align_admin_initial_setup_with_employee_rollout.
-- Admin first-run flow is personal/company setup -> company documents ->
-- qualification settings -> employee preregistration -> employee initial registration.

alter table public.company_initial_setup_progress
  add column if not exists personal_profile_completed boolean not null default false,
  add column if not exists company_documents_reviewed boolean not null default false,
  add column if not exists qualification_settings_reviewed boolean not null default false,
  add column if not exists employee_registration_reviewed boolean not null default false,
  add column if not exists initial_registration_reviewed boolean not null default false;

update public.company_initial_setup_progress
set personal_profile_completed = true,
    company_documents_reviewed = true,
    qualification_settings_reviewed = true,
    employee_registration_reviewed = true,
    initial_registration_reviewed = true
where completed_at is not null;

update public.company_initial_setup_progress
set personal_profile_completed = true
where company_profile_completed = true;

create or replace function private.refresh_initial_setup_completion(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.company_initial_setup_progress p
  set completed_at = case
        when p.personal_profile_completed
         and p.company_profile_completed
         and p.company_documents_reviewed
         and p.qualification_settings_reviewed
         and p.employee_registration_reviewed
         and p.initial_registration_reviewed
        then coalesce(p.completed_at, now())
        else null
      end,
      updated_at = now()
  where p.company_id = p_company_id;
end;
$$;

revoke execute on function private.refresh_initial_setup_completion(uuid)
from public, anon, authenticated;

create or replace function public.admin_initial_setup_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_role text;
  v_progress public.company_initial_setup_progress%rowtype;
begin
  if v_user_id is null then
    return jsonb_build_object('required', false, 'completed', false);
  end if;

  select cm.company_id, cm.role::text
  into v_company_id, v_role
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null then
    return jsonb_build_object('required', false, 'completed', false);
  end if;

  if v_role not in ('owner','admin') then
    return jsonb_build_object('required', false, 'completed', true);
  end if;

  select * into v_progress
  from public.company_initial_setup_progress
  where company_id = v_company_id;

  if not found then
    return jsonb_build_object('required', false, 'completed', true);
  end if;

  return jsonb_build_object(
    'required', v_progress.completed_at is null,
    'completed', v_progress.completed_at is not null,
    'personal_profile_completed', v_progress.personal_profile_completed,
    'company_profile_completed', v_progress.company_profile_completed,
    'company_documents_reviewed', v_progress.company_documents_reviewed,
    'qualification_settings_reviewed', v_progress.qualification_settings_reviewed,
    'employee_registration_reviewed', v_progress.employee_registration_reviewed,
    'initial_registration_reviewed', v_progress.initial_registration_reviewed
  );
end;
$$;

create or replace function public.mark_admin_initial_setup_step(p_step text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company_id uuid;
begin
  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = auth.uid()
    and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  if p_step not in (
    'personal_profile',
    'company_documents',
    'qualification_settings',
    'employee_registration',
    'initial_registration'
  ) then
    raise exception 'invalid initial setup step';
  end if;

  insert into public.company_initial_setup_progress(company_id, updated_at)
  values(v_company_id, now())
  on conflict(company_id) do update set updated_at=now();

  update public.company_initial_setup_progress
  set personal_profile_completed =
        case when p_step='personal_profile' then true else personal_profile_completed end,
      company_documents_reviewed =
        case when p_step='company_documents' then true else company_documents_reviewed end,
      qualification_settings_reviewed =
        case when p_step='qualification_settings' then true else qualification_settings_reviewed end,
      employee_registration_reviewed =
        case when p_step='employee_registration' then true else employee_registration_reviewed end,
      initial_registration_reviewed =
        case when p_step='initial_registration' then true else initial_registration_reviewed end,
      updated_at=now()
  where company_id=v_company_id;

  perform private.refresh_initial_setup_completion(v_company_id);
end;
$$;

revoke execute on function public.admin_initial_setup_state() from public, anon;
grant execute on function public.admin_initial_setup_state() to authenticated;
revoke execute on function public.mark_admin_initial_setup_step(text) from public, anon;
grant execute on function public.mark_admin_initial_setup_step(text) to authenticated;
