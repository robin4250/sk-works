alter table public.site_financial_settings
  add column if not exists worker_rate_formula jsonb not null default
    '{"hours_per_day":8,"overtime_multiplier":1.25,"early_multiplier":1.25,"night_multiplier":1.5,"night_overtime_multiplier":1.25,"holiday_multiplier":1.35,"holiday_overtime_multiplier":1.25,"holiday_night_multiplier":1.6,"holiday_night_overtime_multiplier":1.25}'::jsonb,
  add column if not exists worker_rate_overrides jsonb not null default '{}'::jsonb,
  add column if not exists billing_rate_formula jsonb not null default
    '{"hours_per_day":8,"overtime_multiplier":1.25,"early_multiplier":1.25,"night_multiplier":1.5,"night_overtime_multiplier":1.25,"holiday_multiplier":1.35,"holiday_overtime_multiplier":1.25,"holiday_night_multiplier":1.6,"holiday_night_overtime_multiplier":1.25}'::jsonb,
  add column if not exists billing_rate_overrides jsonb not null default '{}'::jsonb;

alter table public.site_financial_settings
  drop constraint if exists site_financial_worker_rate_formula_object_check,
  drop constraint if exists site_financial_worker_rate_overrides_object_check,
  drop constraint if exists site_financial_billing_rate_formula_object_check,
  drop constraint if exists site_financial_billing_rate_overrides_object_check;

alter table public.site_financial_settings
  add constraint site_financial_worker_rate_formula_object_check
    check (jsonb_typeof(worker_rate_formula)='object'),
  add constraint site_financial_worker_rate_overrides_object_check
    check (jsonb_typeof(worker_rate_overrides)='object'),
  add constraint site_financial_billing_rate_formula_object_check
    check (jsonb_typeof(billing_rate_formula)='object'),
  add constraint site_financial_billing_rate_overrides_object_check
    check (jsonb_typeof(billing_rate_overrides)='object');

update public.site_financial_settings
set worker_rate_overrides =
      coalesce(worker_rate_overrides,'{}'::jsonb)
      || jsonb_build_object(
           'overtime',coalesce(overtime_hour_rate_yen,0),
           'early',coalesce(early_hour_rate_yen,0)
         ),
    billing_rate_overrides =
      coalesce(billing_rate_overrides,'{}'::jsonb)
      || jsonb_build_object(
           'overtime',coalesce(billing_overtime_hour_rate_yen,0),
           'early',coalesce(billing_early_hour_rate_yen,0)
         )
where worker_rate_overrides='{}'::jsonb
   or billing_rate_overrides='{}'::jsonb;
