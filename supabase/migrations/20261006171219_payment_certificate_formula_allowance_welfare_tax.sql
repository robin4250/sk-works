-- Mirror of production payment certificate formula/settings schema.
alter table public.partner_payment_settings
  add column if not exists night_day_rate_yen integer not null default 0,
  add column if not exists night_overtime_hour_rate_yen integer not null default 0,
  add column if not exists holiday_day_rate_yen integer not null default 0,
  add column if not exists holiday_overtime_hour_rate_yen integer not null default 0,
  add column if not exists holiday_night_day_rate_yen integer not null default 0,
  add column if not exists holiday_night_overtime_hour_rate_yen integer not null default 0,
  add column if not exists rate_formula jsonb not null default '{
    "hours_per_day":8,
    "overtime_multiplier":1.25,
    "early_multiplier":1.25,
    "night_multiplier":1.5,
    "night_overtime_multiplier":1.25,
    "holiday_multiplier":1.35,
    "holiday_overtime_multiplier":1.25,
    "holiday_night_multiplier":1.6,
    "holiday_night_overtime_multiplier":1.25
  }'::jsonb,
  add column if not exists allowances jsonb not null default '[]'::jsonb,
  add column if not exists welfare_rate numeric not null default 0,
  add column if not exists tax_rate numeric not null default 10;

alter table public.partner_payment_settings
  drop constraint if exists partner_payment_settings_rate_formula_object_check,
  drop constraint if exists partner_payment_settings_allowances_array_check;

alter table public.partner_payment_settings
  add constraint partner_payment_settings_rate_formula_object_check
    check (jsonb_typeof(rate_formula)='object'),
  add constraint partner_payment_settings_allowances_array_check
    check (jsonb_typeof(allowances)='array');
