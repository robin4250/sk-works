-- Existing owner/admin operations remain; restricted accounts and anonymous execution fail closed.
begin;
do $guard$ begin
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.initial_registration_distribution_settings()') and md5(prosrc) in ('402d85a6ee04936275d9838b91ef2679','787c9fcc6cdd7ed61dfc2e1a8c78ab93') and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'distribution prerequisite differs: initial_registration_distribution_settings()';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.save_initial_registration_distribution_settings(text)') and md5(prosrc) in ('ad08d4bad2f193269f6a28eb35af21f9','6a5059435727bda97f32964d88e7ac28') and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'distribution prerequisite differs: save_initial_registration_distribution_settings(text)';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.account_access_allowed()') and md5(prosrc)='aeca25db212c043c472334026bd98724' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'distribution account prerequisite differs';end if;
end $guard$;

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
  if v_user is null or private.account_access_allowed() is distinct from true then
    raise exception 'アカウントを利用できません' using errcode='42501';
  end if;
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
  if v_user is null or private.account_access_allowed() is distinct from true then
    raise exception 'アカウントを利用できません' using errcode='42501';
  end if;
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

revoke execute on function public.initial_registration_distribution_settings(),public.save_initial_registration_distribution_settings(text) from anon;
commit;
