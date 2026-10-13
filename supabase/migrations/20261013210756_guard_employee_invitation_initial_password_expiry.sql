-- Keep all existing initial-registration roles and responses. Reject expired
-- first password progression even when the state-read RPC was bypassed.
do $$
begin
 if (select md5(prosrc) from pg_proc where oid='public.mark_employee_initial_password_changed()'::regprocedure) not in ('07dc3eaeba15fd12d65ce9f133daf82b','3606a4cfa4425fa6d11de2f06491b522') then
  raise exception 'employee initial password function changed; review required';
 end if;
end $$;

CREATE OR REPLACE FUNCTION public.mark_employee_initial_password_changed()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  update public.employee_registration_invites
  set status = case
        when status = 'invited' then 'profile_pending'
        else status
      end,
      password_changed_at = coalesce(password_changed_at, now())
  where auth_user_id = v_user_id
    and status in ('invited','password_changed','profile_pending')
    and (status <> 'invited' or expires_at >= now());

  if not found then
    raise exception 'pending employee invitation not found';
  end if;
end;
$function$;
