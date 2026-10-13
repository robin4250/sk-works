alter table public.workers
  add column if not exists user_id uuid references auth.users(id) on delete set null;

create unique index if not exists workers_company_user_unique
  on public.workers(company_id, user_id)
  where user_id is not null;

create index if not exists workers_user_id_idx
  on public.workers(user_id)
  where user_id is not null;

-- Link the owner/admin onboarding account to a worker record when possible.
create or replace function public.ensure_current_user_worker()
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_name text;
  v_phone text;
  v_worker_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null then
    raise exception 'company membership not found';
  end if;

  select up.display_name, up.phone
  into v_name, v_phone
  from public.user_profiles up
  where up.user_id = v_user_id;

  if nullif(trim(coalesce(v_name, '')), '') is null then
    v_name := coalesce(
      auth.jwt() -> 'user_metadata' ->> 'display_name',
      auth.jwt() ->> 'phone',
      auth.jwt() ->> 'email',
      'SKOユーザー'
    );
  end if;

  select w.id
  into v_worker_id
  from public.workers w
  where w.company_id = v_company_id
    and w.user_id = v_user_id
  limit 1;

  if v_worker_id is null then
    insert into public.workers (
      company_id,
      user_id,
      affiliation,
      name,
      phone,
      status
    )
    values (
      v_company_id,
      v_user_id,
      'employee',
      v_name,
      nullif(trim(coalesce(v_phone, '')), ''),
      'active'
    )
    returning id into v_worker_id;
  else
    update public.workers
    set name = coalesce(nullif(trim(v_name), ''), name),
        phone = coalesce(nullif(trim(coalesce(v_phone, '')), ''), phone),
        status = 'active'
    where id = v_worker_id;
  end if;

  return v_worker_id;
end;
$$;

revoke execute on function public.ensure_current_user_worker() from public, anon;
grant execute on function public.ensure_current_user_worker() to authenticated;
