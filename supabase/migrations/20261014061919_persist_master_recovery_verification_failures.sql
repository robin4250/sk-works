-- Persist denied verification attempts and explicitly reject NULL inputs.
-- Existing signature, success response, authentication, row locking and ACLs remain.
CREATE OR REPLACE FUNCTION public.verify_master_recovery_code(p_challenge_id uuid, p_channel text, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'pg_temp'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_row private.master_recovery_challenges%rowtype;
  v_ok boolean := false;
begin
  if v_actor is null or not public.is_current_user_master_admin() then
    raise exception 'master admin permission required';
  end if;

  if p_channel is null or p_channel not in ('primary','secondary') then
    raise exception 'invalid recovery channel';
  end if;

  if p_code is null or p_code !~ '^[0-9]{6}$' then
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

  if v_ok is not true then
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

    -- Return a denial so this RPC transaction commits the failure counter,
    -- lock and audit. Raising here rolls all three back.
    return jsonb_build_object(
      'primary_verified',false,
      'secondary_verified',false,
      'complete',false,
      'error','invalid recovery code'
    );
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
$function$;
