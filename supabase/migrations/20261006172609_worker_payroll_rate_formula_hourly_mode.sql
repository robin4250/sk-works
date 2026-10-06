-- Persist editable payroll rate formulas and direct overrides.
alter table public.worker_payroll_settings
  add column if not exists hourly_rate_yen numeric not null default 0,
  add column if not exists rate_formula jsonb not null default jsonb_build_object(
    'base_mode','daily',
    'hours_per_day',8,
    'hourly_rate_yen',0,
    'overtime_multiplier',1.25,
    'early_multiplier',1.25,
    'night_multiplier',1.5,
    'night_overtime_multiplier',1.5,
    'holiday_multiplier',1.35,
    'holiday_overtime_multiplier',1.35,
    'holiday_night_multiplier',1.6,
    'holiday_night_overtime_multiplier',1.6
  ),
  add column if not exists rate_overrides jsonb not null default '{}'::jsonb;

alter table public.worker_payroll_settings
  drop constraint if exists worker_payroll_settings_rate_formula_object_check,
  drop constraint if exists worker_payroll_settings_rate_overrides_object_check,
  drop constraint if exists worker_payroll_settings_hourly_rate_nonnegative_check;

alter table public.worker_payroll_settings
  add constraint worker_payroll_settings_rate_formula_object_check
    check (jsonb_typeof(rate_formula)='object'),
  add constraint worker_payroll_settings_rate_overrides_object_check
    check (jsonb_typeof(rate_overrides)='object'),
  add constraint worker_payroll_settings_hourly_rate_nonnegative_check
    check (hourly_rate_yen >= 0);

update public.worker_payroll_settings
set rate_formula =
  coalesce(rate_formula,'{}'::jsonb)
  || jsonb_build_object(
    'base_mode',coalesce(nullif(rate_formula->>'base_mode',''),'daily'),
    'hours_per_day',coalesce((rate_formula->>'hours_per_day')::numeric,8),
    'hourly_rate_yen',coalesce(hourly_rate_yen,0),
    'overtime_multiplier',coalesce((rate_formula->>'overtime_multiplier')::numeric,1.25),
    'early_multiplier',coalesce((rate_formula->>'early_multiplier')::numeric,1.25),
    'night_multiplier',coalesce((rate_formula->>'night_multiplier')::numeric,1.5),
    'night_overtime_multiplier',coalesce((rate_formula->>'night_overtime_multiplier')::numeric,1.5),
    'holiday_multiplier',coalesce((rate_formula->>'holiday_multiplier')::numeric,1.35),
    'holiday_overtime_multiplier',coalesce((rate_formula->>'holiday_overtime_multiplier')::numeric,1.35),
    'holiday_night_multiplier',coalesce((rate_formula->>'holiday_night_multiplier')::numeric,1.6),
    'holiday_night_overtime_multiplier',coalesce((rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.6)
  ),
  rate_overrides=coalesce(rate_overrides,'{}'::jsonb);
