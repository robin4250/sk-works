alter table public.company_rate_settings
  add column if not exists allowance_1_unit text not null default '回',
  add column if not exists allowance_2_unit text not null default '回',
  add column if not exists allowance_3_unit text not null default '回';

create or replace function public.company_rate_settings_state()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_role text;
  v_company public.companies%rowtype;
  v_rates public.company_rate_settings%rowtype;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  select cm.company_id, cm.role::text
    into v_company_id, v_role
  from public.company_members cm
  where cm.user_id=v_user_id
  limit 1;
  if v_company_id is null or v_role not in ('owner','admin') then
    raise exception 'owner or admin permission required';
  end if;

  select * into v_company from public.companies where id=v_company_id;
  select * into v_rates from public.company_rate_settings where company_id=v_company_id;

  return jsonb_build_object(
    'tax_rate',coalesce(v_company.tax_rate,0),
    'welfare_rate',coalesce(v_company.default_welfare_rate,0),
    'overtime_hour_rate_yen',coalesce(v_rates.overtime_hour_rate_yen,0),
    'early_hour_rate_yen',coalesce(v_rates.early_hour_rate_yen,0),
    'night_hour_rate_yen',coalesce(v_rates.night_hour_rate_yen,0),
    'holiday_day_rate_yen',coalesce(v_rates.holiday_day_rate_yen,0),
    'allowance_1_name',v_rates.allowance_1_name,
    'allowance_1_amount_yen',coalesce(v_rates.allowance_1_amount_yen,0),
    'allowance_1_unit',coalesce(nullif(trim(v_rates.allowance_1_unit),''),'回'),
    'allowance_2_name',v_rates.allowance_2_name,
    'allowance_2_amount_yen',coalesce(v_rates.allowance_2_amount_yen,0),
    'allowance_2_unit',coalesce(nullif(trim(v_rates.allowance_2_unit),''),'回'),
    'allowance_3_name',v_rates.allowance_3_name,
    'allowance_3_amount_yen',coalesce(v_rates.allowance_3_amount_yen,0),
    'allowance_3_unit',coalesce(nullif(trim(v_rates.allowance_3_unit),''),'回')
  );
end;
$$;

create or replace function public.save_company_allowance_units(
  p_allowance_1_unit text,
  p_allowance_2_unit text,
  p_allowance_3_unit text
)
returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_user_id uuid:=auth.uid();
  v_company_id uuid;
begin
  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_user_id and cm.role::text in ('owner','admin')
  limit 1;
  if v_company_id is null then raise exception 'owner or admin permission required'; end if;

  insert into public.company_rate_settings(
    company_id,allowance_1_unit,allowance_2_unit,allowance_3_unit,updated_by,updated_at
  ) values(
    v_company_id,
    coalesce(nullif(trim(p_allowance_1_unit),''),'回'),
    coalesce(nullif(trim(p_allowance_2_unit),''),'回'),
    coalesce(nullif(trim(p_allowance_3_unit),''),'回'),
    v_user_id,now()
  )
  on conflict(company_id) do update set
    allowance_1_unit=excluded.allowance_1_unit,
    allowance_2_unit=excluded.allowance_2_unit,
    allowance_3_unit=excluded.allowance_3_unit,
    updated_by=v_user_id,
    updated_at=now();
end;
$$;

create or replace function public.my_attendance_allowance_units()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_user_id uuid:=auth.uid();
  v_company_id uuid;
  v_rates public.company_rate_settings%rowtype;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  select company_id into v_company_id
  from public.company_members
  where user_id=v_user_id
  limit 1;
  if v_company_id is null then return '{}'::jsonb; end if;

  select * into v_rates
  from public.company_rate_settings
  where company_id=v_company_id;

  return jsonb_strip_nulls(jsonb_build_object(
    coalesce(nullif(trim(v_rates.allowance_1_name),''),'__none1'),
      coalesce(nullif(trim(v_rates.allowance_1_unit),''),'回'),
    coalesce(nullif(trim(v_rates.allowance_2_name),''),'__none2'),
      coalesce(nullif(trim(v_rates.allowance_2_unit),''),'回'),
    coalesce(nullif(trim(v_rates.allowance_3_name),''),'__none3'),
      coalesce(nullif(trim(v_rates.allowance_3_unit),''),'回')
  )) - '__none1' - '__none2' - '__none3';
end;
$$;

revoke all on function public.save_company_allowance_units(text,text,text) from public;
grant execute on function public.save_company_allowance_units(text,text,text) to authenticated;
revoke all on function public.my_attendance_allowance_units() from public;
grant execute on function public.my_attendance_allowance_units() to authenticated;
