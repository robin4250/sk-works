-- Keep new rows on the same requested formula defaults.
alter table public.partner_payment_settings
  alter column rate_formula set default '{"hours_per_day":8,"base_mode":"daily","hourly_base":false,"overtime_multiplier":1.25,"early_multiplier":1.25,"night_multiplier":1.5,"night_overtime_multiplier":1.5,"holiday_multiplier":1.35,"holiday_overtime_multiplier":1.35,"holiday_night_multiplier":1.6,"holiday_night_overtime_multiplier":1.6}'::jsonb;

alter table public.site_financial_settings
  alter column worker_rate_formula set default '{"hours_per_day":8,"base_mode":"daily","hourly_base":false,"overtime_multiplier":1.25,"early_multiplier":1.25,"night_multiplier":1.5,"night_overtime_multiplier":1.5,"holiday_multiplier":1.35,"holiday_overtime_multiplier":1.35,"holiday_night_multiplier":1.6,"holiday_night_overtime_multiplier":1.6}'::jsonb,
  alter column billing_rate_formula set default '{"hours_per_day":8,"base_mode":"daily","hourly_base":false,"overtime_multiplier":1.25,"early_multiplier":1.25,"night_multiplier":1.5,"night_overtime_multiplier":1.5,"holiday_multiplier":1.35,"holiday_overtime_multiplier":1.35,"holiday_night_multiplier":1.6,"holiday_night_overtime_multiplier":1.6}'::jsonb;

alter table public.worker_payroll_settings
  alter column rate_formula set default '{"hours_per_day":8,"base_mode":"daily","hourly_base":false,"overtime_multiplier":1.25,"early_multiplier":1.25,"night_multiplier":1.5,"night_overtime_multiplier":1.5,"holiday_multiplier":1.35,"holiday_overtime_multiplier":1.35,"holiday_night_multiplier":1.6,"holiday_night_overtime_multiplier":1.6}'::jsonb;

update public.partner_payment_settings
set rate_formula = coalesce(rate_formula,'{}'::jsonb)
  || jsonb_build_object(
    'hours_per_day',coalesce((rate_formula->>'hours_per_day')::numeric,8),
    'base_mode',coalesce(nullif(rate_formula->>'base_mode',''),'daily'),
    'hourly_base',coalesce((rate_formula->>'hourly_base')::boolean,false),
    'overtime_multiplier',coalesce((rate_formula->>'overtime_multiplier')::numeric,1.25),
    'early_multiplier',coalesce((rate_formula->>'early_multiplier')::numeric,1.25),
    'night_multiplier',coalesce((rate_formula->>'night_multiplier')::numeric,1.5),
    'night_overtime_multiplier',coalesce((rate_formula->>'night_overtime_multiplier')::numeric,1.5),
    'holiday_multiplier',coalesce((rate_formula->>'holiday_multiplier')::numeric,1.35),
    'holiday_overtime_multiplier',coalesce((rate_formula->>'holiday_overtime_multiplier')::numeric,1.35),
    'holiday_night_multiplier',coalesce((rate_formula->>'holiday_night_multiplier')::numeric,1.6),
    'holiday_night_overtime_multiplier',coalesce((rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.6)
  );

update public.site_financial_settings
set worker_rate_formula = coalesce(worker_rate_formula,'{}'::jsonb)
  || jsonb_build_object(
    'hours_per_day',coalesce((worker_rate_formula->>'hours_per_day')::numeric,8),
    'base_mode',coalesce(nullif(worker_rate_formula->>'base_mode',''),'daily'),
    'hourly_base',coalesce((worker_rate_formula->>'hourly_base')::boolean,false),
    'overtime_multiplier',coalesce((worker_rate_formula->>'overtime_multiplier')::numeric,1.25),
    'early_multiplier',coalesce((worker_rate_formula->>'early_multiplier')::numeric,1.25),
    'night_multiplier',coalesce((worker_rate_formula->>'night_multiplier')::numeric,1.5),
    'night_overtime_multiplier',coalesce((worker_rate_formula->>'night_overtime_multiplier')::numeric,1.5),
    'holiday_multiplier',coalesce((worker_rate_formula->>'holiday_multiplier')::numeric,1.35),
    'holiday_overtime_multiplier',coalesce((worker_rate_formula->>'holiday_overtime_multiplier')::numeric,1.35),
    'holiday_night_multiplier',coalesce((worker_rate_formula->>'holiday_night_multiplier')::numeric,1.6),
    'holiday_night_overtime_multiplier',coalesce((worker_rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.6)
  ),
    billing_rate_formula = coalesce(billing_rate_formula,'{}'::jsonb)
  || jsonb_build_object(
    'hours_per_day',coalesce((billing_rate_formula->>'hours_per_day')::numeric,8),
    'base_mode',coalesce(nullif(billing_rate_formula->>'base_mode',''),'daily'),
    'hourly_base',coalesce((billing_rate_formula->>'hourly_base')::boolean,false),
    'overtime_multiplier',coalesce((billing_rate_formula->>'overtime_multiplier')::numeric,1.25),
    'early_multiplier',coalesce((billing_rate_formula->>'early_multiplier')::numeric,1.25),
    'night_multiplier',coalesce((billing_rate_formula->>'night_multiplier')::numeric,1.5),
    'night_overtime_multiplier',coalesce((billing_rate_formula->>'night_overtime_multiplier')::numeric,1.5),
    'holiday_multiplier',coalesce((billing_rate_formula->>'holiday_multiplier')::numeric,1.35),
    'holiday_overtime_multiplier',coalesce((billing_rate_formula->>'holiday_overtime_multiplier')::numeric,1.35),
    'holiday_night_multiplier',coalesce((billing_rate_formula->>'holiday_night_multiplier')::numeric,1.6),
    'holiday_night_overtime_multiplier',coalesce((billing_rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.6)
  );

update public.worker_payroll_settings
set rate_formula = coalesce(rate_formula,'{}'::jsonb)
  || jsonb_build_object(
    'hours_per_day',coalesce((rate_formula->>'hours_per_day')::numeric,8),
    'base_mode',coalesce(nullif(rate_formula->>'base_mode',''),'daily'),
    'hourly_base',coalesce((rate_formula->>'hourly_base')::boolean,false),
    'overtime_multiplier',coalesce((rate_formula->>'overtime_multiplier')::numeric,1.25),
    'early_multiplier',coalesce((rate_formula->>'early_multiplier')::numeric,1.25),
    'night_multiplier',coalesce((rate_formula->>'night_multiplier')::numeric,1.5),
    'night_overtime_multiplier',coalesce((rate_formula->>'night_overtime_multiplier')::numeric,1.5),
    'holiday_multiplier',coalesce((rate_formula->>'holiday_multiplier')::numeric,1.35),
    'holiday_overtime_multiplier',coalesce((rate_formula->>'holiday_overtime_multiplier')::numeric,1.35),
    'holiday_night_multiplier',coalesce((rate_formula->>'holiday_night_multiplier')::numeric,1.6),
    'holiday_night_overtime_multiplier',coalesce((rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.6)
  );
