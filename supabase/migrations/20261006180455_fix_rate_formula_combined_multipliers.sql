CREATE OR REPLACE FUNCTION private.resolve_rate_formula(
  p_base_rate numeric,
  p_formula jsonb,
  p_overrides jsonb,
  p_kind text
)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $function$
declare
  f jsonb:=coalesce(p_formula,'{}'::jsonb);
  o jsonb:=coalesce(p_overrides,'{}'::jsonb);
  hours numeric:=greatest(coalesce((f->>'hours_per_day')::numeric,8),0.01);
  base_mode text:=coalesce(nullif(f->>'base_mode',''),'daily');
  hourly numeric;
  daily numeric;
  direct numeric:=coalesce((o->>p_kind)::numeric,0);
  ot numeric:=coalesce((f->>'overtime_multiplier')::numeric,1.25);
  early numeric:=coalesce((f->>'early_multiplier')::numeric,1.25);
  night numeric:=coalesce((f->>'night_multiplier')::numeric,1.5);
  night_ot numeric:=coalesce((f->>'night_overtime_multiplier')::numeric,1.25);
  holiday numeric:=coalesce((f->>'holiday_multiplier')::numeric,1.35);
  holiday_ot numeric:=coalesce((f->>'holiday_overtime_multiplier')::numeric,1.25);
  holiday_night numeric:=coalesce((f->>'holiday_night_multiplier')::numeric,1.6);
  holiday_night_ot numeric:=coalesce((f->>'holiday_night_overtime_multiplier')::numeric,1.25);
begin
  if direct>0 then return round(direct); end if;
  if base_mode='hourly' then
    hourly:=coalesce(nullif((f->>'hourly_rate_yen')::numeric,0),p_base_rate/hours,0);
    daily:=hourly*hours;
  else
    daily:=coalesce(p_base_rate,0);
    hourly:=daily/hours;
  end if;
  return round(case p_kind
    when 'daily' then daily
    when 'overtime' then hourly*ot
    when 'early' then hourly*early
    when 'night' then daily*night
    when 'night_overtime' then hourly*night*night_ot
    when 'holiday' then daily*holiday
    when 'holiday_overtime' then hourly*holiday*holiday_ot
    when 'holiday_night' then daily*holiday_night
    when 'holiday_night_overtime' then hourly*holiday_night*holiday_night_ot
    else 0
  end);
end
$function$;

CREATE OR REPLACE FUNCTION private.rate_formula_label(
  p_formula jsonb,
  p_kind text
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $function$
declare
  f jsonb:=coalesce(p_formula,'{}'::jsonb);
  h text:=trim(to_char(coalesce((f->>'hours_per_day')::numeric,8),'FM999990.###'));
  ot text:=trim(to_char(coalesce((f->>'overtime_multiplier')::numeric,1.25),'FM999990.###'));
  early text:=trim(to_char(coalesce((f->>'early_multiplier')::numeric,1.25),'FM999990.###'));
  night text:=trim(to_char(coalesce((f->>'night_multiplier')::numeric,1.5),'FM999990.###'));
  night_ot text:=trim(to_char(coalesce((f->>'night_overtime_multiplier')::numeric,1.25),'FM999990.###'));
  holiday text:=trim(to_char(coalesce((f->>'holiday_multiplier')::numeric,1.35),'FM999990.###'));
  holiday_ot text:=trim(to_char(coalesce((f->>'holiday_overtime_multiplier')::numeric,1.25),'FM999990.###'));
  holiday_night text:=trim(to_char(coalesce((f->>'holiday_night_multiplier')::numeric,1.6),'FM999990.###'));
  holiday_night_ot text:=trim(to_char(coalesce((f->>'holiday_night_overtime_multiplier')::numeric,1.25),'FM999990.###'));
  base text:=case when f->>'base_mode'='hourly' then '時給' else '1日単価' end;
  hourly_prefix text:=case when f->>'base_mode'='hourly' then base else base||'÷'||h end;
  daily_prefix text:=case when f->>'base_mode'='hourly' then base||'×'||h else base end;
begin
  return case p_kind
    when 'daily' then daily_prefix
    when 'overtime' then hourly_prefix||'×'||ot
    when 'early' then hourly_prefix||'×'||early
    when 'night' then daily_prefix||'×'||night
    when 'night_overtime' then hourly_prefix||'×'||night||'×'||night_ot
    when 'holiday' then daily_prefix||'×'||holiday
    when 'holiday_overtime' then hourly_prefix||'×'||holiday||'×'||holiday_ot
    when 'holiday_night' then daily_prefix||'×'||holiday_night
    when 'holiday_night_overtime' then hourly_prefix||'×'||holiday_night||'×'||holiday_night_ot
    else base
  end;
end
$function$;
