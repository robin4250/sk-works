alter table public.site_financial_settings
  add column if not exists billing_square_meter_unit_price_yen integer not null default 0,
  add column if not exists billing_square_meter_quantity numeric(12,3) not null default 0,
  add column if not exists billing_contract_amount_yen integer not null default 0;

alter table public.site_financial_settings
  drop constraint if exists site_financial_settings_billing_square_pair_check,
  drop constraint if exists site_financial_settings_single_billing_method_check,
  drop constraint if exists site_financial_settings_billing_nonnegative_check;

alter table public.site_financial_settings
  add constraint site_financial_settings_billing_nonnegative_check
    check (
      billing_unit_price_yen >= 0
      and billing_square_meter_unit_price_yen >= 0
      and billing_square_meter_quantity >= 0
      and billing_contract_amount_yen >= 0
    ),
  add constraint site_financial_settings_billing_square_pair_check
    check (
      (billing_square_meter_unit_price_yen = 0 and billing_square_meter_quantity = 0)
      or
      (billing_square_meter_unit_price_yen > 0 and billing_square_meter_quantity > 0)
    ),
  add constraint site_financial_settings_single_billing_method_check
    check (
      (case when billing_unit_price_yen > 0 then 1 else 0 end)
      +
      (case
        when billing_square_meter_unit_price_yen > 0
         and billing_square_meter_quantity > 0 then 1
        else 0
      end)
      +
      (case when billing_contract_amount_yen > 0 then 1 else 0 end)
      <= 1
    );
