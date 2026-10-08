-- One transaction for rates, allowance amounts and display units.
-- SECURITY INVOKER keeps existing owner/admin checks inside the two reviewed RPCs.
create or replace function public.save_company_rate_settings_with_units(
  p_tax_rate numeric,
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
  p_allowance_3_amount_yen integer default 0,
  p_allowance_1_unit text default '回',
  p_allowance_2_unit text default '回',
  p_allowance_3_unit text default '回'
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform public.save_company_rate_settings(
    p_tax_rate,p_welfare_rate,p_overtime_hour_rate_yen,p_early_hour_rate_yen,
    p_night_hour_rate_yen,p_holiday_day_rate_yen,p_allowance_1_name,
    p_allowance_1_amount_yen,p_allowance_2_name,p_allowance_2_amount_yen,
    p_allowance_3_name,p_allowance_3_amount_yen);
  perform public.save_company_allowance_units(
    p_allowance_1_unit,p_allowance_2_unit,p_allowance_3_unit);
end;
$$;
revoke all on function public.save_company_rate_settings_with_units(
 numeric,numeric,integer,integer,integer,integer,text,integer,text,integer,text,integer,text,text,text
) from public,anon;
grant execute on function public.save_company_rate_settings_with_units(
 numeric,numeric,integer,integer,integer,integer,text,integer,text,integer,text,integer,text,text,text
) to authenticated;
