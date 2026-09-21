create table if not exists public.employee_registration_invites (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  phone_e164 text not null,
  status text not null default 'invited'
    check (status in ('invited','password_changed','profile_pending','approval_pending','approved','cancelled')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '14 days'),
  password_changed_at timestamptz,
  unique(company_id, phone_e164),
  unique(auth_user_id)
);

alter table public.employee_registration_invites enable row level security;

revoke all on public.employee_registration_invites from anon, authenticated;

create index if not exists employee_registration_invites_company_status_idx
  on public.employee_registration_invites(company_id, status, created_at desc);

create or replace function public.employee_onboarding_state()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.employee_registration_invites%rowtype;
begin
  if v_user_id is null then
    return null;
  end if;

  select *
  into v_row
  from public.employee_registration_invites
  where auth_user_id = v_user_id
  order by created_at desc
  limit 1;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'invite_id', v_row.id,
    'company_id', v_row.company_id,
    'worker_id', v_row.worker_id,
    'name', v_row.name,
    'phone', v_row.phone_e164,
    'status', v_row.status,
    'expires_at', v_row.expires_at,
    'password_changed_at', v_row.password_changed_at
  );
end;
$$;

create or replace function public.mark_employee_initial_password_changed()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  update public.employee_registration_invites
  set status = case
        when status = 'invited' then 'profile_pending'
        else status
      end,
      password_changed_at = coalesce(password_changed_at, now())
  where auth_user_id = v_user_id
    and status in ('invited','password_changed','profile_pending');

  if not found then
    raise exception 'pending employee invitation not found';
  end if;
end;
$$;

revoke execute on function public.employee_onboarding_state() from public, anon;
revoke execute on function public.mark_employee_initial_password_changed() from public, anon;
grant execute on function public.employee_onboarding_state() to authenticated;
grant execute on function public.mark_employee_initial_password_changed() to authenticated;
