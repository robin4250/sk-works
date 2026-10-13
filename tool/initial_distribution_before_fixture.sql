CREATE OR REPLACE FUNCTION public.initial_registration_distribution_settings()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_role text;
  v_url text;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  select cm.company_id,cm.role::text into v_company,v_role
  from public.company_members cm where cm.user_id=v_user limit 1;
  if v_company is null then raise exception '会社への所属が必要です'; end if;
  if v_role not in ('owner','admin') then raise exception '管理者だけが設定できます'; end if;
  select coalesce(c.employee_testflight_url,'') into v_url
  from public.companies c where c.id=v_company;
  return jsonb_build_object('testflight_url',v_url);
end $function$;

CREATE OR REPLACE FUNCTION public.save_initial_registration_distribution_settings(p_testflight_url text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_role text;
  v_url text:=trim(coalesce(p_testflight_url,''));
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  select cm.company_id,cm.role::text into v_company,v_role
  from public.company_members cm where cm.user_id=v_user limit 1;
  if v_company is null then raise exception '会社への所属が必要です'; end if;
  if v_role not in ('owner','admin') then raise exception '管理者だけが設定できます'; end if;
  if v_url<>'' and v_url !~ '^https://[A-Za-z0-9._~:/?#\[\]@!$&''()*+,;=%-]+$' then
    raise exception 'https://から始まるURLを入力してください';
  end if;
  update public.companies set employee_testflight_url=nullif(v_url,''),updated_at=now()
  where id=v_company;
end $function$;

CREATE OR REPLACE FUNCTION private.account_access_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and not exists(
  select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())
$function$;