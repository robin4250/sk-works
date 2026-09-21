create or replace function public.company_rate_settings_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_company_id uuid;
  v_role text;
  v_company public.companies%rowtype;
  v_rates public.company_rate_settings%rowtype;
begin
  select cm.company_id, cm.role::text
  into v_company_id, v_role
  from public.company_members cm
  where cm.user_id = auth.uid()
  limit 1;

  if v_company_id is null or v_role not in ('owner','admin') then
    raise exception 'owner or admin permission required';
  end if;

  select *
  into v_company
  from public.companies
  where id = v_company_id;

  select *
  into v_rates
  from public.company_rate_settings
  where company_id = v_company_id;

  return jsonb_build_object(
    'welfare_rate', coalesce(v_company.default_welfare_rate, 0),
    'overtime_hour_rate_yen', coalesce(v_rates.overtime_hour_rate_yen, 0),
    'early_hour_rate_yen', coalesce(v_rates.early_hour_rate_yen, 0),
    'night_hour_rate_yen', coalesce(v_rates.night_hour_rate_yen, 0),
    'holiday_day_rate_yen', coalesce(v_rates.holiday_day_rate_yen, 0),
    'allowance_1_name', coalesce(v_rates.allowance_1_name, ''),
    'allowance_1_amount_yen', coalesce(v_rates.allowance_1_amount_yen, 0),
    'allowance_2_name', coalesce(v_rates.allowance_2_name, ''),
    'allowance_2_amount_yen', coalesce(v_rates.allowance_2_amount_yen, 0),
    'allowance_3_name', coalesce(v_rates.allowance_3_name, ''),
    'allowance_3_amount_yen', coalesce(v_rates.allowance_3_amount_yen, 0)
  );
end;
$$;

create or replace function public.save_company_rate_settings(
  p_welfare_rate numeric,
  p_overtime_hour_rate_yen integer,
  p_early_hour_rate_yen integer,
  p_night_hour_rate_yen integer,
  p_holiday_day_rate_yen integer,
  p_allowance_1_name text default null,
  p_allowance_1_amount_yen integer default 0,
  p_allowance_2_name text default null,
  p_allowance_2_amount_yen integer default 0,
  p_allowance_3_name text default null,
  p_allowance_3_amount_yen integer default 0
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_role text;
begin
  select cm.company_id, cm.role::text
  into v_company_id, v_role
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null or v_role not in ('owner','admin') then
    raise exception 'owner or admin permission required';
  end if;

  if p_welfare_rate < 0 or p_welfare_rate > 100
     or p_overtime_hour_rate_yen < 0
     or p_early_hour_rate_yen < 0
     or p_night_hour_rate_yen < 0
     or p_holiday_day_rate_yen < 0
     or p_allowance_1_amount_yen < 0
     or p_allowance_2_amount_yen < 0
     or p_allowance_3_amount_yen < 0 then
    raise exception 'invalid company rate setting';
  end if;

  update public.companies
  set default_welfare_rate = p_welfare_rate,
      updated_at = now()
  where id = v_company_id;

  insert into public.company_rate_settings(
    company_id,
    overtime_hour_rate_yen,
    early_hour_rate_yen,
    night_hour_rate_yen,
    holiday_day_rate_yen,
    allowance_1_name,
    allowance_1_amount_yen,
    allowance_2_name,
    allowance_2_amount_yen,
    allowance_3_name,
    allowance_3_amount_yen,
    updated_by,
    updated_at
  )
  values(
    v_company_id,
    p_overtime_hour_rate_yen,
    p_early_hour_rate_yen,
    p_night_hour_rate_yen,
    p_holiday_day_rate_yen,
    nullif(trim(coalesce(p_allowance_1_name, '')), ''),
    p_allowance_1_amount_yen,
    nullif(trim(coalesce(p_allowance_2_name, '')), ''),
    p_allowance_2_amount_yen,
    nullif(trim(coalesce(p_allowance_3_name, '')), ''),
    p_allowance_3_amount_yen,
    v_user_id,
    now()
  )
  on conflict(company_id) do update
  set overtime_hour_rate_yen = excluded.overtime_hour_rate_yen,
      early_hour_rate_yen = excluded.early_hour_rate_yen,
      night_hour_rate_yen = excluded.night_hour_rate_yen,
      holiday_day_rate_yen = excluded.holiday_day_rate_yen,
      allowance_1_name = excluded.allowance_1_name,
      allowance_1_amount_yen = excluded.allowance_1_amount_yen,
      allowance_2_name = excluded.allowance_2_name,
      allowance_2_amount_yen = excluded.allowance_2_amount_yen,
      allowance_3_name = excluded.allowance_3_name,
      allowance_3_amount_yen = excluded.allowance_3_amount_yen,
      updated_by = v_user_id,
      updated_at = now();
end;
$$;

revoke execute on function public.company_rate_settings_state() from public, anon;
revoke execute on function public.save_company_rate_settings(
  numeric,integer,integer,integer,integer,text,integer,text,integer,text,integer
) from public, anon;

grant execute on function public.company_rate_settings_state() to authenticated;
grant execute on function public.save_company_rate_settings(
  numeric,integer,integer,integer,integer,text,integer,text,integer,text,integer
) to authenticated;
