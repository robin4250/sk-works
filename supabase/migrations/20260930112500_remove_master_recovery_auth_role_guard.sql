-- Remove deprecated auth.role() dependency from the service-only recovery issuer.
-- Authorization remains enforced by EXECUTE ACL: service_role only.

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

revoke all on function public.service_create_master_recovery_challenge(uuid,text,text,integer)
  from public, anon, authenticated;
grant execute on function public.service_create_master_recovery_challenge(uuid,text,text,integer)
  to service_role;
