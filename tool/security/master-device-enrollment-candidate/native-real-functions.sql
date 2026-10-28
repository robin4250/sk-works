CREATE OR REPLACE FUNCTION private.require_reauthentication_session()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid();sid uuid;
begin
 if actor is null or auth.jwt()->>'role' is distinct from 'authenticated'
  or coalesce(auth.jwt()->>'is_anonymous','false')<>'false'
  or not private.account_access_allowed() then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 begin sid:=(auth.jwt()->>'session_id')::uuid;
 exception when invalid_text_representation then raise sqlstate '42501' using message='reauthentication_required';end;
 if sid is null or not pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(actor)) then
  raise sqlstate '42501' using message='reauthentication_required';end if;
 perform 1 from auth.users where id=actor and not coalesce(is_anonymous,false)
  and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 perform 1 from auth.sessions where id=sid and user_id=actor
  and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 return sid;
end $function$
;
create or replace function public.verify_secondary_password(p_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.user_secondary_credentials%rowtype;
  v_ok boolean;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select *
  into v_row
  from public.user_secondary_credentials
  where user_id = v_user_id
  for update;

  if not found then
    return false;
  end if;

  if v_row.locked_until is not null and v_row.locked_until > now() then
    raise exception 'secondary password temporarily locked';
  end if;

  v_ok := v_row.password_hash = crypt(coalesce(p_password, ''), v_row.password_hash);

  if v_ok then
    update public.user_secondary_credentials
    set failed_attempts = 0,
        locked_until = null,
        updated_at = now()
    where user_id = v_user_id;
    return true;
  end if;

  update public.user_secondary_credentials
  set failed_attempts = failed_attempts + 1,
      locked_until = case
        when failed_attempts + 1 >= 5 then now() + interval '5 minutes'
        else null
      end,
      updated_at = now()
  where user_id = v_user_id;

  return false;
end;
$$;
