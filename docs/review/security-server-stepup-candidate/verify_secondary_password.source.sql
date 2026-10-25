CREATE OR REPLACE FUNCTION public.verify_secondary_password(p_password text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

