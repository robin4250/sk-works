-- Align combined overtime defaults with the requested labor-rate formulas.
-- Only untouched default values are changed; explicit direct overrides remain authoritative.

update public.worker_payroll_settings
set rate_formula =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        coalesce(rate_formula,'{}'::jsonb),
        '{night_overtime_multiplier}',
        '1.5'::jsonb,
        true
      ),
      '{holiday_overtime_multiplier}',
      '1.35'::jsonb,
      true
    ),
    '{holiday_night_overtime_multiplier}',
    '1.6'::jsonb,
    true
  )
where coalesce((rate_formula->>'night_overtime_multiplier')::numeric,1.25)=1.25
  and coalesce((rate_formula->>'holiday_overtime_multiplier')::numeric,1.25)=1.25
  and coalesce((rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.25)=1.25;

update public.worker_payroll_settings s
set day_overtime = case
      when coalesce((s.rate_overrides->>'overtime')::numeric,0)>0
        then (s.rate_overrides->>'overtime')::numeric
      else round(coalesce(s.day_daily,0)
        / greatest(coalesce((s.rate_formula->>'hours_per_day')::numeric,8),1)
        * coalesce((s.rate_formula->>'overtime_multiplier')::numeric,1.25))
    end,
    day_early = case
      when coalesce((s.rate_overrides->>'early')::numeric,0)>0
        then (s.rate_overrides->>'early')::numeric
      else round(coalesce(s.day_daily,0)
        / greatest(coalesce((s.rate_formula->>'hours_per_day')::numeric,8),1)
        * coalesce((s.rate_formula->>'early_multiplier')::numeric,1.25))
    end,
    night_daily = case
      when coalesce((s.rate_overrides->>'night')::numeric,0)>0
        then (s.rate_overrides->>'night')::numeric
      else round(coalesce(s.day_daily,0)
        * coalesce((s.rate_formula->>'night_multiplier')::numeric,1.5))
    end,
    night_overtime = case
      when coalesce((s.rate_overrides->>'night_overtime')::numeric,0)>0
        then (s.rate_overrides->>'night_overtime')::numeric
      else round(coalesce(s.day_daily,0)
        / greatest(coalesce((s.rate_formula->>'hours_per_day')::numeric,8),1)
        * coalesce((s.rate_formula->>'night_overtime_multiplier')::numeric,1.5))
    end,
    night_early = case
      when coalesce((s.rate_overrides->>'night_overtime')::numeric,0)>0
        then (s.rate_overrides->>'night_overtime')::numeric
      else round(coalesce(s.day_daily,0)
        / greatest(coalesce((s.rate_formula->>'hours_per_day')::numeric,8),1)
        * coalesce((s.rate_formula->>'night_overtime_multiplier')::numeric,1.5))
    end,
    holiday_daily = case
      when coalesce((s.rate_overrides->>'holiday')::numeric,0)>0
        then (s.rate_overrides->>'holiday')::numeric
      else round(coalesce(s.day_daily,0)
        * coalesce((s.rate_formula->>'holiday_multiplier')::numeric,1.35))
    end,
    holiday_overtime = case
      when coalesce((s.rate_overrides->>'holiday_overtime')::numeric,0)>0
        then (s.rate_overrides->>'holiday_overtime')::numeric
      else round(coalesce(s.day_daily,0)
        / greatest(coalesce((s.rate_formula->>'hours_per_day')::numeric,8),1)
        * coalesce((s.rate_formula->>'holiday_overtime_multiplier')::numeric,1.35))
    end,
    holiday_early = case
      when coalesce((s.rate_overrides->>'holiday_overtime')::numeric,0)>0
        then (s.rate_overrides->>'holiday_overtime')::numeric
      else round(coalesce(s.day_daily,0)
        / greatest(coalesce((s.rate_formula->>'hours_per_day')::numeric,8),1)
        * coalesce((s.rate_formula->>'holiday_overtime_multiplier')::numeric,1.35))
    end,
    holiday_night_daily = case
      when coalesce((s.rate_overrides->>'holiday_night')::numeric,0)>0
        then (s.rate_overrides->>'holiday_night')::numeric
      else round(coalesce(s.day_daily,0)
        * coalesce((s.rate_formula->>'holiday_night_multiplier')::numeric,1.6))
    end,
    holiday_night_overtime = case
      when coalesce((s.rate_overrides->>'holiday_night_overtime')::numeric,0)>0
        then (s.rate_overrides->>'holiday_night_overtime')::numeric
      else round(coalesce(s.day_daily,0)
        / greatest(coalesce((s.rate_formula->>'hours_per_day')::numeric,8),1)
        * coalesce((s.rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.6))
    end,
    holiday_night_early = case
      when coalesce((s.rate_overrides->>'holiday_night_overtime')::numeric,0)>0
        then (s.rate_overrides->>'holiday_night_overtime')::numeric
      else round(coalesce(s.day_daily,0)
        / greatest(coalesce((s.rate_formula->>'hours_per_day')::numeric,8),1)
        * coalesce((s.rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.6))
    end;

update public.partner_payment_settings
set rate_formula =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        coalesce(rate_formula,'{}'::jsonb),
        '{night_overtime_multiplier}',
        '1.5'::jsonb,
        true
      ),
      '{holiday_overtime_multiplier}',
      '1.35'::jsonb,
      true
    ),
    '{holiday_night_overtime_multiplier}',
    '1.6'::jsonb,
    true
  )
where coalesce((rate_formula->>'night_overtime_multiplier')::numeric,1.25)=1.25
  and coalesce((rate_formula->>'holiday_overtime_multiplier')::numeric,1.25)=1.25
  and coalesce((rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.25)=1.25;

update public.partner_payment_settings p
set night_overtime_hour_rate_yen =
      round(coalesce(p.daily_rate_yen,0)
        / greatest(coalesce((p.rate_formula->>'hours_per_day')::numeric,8),1)
        * coalesce((p.rate_formula->>'night_overtime_multiplier')::numeric,1.5)),
    holiday_overtime_hour_rate_yen =
      round(coalesce(p.daily_rate_yen,0)
        / greatest(coalesce((p.rate_formula->>'hours_per_day')::numeric,8),1)
        * coalesce((p.rate_formula->>'holiday_overtime_multiplier')::numeric,1.35)),
    holiday_night_overtime_hour_rate_yen =
      round(coalesce(p.daily_rate_yen,0)
        / greatest(coalesce((p.rate_formula->>'hours_per_day')::numeric,8),1)
        * coalesce((p.rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.6));

update public.site_financial_settings
set worker_rate_formula =
      jsonb_set(
        jsonb_set(
          jsonb_set(
            coalesce(worker_rate_formula,'{}'::jsonb),
            '{night_overtime_multiplier}','1.5'::jsonb,true
          ),
          '{holiday_overtime_multiplier}','1.35'::jsonb,true
        ),
        '{holiday_night_overtime_multiplier}','1.6'::jsonb,true
      ),
    billing_rate_formula =
      jsonb_set(
        jsonb_set(
          jsonb_set(
            coalesce(billing_rate_formula,'{}'::jsonb),
            '{night_overtime_multiplier}','1.5'::jsonb,true
          ),
          '{holiday_overtime_multiplier}','1.35'::jsonb,true
        ),
        '{holiday_night_overtime_multiplier}','1.6'::jsonb,true
      );
