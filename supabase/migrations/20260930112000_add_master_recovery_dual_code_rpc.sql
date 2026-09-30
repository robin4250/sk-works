-- Dual-code Master emergency recovery RPCs.
-- Code delivery is performed by a service-role Edge Function. The app never
-- receives stored hashes or raw recovery contact addresses.

create or replace function public.service_create_master_recovery_challenge(
  p_master_user_id uuid,
  p_primary_code text,
  p_secondary_code text,
  p_ttl_minutes integer default 15
)
returns jsonb
language plpgsql
security definer
set search_path='public','private','extensions','pg_temp'
as $$
declare
  v_contacts private.master_recovery_contacts%rowtype;
  v_challenge_id uuid;
  v_expires_at timestamptz;
  v_ttl integer := greatest(5, least(coalesce(p_ttl_minutes,15), 30));
begin
  -- Execution is restricted to service_role by function ACL below.
  if p_master_user_id is null or not exists(
    select 1
    from private.master_admins ma
    where ma.user_id=p_master_user_id
      and ma.enabled
  ) then
    raise exception 'active master admin required';
  end if;

  if p_primary_code !~ '^[0-9]{6}$'
     or p_secondary_code !~ '^[0-9]{6}$'
     or p_primary_code=p_secondary_code then
    raise exception 'two distinct six digit codes required';
  end if;

  select *
  into v_contacts
  from private.master_recovery_contacts
  where master_user_id=p_master_user_id;

  if not found then
    raise exception 'master recovery contacts not configured';
  end if;

  update private.master_recovery_challenges
  set locked_at=coalesce(locked_at,now())
  where master_user_id=p_master_user_id
    and used_at is null
    and locked_at is null
    and expires_at > now();

  v_expires_at := now() + make_interval(mins => v_ttl);

  insert into private.master_recovery_challenges(
    master_user_id,
    primary_code_hash,
    secondary_code_hash,
    expires_at
  ) values (
    p_master_user_id,
    crypt(p_primary_code, gen_salt('bf')),
    crypt(p_secondary_code, gen_salt('bf')),
    v_expires_at
  )
  returning id into v_challenge_id;

  insert into private.master_admin_audit_log(
    actor_user_id,
    action,
    target_user_id,
    details
  ) values (
    p_master_user_id,
    'master_recovery_challenge_issued',
    p_master_user_id,
    jsonb_build_object(
      'challenge_id',v_challenge_id,
      'expires_at',v_expires_at
    )
  );

  return jsonb_build_object(
    'challenge_id',v_challenge_id,
    'primary_email',v_contacts.primary_email,
    'secondary_email',v_contacts.secondary_email,
    'expires_at',v_expires_at
  );
end;
$$;

create or replace function public.verify_master_recovery_code(
  p_challenge_id uuid,
  p_channel text,
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path='public','private','extensions','pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_row private.master_recovery_challenges%rowtype;
  v_ok boolean := false;
begin
  if v_actor is null or not public.is_current_user_master_admin() then
    raise exception 'master admin permission required';
  end if;

  if p_channel not in ('primary','secondary') then
    raise exception 'invalid recovery channel';
  end if;

  if p_code !~ '^[0-9]{6}$' then
    raise exception 'invalid recovery code';
  end if;

  select *
  into v_row
  from private.master_recovery_challenges
  where id=p_challenge_id
    and master_user_id=v_actor
  for update;

  if not found then
    raise exception 'recovery challenge not found';
  end if;
  if v_row.used_at is not null then
    raise exception 'recovery challenge already used';
  end if;
  if v_row.locked_at is not null then
    raise exception 'recovery challenge locked';
  end if;
  if v_row.expires_at <= now() then
    raise exception 'recovery challenge expired';
  end if;

  if p_channel='primary' then
    v_ok := crypt(p_code,v_row.primary_code_hash)=v_row.primary_code_hash;
  else
    v_ok := crypt(p_code,v_row.secondary_code_hash)=v_row.secondary_code_hash;
  end if;

  if not v_ok then
    update private.master_recovery_challenges
    set failed_attempts=failed_attempts+1,
        locked_at=case when failed_attempts+1 >= 8 then now() else locked_at end
    where id=p_challenge_id;

    insert into private.master_admin_audit_log(
      actor_user_id,action,target_user_id,details
    ) values (
      v_actor,
      'master_recovery_code_failed',
      v_actor,
      jsonb_build_object(
        'challenge_id',p_challenge_id,
        'channel',p_channel
      )
    );

    raise exception 'invalid recovery code';
  end if;

  if p_channel='primary' then
    update private.master_recovery_challenges
    set primary_verified_at=coalesce(primary_verified_at,now())
    where id=p_challenge_id;
  else
    update private.master_recovery_challenges
    set secondary_verified_at=coalesce(secondary_verified_at,now())
    where id=p_challenge_id;
  end if;

  select *
  into v_row
  from private.master_recovery_challenges
  where id=p_challenge_id;

  insert into private.master_admin_audit_log(
    actor_user_id,action,target_user_id,details
  ) values (
    v_actor,
    'master_recovery_code_verified',
    v_actor,
    jsonb_build_object(
      'challenge_id',p_challenge_id,
      'channel',p_channel
    )
  );

  return jsonb_build_object(
    'primary_verified',v_row.primary_verified_at is not null,
    'secondary_verified',v_row.secondary_verified_at is not null,
    'complete',
      v_row.primary_verified_at is not null
      and v_row.secondary_verified_at is not null
  );
end;
$$;

create or replace function public.consume_master_recovery_challenge(
  p_challenge_id uuid,
  p_device_key text,
  p_device_name text,
  p_device_type text,
  p_platform text default null
)
returns jsonb
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_row private.master_recovery_challenges%rowtype;
  v_device_id uuid;
begin
  if v_actor is null or not public.is_current_user_master_admin() then
    raise exception 'master admin permission required';
  end if;

  if p_device_key is null or length(p_device_key) < 32 or length(p_device_key) > 256 then
    raise exception 'invalid master device key';
  end if;
  if p_device_name is null or length(btrim(p_device_name)) < 1
     or length(p_device_name) > 120 then
    raise exception 'invalid master device name';
  end if;
  if p_device_type not in ('iphone','ipad','mac','other') then
    raise exception 'invalid master device type';
  end if;

  select *
  into v_row
  from private.master_recovery_challenges
  where id=p_challenge_id
    and master_user_id=v_actor
  for update;

  if not found then
    raise exception 'recovery challenge not found';
  end if;
  if v_row.used_at is not null then
    raise exception 'recovery challenge already used';
  end if;
  if v_row.locked_at is not null then
    raise exception 'recovery challenge locked';
  end if;
  if v_row.expires_at <= now() then
    raise exception 'recovery challenge expired';
  end if;
  if v_row.primary_verified_at is null or v_row.secondary_verified_at is null then
    raise exception 'both recovery codes required';
  end if;

  insert into private.master_devices(
    master_user_id,
    device_key,
    device_name,
    device_type,
    platform,
    last_used_at
  ) values (
    v_actor,
    p_device_key,
    btrim(p_device_name),
    p_device_type,
    nullif(btrim(coalesce(p_platform,'')),''),
    now()
  )
  on conflict(master_user_id,device_key) do update
  set device_name=excluded.device_name,
      device_type=excluded.device_type,
      platform=excluded.platform,
      last_used_at=now(),
      is_locked=false,
      revoked_at=null,
      revoked_by=null
  returning id into v_device_id;

  update private.master_recovery_challenges
  set used_at=now()
  where id=p_challenge_id;

  insert into private.master_admin_audit_log(
    actor_user_id,action,target_user_id,details
  ) values (
    v_actor,
    'master_recovery_device_registered',
    v_actor,
    jsonb_build_object(
      'challenge_id',p_challenge_id,
      'device_id',v_device_id
    )
  );

  return jsonb_build_object(
    'trusted',true,
    'device_id',v_device_id
  );
end;
$$;

revoke all on function public.service_create_master_recovery_challenge(uuid,text,text,integer)
  from public, anon, authenticated;
grant execute on function public.service_create_master_recovery_challenge(uuid,text,text,integer)
  to service_role;

revoke all on function public.verify_master_recovery_code(uuid,text,text)
  from public, anon;
grant execute on function public.verify_master_recovery_code(uuid,text,text)
  to authenticated;

revoke all on function public.consume_master_recovery_challenge(uuid,text,text,text,text)
  from public, anon;
grant execute on function public.consume_master_recovery_challenge(uuid,text,text,text,text)
  to authenticated;
