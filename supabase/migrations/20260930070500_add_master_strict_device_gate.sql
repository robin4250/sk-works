-- Strict Master device trust foundation.
-- Direct table access remains private. The first trusted device may be
-- bootstrapped only when the current Master admin has no active trusted device.

create or replace function public.current_master_device_status(
  p_device_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_active_count integer := 0;
  v_trusted boolean := false;
begin
  if v_actor is null or not public.is_current_user_master_admin() then
    return jsonb_build_object(
      'is_master_admin', false,
      'trusted', false,
      'can_bootstrap', false
    );
  end if;

  if p_device_key is null or length(p_device_key) < 32 or length(p_device_key) > 256 then
    raise exception 'invalid master device key';
  end if;

  select count(*)
  into v_active_count
  from private.master_devices d
  where d.master_user_id = v_actor
    and d.revoked_at is null;

  select exists(
    select 1
    from private.master_devices d
    where d.master_user_id = v_actor
      and d.device_key = p_device_key
      and d.revoked_at is null
      and not d.is_locked
  ) into v_trusted;

  if v_trusted then
    update private.master_devices
    set last_used_at = now()
    where master_user_id = v_actor
      and device_key = p_device_key
      and revoked_at is null
      and not is_locked;
  end if;

  return jsonb_build_object(
    'is_master_admin', true,
    'trusted', v_trusted,
    'can_bootstrap', v_active_count = 0
  );
end;
$$;

create or replace function public.bootstrap_first_master_device(
  p_device_key text,
  p_device_name text,
  p_device_type text,
  p_platform text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_device_id uuid;
begin
  if v_actor is null or not public.is_current_user_master_admin() then
    raise exception 'master admin permission required';
  end if;

  if p_device_key is null or length(p_device_key) < 32 or length(p_device_key) > 256 then
    raise exception 'invalid master device key';
  end if;

  if p_device_name is null or length(trim(p_device_name)) < 1 or length(p_device_name) > 120 then
    raise exception 'invalid master device name';
  end if;

  if p_device_type not in ('iphone','ipad','mac','other') then
    raise exception 'invalid master device type';
  end if;

  if exists(
    select 1
    from private.master_devices d
    where d.master_user_id = v_actor
      and d.revoked_at is null
  ) then
    raise exception 'trusted device approval required';
  end if;

  insert into private.master_devices(
    master_user_id,
    device_key,
    device_name,
    device_type,
    platform,
    last_used_at
  )
  values(
    v_actor,
    p_device_key,
    trim(p_device_name),
    p_device_type,
    nullif(trim(coalesce(p_platform,'')), ''),
    now()
  )
  returning id into v_device_id;

  insert into private.master_admin_audit_log(
    actor_user_id,
    action,
    target_user_id,
    details
  )
  values(
    v_actor,
    'master_device_bootstrap',
    v_actor,
    jsonb_build_object('device_id', v_device_id)
  );

  return jsonb_build_object(
    'trusted', true,
    'device_id', v_device_id
  );
end;
$$;

revoke all on function public.current_master_device_status(text)
  from public, anon;
revoke all on function public.bootstrap_first_master_device(text,text,text,text)
  from public, anon;
grant execute on function public.current_master_device_status(text)
  to authenticated;
grant execute on function public.bootstrap_first_master_device(text,text,text,text)
  to authenticated;
