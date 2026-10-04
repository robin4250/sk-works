-- Mirrors production migration 20261004141035.
-- Recalculate affected draft outputs immediately after a trade-company contract changes.

CREATE OR REPLACE FUNCTION private.save_trade_company_contract(p_trade_company_id uuid, p_contract_method text, p_daily_rate_yen integer DEFAULT 0, p_monthly_rate_yen integer DEFAULT 0, p_square_meter_unit_price_yen integer DEFAULT 0, p_square_meter_quantity numeric DEFAULT 0, p_contract_amount_yen integer DEFAULT 0)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cid uuid;
  tc public.trade_companies%rowtype;
  r record;
  v_customer uuid;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;

  select * into tc
  from public.trade_companies
  where id=p_trade_company_id and company_id=cid;
  if tc.id is null then raise exception '取引会社が見つかりません。'; end if;

  if p_contract_method not in ('none','daily','monthly','square_meter','contract') then
    raise exception '契約方式を確認してください。';
  end if;
  if p_contract_method='square_meter'
     and (coalesce(p_square_meter_unit_price_yen,0)<=0
       or coalesce(p_square_meter_quantity,0)<=0) then
    raise exception '平米単価と平米数を入力してください。';
  end if;

  insert into public.trade_company_contracts(
    company_id,trade_company_id,contract_method,daily_rate_yen,monthly_rate_yen,
    square_meter_unit_price_yen,square_meter_quantity,contract_amount_yen,
    updated_by,updated_at
  )
  values(
    cid,p_trade_company_id,p_contract_method,
    greatest(coalesce(p_daily_rate_yen,0),0),
    greatest(coalesce(p_monthly_rate_yen,0),0),
    greatest(coalesce(p_square_meter_unit_price_yen,0),0),
    greatest(coalesce(p_square_meter_quantity,0),0),
    greatest(coalesce(p_contract_amount_yen,0),0),
    auth.uid(),now()
  )
  on conflict(company_id,trade_company_id) do update
  set contract_method=excluded.contract_method,
      daily_rate_yen=excluded.daily_rate_yen,
      monthly_rate_yen=excluded.monthly_rate_yen,
      square_meter_unit_price_yen=excluded.square_meter_unit_price_yen,
      square_meter_quantity=excluded.square_meter_quantity,
      contract_amount_yen=excluded.contract_amount_yen,
      updated_by=auth.uid(),
      updated_at=now();

  if tc.partner_company_id is not null then
    insert into public.partner_payment_settings(
      company_id,partner_company_id,daily_rate_yen,updated_at
    )
    values(
      cid,tc.partner_company_id,
      case when p_contract_method='daily'
        then greatest(coalesce(p_daily_rate_yen,0),0)
        else 0 end,
      now()
    )
    on conflict(company_id,partner_company_id) do update
    set daily_rate_yen=excluded.daily_rate_yen,
        updated_at=now();
  end if;

  for r in
    select distinct
      scsp.site_id,
      scsp.output_type,
      ae.work_date,
      ae.worker_id
    from public.site_calculation_source_preferences scsp
    join public.attendance_entries ae
      on ae.company_id=scsp.company_id
      and ae.site_id=scsp.site_id
    where scsp.company_id=cid
      and scsp.trade_company_id=p_trade_company_id
      and scsp.source='trade_company'
  loop
    if r.output_type='invoice' then
      select s.customer_id into v_customer
      from public.sites s
      where s.id=r.site_id and s.company_id=cid;
      perform private.refresh_automatic_invoice(cid,v_customer,r.work_date);
    elsif r.output_type='payment_certificate'
          and tc.partner_company_id is not null then
      perform private.refresh_automatic_payment_certificate(
        cid,tc.partner_company_id,r.work_date
      );
    elsif r.output_type='payroll' then
      perform private.refresh_automatic_payroll(cid,r.worker_id,r.work_date);
    end if;
  end loop;
end
$function$;

revoke all on function private.save_trade_company_contract(
  uuid,text,integer,integer,integer,numeric,integer
) from public,anon,authenticated;
