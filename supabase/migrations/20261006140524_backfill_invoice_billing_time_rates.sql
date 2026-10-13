update public.site_financial_settings
set billing_overtime_hour_rate_yen = case
      when billing_overtime_hour_rate_yen = 0 then coalesce(overtime_hour_rate_yen,0)
      else billing_overtime_hour_rate_yen
    end,
    billing_early_hour_rate_yen = case
      when billing_early_hour_rate_yen = 0 then coalesce(early_hour_rate_yen,0)
      else billing_early_hour_rate_yen
    end
where billing_overtime_hour_rate_yen = 0
   or billing_early_hour_rate_yen = 0;
