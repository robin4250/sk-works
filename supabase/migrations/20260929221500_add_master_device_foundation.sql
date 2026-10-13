create table if not exists private.master_devices (
  id uuid primary key default gen_random_uuid(),
  master_user_id uuid not null references auth.users(id) on delete cascade,
  device_key text not null,
  device_name text not null,
  device_type text not null,
  platform text,
  registered_at timestamptz not null default now(),
  last_used_at timestamptz,
  is_locked boolean not null default false,
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  constraint master_devices_device_type_check
    check (device_type in ('iphone','ipad','mac','other')),
  constraint master_devices_revoked_consistency
    check (
      (revoked_at is null and revoked_by is null)
      or
      (revoked_at is not null and revoked_by is not null)
    ),
  unique(master_user_id, device_key)
);

create index if not exists master_devices_user_status_idx
  on private.master_devices(master_user_id, revoked_at, is_locked);

revoke all on private.master_devices from public, anon, authenticated;

create or replace function public.master_device_rows()
returns table(
  id uuid,
  device_name text,
  device_type text,
  platform text,
  registered_at timestamptz,
  last_used_at timestamptz,
  is_locked boolean,
  revoked_at timestamptz
)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  if not public.is_current_user_master_admin() then
    raise exception 'master admin permission required';
  end if;

  return query
  select
    d.id,
    d.device_name,
    d.device_type,
    d.platform,
    d.registered_at,
    d.last_used_at,
    d.is_locked,
    d.revoked_at
  from private.master_devices d
  where d.master_user_id = auth.uid()
  order by
    (d.revoked_at is null) desc,
    d.last_used_at desc nulls last,
    d.registered_at desc;
end;
$$;

create or replace function public.set_master_device_locked(
  p_device_id uuid,
  p_locked boolean
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_device private.master_devices%rowtype;
begin
  if not public.is_current_user_master_admin() then
    raise exception 'master admin permission required';
  end if;

  select *
  into v_device
  from private.master_devices
  where id = p_device_id
    and master_user_id = v_actor
  for update;

  if not found then
    raise exception 'master device not found';
  end if;

  if v_device.revoked_at is not null then
    raise exception 'revoked master device cannot be changed';
  end if;

  update private.master_devices
  set is_locked = p_locked
  where id = p_device_id;

  insert into private.master_admin_audit_log(
    actor_user_id,
    action,
    target_user_id,
    details
  )
  values(
    v_actor,
    case when p_locked then 'master_device_lock'
         else 'master_device_unlock' end,
    v_actor,
    jsonb_build_object(
      'device_id', p_device_id,
      'device_name', v_device.device_name
    )
  );
end;
$$;

create or replace function public.revoke_master_device(
  p_device_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_device private.master_devices%rowtype;
begin
  if not public.is_current_user_master_admin() then
    raise exception 'master admin permission required';
  end if;

  select *
  into v_device
  from private.master_devices
  where id = p_device_id
    and master_user_id = v_actor
  for update;

  if not found then
    raise exception 'master device not found';
  end if;

  if v_device.revoked_at is not null then
    return;
  end if;

  update private.master_devices
  set is_locked = true,
      revoked_at = now(),
      revoked_by = v_actor
  where id = p_device_id;

  insert into private.master_admin_audit_log(
    actor_user_id,
    action,
    target_user_id,
    details
  )
  values(
    v_actor,
    'master_device_revoke',
    v_actor,
    jsonb_build_object(
      'device_id', p_device_id,
      'device_name', v_device.device_name
    )
  );
end;
$$;

revoke execute on function public.master_device_rows()
  from public, anon;
revoke execute on function public.set_master_device_locked(uuid,boolean)
  from public, anon;
revoke execute on function public.revoke_master_device(uuid)
  from public, anon;

grant execute on function public.master_device_rows()
  to authenticated;
grant execute on function public.set_master_device_locked(uuid,boolean)
  to authenticated;
grant execute on function public.revoke_master_device(uuid)
  to authenticated;
