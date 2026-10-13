alter table public.companies
  add column if not exists employee_testflight_url text;

create or replace function public.initial_registration_distribution_settings()
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_company uuid; v_role text; v_url text;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  select cm.company_id,cm.role::text into v_company,v_role from public.company_members cm where cm.user_id=v_user limit 1;
  if v_company is null then raise exception '会社への所属が必要です'; end if;
  if v_role not in ('owner','admin') then raise exception '管理者だけが設定できます'; end if;
  select coalesce(c.employee_testflight_url,'') into v_url from public.companies c where c.id=v_company;
  return jsonb_build_object('testflight_url',v_url);
end $$;

create or replace function public.save_initial_registration_distribution_settings(p_testflight_url text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_company uuid; v_role text; v_url text:=trim(coalesce(p_testflight_url,''));
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  select cm.company_id,cm.role::text into v_company,v_role from public.company_members cm where cm.user_id=v_user limit 1;
  if v_company is null then raise exception '会社への所属が必要です'; end if;
  if v_role not in ('owner','admin') then raise exception '管理者だけが設定できます'; end if;
  if v_url<>'' and v_url !~ '^https://[A-Za-z0-9._~:/?#\\[\\]@!$&''()*+,;=%-]+$' then raise exception 'https://から始まるURLを入力してください'; end if;
  update public.companies set employee_testflight_url=nullif(v_url,''),updated_at=now() where id=v_company;
end $$;

revoke all on function public.initial_registration_distribution_settings() from public;
revoke all on function public.save_initial_registration_distribution_settings(text) from public;
grant execute on function public.initial_registration_distribution_settings() to authenticated;
grant execute on function public.save_initial_registration_distribution_settings(text) to authenticated;
