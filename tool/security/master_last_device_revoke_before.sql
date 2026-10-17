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
