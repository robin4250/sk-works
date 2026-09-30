-- Master emergency recovery foundation.
-- Stores two distinct recovery email addresses and a private two-code challenge
-- model. Delivery of the two codes is intentionally handled by a later
-- service/Edge Function integration; no recovery code is exposed to the app.

create table if not exists private.master_recovery_contacts (
  master_user_id uuid primary key references auth.users(id) on delete cascade,
  primary_email text not null,
  secondary_email text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint master_recovery_primary_email_length
    check (length(btrim(primary_email)) between 3 and 320),
  constraint master_recovery_secondary_email_length
    check (length(btrim(secondary_email)) between 3 and 320),
  constraint master_recovery_distinct_emails
    check (lower(btrim(primary_email)) <> lower(btrim(secondary_email)))
);

create table if not exists private.master_recovery_challenges (
  id uuid primary key default gen_random_uuid(),
  master_user_id uuid not null references auth.users(id) on delete cascade,
  primary_code_hash text not null,
  secondary_code_hash text not null,
  primary_verified_at timestamptz,
  secondary_verified_at timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  failed_attempts integer not null default 0,
  locked_at timestamptz,
  constraint master_recovery_challenge_expiry
    check (expires_at > created_at),
  constraint master_recovery_failed_attempts_nonnegative
    check (failed_attempts >= 0)
);

create index if not exists master_recovery_challenges_user_recent_idx
  on private.master_recovery_challenges(master_user_id, created_at desc);

revoke all on private.master_recovery_contacts
  from public, anon, authenticated;
revoke all on private.master_recovery_challenges
  from public, anon, authenticated;

create or replace function public.current_master_recovery_contacts()
returns jsonb
language plpgsql
stable
security definer
set search_path='public','private','pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_row private.master_recovery_contacts%rowtype;
begin
  if v_actor is null or not public.is_current_user_master_admin() then
    return jsonb_build_object(
      'configured', false,
      'primary_masked', null,
      'secondary_masked', null
    );
  end if;

  select *
  into v_row
  from private.master_recovery_contacts
  where master_user_id=v_actor;

  if not found then
    return jsonb_build_object(
      'configured', false,
      'primary_masked', null,
      'secondary_masked', null
    );
  end if;

  return jsonb_build_object(
    'configured', true,
    'primary_masked',
      left(v_row.primary_email,1) || '***@' ||
      split_part(v_row.primary_email,'@',2),
    'secondary_masked',
      left(v_row.secondary_email,1) || '***@' ||
      split_part(v_row.secondary_email,'@',2)
  );
end;
$$;

create or replace function public.set_master_recovery_contacts(
  p_device_key text,
  p_primary_email text,
  p_secondary_email text
)
returns jsonb
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_primary text := lower(btrim(coalesce(p_primary_email,'')));
  v_secondary text := lower(btrim(coalesce(p_secondary_email,'')));
  v_device_status jsonb;
begin
  if v_actor is null or not public.is_current_user_master_admin() then
    raise exception 'master admin permission required';
  end if;

  if p_device_key is null or length(p_device_key) < 32 or length(p_device_key) > 256 then
    raise exception 'trusted master device required';
  end if;

  v_device_status := public.current_master_device_status(p_device_key);
  if coalesce((v_device_status->>'trusted')::boolean,false) is not true then
    raise exception 'trusted master device required';
  end if;

  if length(v_primary) < 3 or length(v_primary) > 320
     or position('@' in v_primary) <= 1 then
    raise exception 'invalid primary recovery email';
  end if;

  if length(v_secondary) < 3 or length(v_secondary) > 320
     or position('@' in v_secondary) <= 1 then
    raise exception 'invalid secondary recovery email';
  end if;

  if v_primary=v_secondary then
    raise exception 'recovery emails must be different';
  end if;

  insert into private.master_recovery_contacts(
    master_user_id,
    primary_email,
    secondary_email,
    updated_at,
    updated_by
  ) values (
    v_actor,
    v_primary,
    v_secondary,
    now(),
    v_actor
  )
  on conflict(master_user_id) do update
  set primary_email=excluded.primary_email,
      secondary_email=excluded.secondary_email,
      updated_at=now(),
      updated_by=v_actor;

  insert into private.master_admin_audit_log(
    actor_user_id,
    action,
    target_user_id,
    details
  ) values (
    v_actor,
    'master_recovery_contacts_update',
    v_actor,
    jsonb_build_object(
      'primary_domain',split_part(v_primary,'@',2),
      'secondary_domain',split_part(v_secondary,'@',2)
    )
  );

  return public.current_master_recovery_contacts();
end;
$$;

revoke all on function public.current_master_recovery_contacts()
  from public, anon;
revoke all on function public.set_master_recovery_contacts(text,text,text)
  from public, anon;

grant execute on function public.current_master_recovery_contacts()
  to authenticated;
grant execute on function public.set_master_recovery_contacts(text,text,text)
  to authenticated;

comment on table private.master_recovery_contacts is
  'Master緊急復旧用の2系統メール。通常会社管理者からは参照・変更不可。';
comment on table private.master_recovery_challenges is
  '2つの別コードによるMaster緊急復旧チャレンジ。配送/検証は専用サービス経由のみ。';
