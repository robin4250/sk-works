-- Reflect attendance allowances even before a site rate is configured,
-- and insert early-work rows before overtime in each normal/night invoice block.
create or replace function private.refresh_automatic_invoice(cid uuid, customer uuid, day date)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  first_day date:=date_trunc('month',day)::date;
  last_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
  existing public.invoices%rowtype;
  s record;
  pref record;
  allowance_cfg record;
  sites_json jsonb:='[]'::jsonb;
  lines jsonb;
  customer_name text;
  snapshot_value jsonb;
  v_system_customer boolean:=false;
  v_tax_rate numeric:=0;
  day_days numeric:=0;
  night_days numeric:=0;
  day_overtime numeric:=0;
  night_overtime numeric:=0;
  day_early numeric:=0;
  night_early numeric:=0;
  unit_rate numeric:=0;
  night_rate numeric:=0;
  method_label text:='';
  qty numeric;
  allowance_count numeric;
  allowance_rate numeric;
  early_amount numeric;
  a numeric;
  b numeric;
  c numeric;
  d numeric;
  site_tax numeric;
  set_pre_tax numeric;
  site_pre_tax numeric;
  site_tax_total numeric;
  total_pre_tax numeric:=0;
  total_tax numeric:=0;
  total_welfare numeric:=0;
  n integer:=0;
begin
  if auth.uid() is null then return; end if;

  if customer is null then
    customer:=private.ensure_unassigned_invoice_customer(cid);
    v_system_customer:=true;
  else
    select c.notes='sko_system_unassigned_invoice_customer'
    into v_system_customer
    from public.customers c
    where c.id=customer and c.company_id=cid;
    v_system_customer:=coalesce(v_system_customer,false);
  end if;

  if customer is null then return; end if;
  perform pg_advisory_xact_lock(
    hashtextextended('invoice:'||cid::text||customer::text||first_day::text,0)
  );

  select * into existing
  from public.invoices
  where company_id=cid
    and customer_id=customer
    and billing_period_start=first_day
    and automatic_calculation
  for update;

  if found and (existing.status<>'draft' or existing.finalized_at is not null) then
    return;
  end if;
  if existing.id is null and exists(
    select 1 from public.invoices
    where company_id=cid
      and customer_id=customer
      and billing_period_start=first_day
  ) then return; end if;

  select name into customer_name
  from public.customers
  where id=customer and company_id=cid;
  if customer_name is null then return; end if;

  select greatest(coalesce(c.tax_rate,0),0)
  into v_tax_rate
  from public.companies c
  where c.id=cid;

  for s in
    select
      st.id,
      coalesce(nullif(st.formal_name,''),st.name) as name,
      coalesce(fs.billing_unit_price_yen,0) as billing_unit_price_yen,
      coalesce(fs.billing_monthly_rate_yen,0) as billing_monthly_rate_yen,
      coalesce(fs.billing_square_meter_unit_price_yen,0) as billing_square_meter_unit_price_yen,
      coalesce(fs.billing_square_meter_quantity,0) as billing_square_meter_quantity,
      coalesce(fs.billing_contract_amount_yen,0) as billing_contract_amount_yen,
      coalesce(fs.overtime_hour_rate_yen,0) as overtime_hour_rate_yen,
      coalesce(fs.early_hour_rate_yen,0) as early_hour_rate_yen,
      case when fs.welfare_rate between 0 and 100 then fs.welfare_rate else 0 end as welfare_rate,
      nullif(trim(coalesce(fs.billing_allowance_1_name,'')),'') as allowance_1_name,
      coalesce(fs.billing_allowance_1_amount_yen,0) as allowance_1_amount,
      nullif(trim(coalesce(fs.billing_allowance_2_name,'')),'') as allowance_2_name,
      coalesce(fs.billing_allowance_2_amount_yen,0) as allowance_2_amount,
      nullif(trim(coalesce(fs.billing_allowance_3_name,'')),'') as allowance_3_name,
      coalesce(fs.billing_allowance_3_amount_yen,0) as allowance_3_amount
    from public.sites st
    left join public.site_financial_settings fs
      on fs.site_id=st.id and fs.company_id=cid
    where st.company_id=cid
      and (
        (v_system_customer and st.customer_id is null)
        or (not v_system_customer and st.customer_id=customer)
      )
      and exists(
        select 1
        from public.attendance_entries e
        where e.site_id=st.id
          and e.company_id=cid
          and e.work_date between first_day and last_day
      )
    order by st.created_at, st.id
  loop
    n:=n+1;
    lines:='[]'::jsonb;
    site_pre_tax:=0;
    site_tax_total:=0;

    select
      coalesce(sum(case when e.work_category in ('day','holiday') then coalesce(e.base_man_days,0) else 0 end),0),
      coalesce(sum(case when e.work_category in ('night','holiday_night') then coalesce(e.base_man_days,0) else 0 end),0),
      coalesce(sum(case when e.work_category in ('day','holiday') then coalesce(e.overtime_hours,0) else 0 end),0),
      coalesce(sum(case when e.work_category in ('night','holiday_night') then coalesce(e.overtime_hours,0) else 0 end),0),
      coalesce(sum(case when e.work_category in ('day','holiday') then coalesce(e.early_hours,0) else 0 end),0),
      coalesce(sum(case when e.work_category in ('night','holiday_night') then coalesce(e.early_hours,0) else 0 end),0)
    into day_days,night_days,day_overtime,night_overtime,day_early,night_early
    from public.attendance_entries e
    where e.company_id=cid
      and e.site_id=s.id
      and e.work_date between first_day and last_day;

    pref:=null;
    select
      scsp.source,
      coalesce(ct.contract_method,'none') as contract_method,
      coalesce(ct.daily_rate_yen,0) as daily_rate_yen,
      coalesce(ct.monthly_rate_yen,0) as monthly_rate_yen,
      coalesce(ct.square_meter_unit_price_yen,0) as square_meter_unit_price_yen,
      coalesce(ct.square_meter_quantity,0) as square_meter_quantity,
      coalesce(ct.contract_amount_yen,0) as contract_amount_yen
    into pref
    from public.site_calculation_source_preferences scsp
    join public.trade_companies tc
      on tc.id=scsp.trade_company_id and tc.company_id=cid
    left join public.trade_company_contracts ct
      on ct.company_id=cid and ct.trade_company_id=tc.id
    where scsp.company_id=cid
      and scsp.site_id=s.id
      and scsp.output_type='invoice'
      and scsp.source='trade_company'
    limit 1;

    if pref.source='trade_company' then
      if pref.contract_method='daily' then
        unit_rate:=pref.daily_rate_yen;
        method_label:=unit_rate::int::text;
      elsif pref.contract_method='monthly' then
        unit_rate:=pref.monthly_rate_yen;
        method_label:=unit_rate::int::text;
      elsif pref.contract_method='square_meter' then
        unit_rate:=round(pref.square_meter_unit_price_yen*pref.square_meter_quantity);
        method_label:=pref.square_meter_unit_price_yen::int::text||'×'||trim(to_char(pref.square_meter_quantity,'FM999999990.###'));
      elsif pref.contract_method='contract' then
        unit_rate:=pref.contract_amount_yen;
        method_label:=unit_rate::int::text;
      else
        unit_rate:=0;
        method_label:='未設定';
      end if;
    elsif s.billing_unit_price_yen>0 then
      unit_rate:=s.billing_unit_price_yen;
      method_label:=unit_rate::int::text;
    elsif s.billing_monthly_rate_yen>0 then
      unit_rate:=s.billing_monthly_rate_yen;
      method_label:=unit_rate::int::text;
    elsif s.billing_square_meter_unit_price_yen>0 and s.billing_square_meter_quantity>0 then
      unit_rate:=round(s.billing_square_meter_unit_price_yen*s.billing_square_meter_quantity);
      method_label:=s.billing_square_meter_unit_price_yen::int::text||'×'||trim(to_char(s.billing_square_meter_quantity,'FM999999990.###'));
    elsif s.billing_contract_amount_yen>0 then
      unit_rate:=s.billing_contract_amount_yen;
      method_label:=unit_rate::int::text;
    else
      unit_rate:=0;
      method_label:='未設定';
    end if;

    -- Normal/daytime block.
    if day_days>0 then
      a:=round(day_days*unit_rate);
      b:=0;
      c:=round(day_overtime*s.overtime_hour_rate_yen);

      lines:=lines||jsonb_build_array(jsonb_build_object(
        'site_label',s.name,'work_content','',
        'quantity',day_days,'unit_price',unit_rate,
        'unit_price_text',method_label,'amount',a
      ));

      for allowance_cfg in
        select allowance_name as name,count(*)::numeric as qty
        from public.attendance_entries e,
             unnest(coalesce(e.allowance_names,'{}'::text[])) allowance_name
        where e.company_id=cid
          and e.site_id=s.id
          and e.work_date between first_day and last_day
          and e.work_category in ('day','holiday')
          and nullif(trim(allowance_name),'') is not null
        group by allowance_name
        order by allowance_name
      loop
        allowance_count:=allowance_cfg.qty;
        allowance_rate:=case
          when allowance_cfg.name=s.allowance_1_name then s.allowance_1_amount
          when allowance_cfg.name=s.allowance_2_name then s.allowance_2_amount
          when allowance_cfg.name=s.allowance_3_name then s.allowance_3_amount
          else 0
        end;
        b:=b+round(allowance_count*allowance_rate);
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label','〃','work_content','（手当て）',
          'quantity',allowance_count,'unit_price',allowance_rate,
          'unit_price_text',allowance_rate::int::text,
          'amount',round(allowance_count*allowance_rate),
          'allowance_name',allowance_cfg.name
        ));
      end loop;

      early_amount:=round(day_early*s.early_hour_rate_yen);
      if day_early>0 then
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label','〃','work_content','（早出）',
          'quantity',day_early,'unit_price',s.early_hour_rate_yen,
          'unit_price_text',s.early_hour_rate_yen::int::text,
          'amount',early_amount
        ));
      end if;

      if day_overtime>0 then
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label','〃','work_content','（残業）',
          'quantity',day_overtime,'unit_price',s.overtime_hour_rate_yen,
          'unit_price_text',s.overtime_hour_rate_yen::int::text,'amount',c
        ));
      end if;

      d:=round((a+b+early_amount+c)*s.welfare_rate/100);
      set_pre_tax:=a+b+early_amount+c+d;
      site_tax:=round(set_pre_tax*v_tax_rate/100);
      total_welfare:=total_welfare+d;
      site_pre_tax:=site_pre_tax+set_pre_tax;
      site_tax_total:=site_tax_total+site_tax;

      lines:=lines||jsonb_build_array(
        jsonb_build_object(
          'site_label','〃','work_content','（法定福利費）',
          'quantity',0,'unit_price',0,'unit_price_text','',
          'amount',d
        ),
        jsonb_build_object(
          'site_label','〃','work_content','（消費税）',
          'quantity',0,'unit_price',0,
          'unit_price_text',trim(to_char(v_tax_rate,'FM999990.###'))||'%',
          'amount',site_tax
        )
      );
    end if;

    -- Night block uses the site's one-day billing rate x 1.5.
    if night_days>0 then
      night_rate:=round(
        (case when s.billing_unit_price_yen>0 then s.billing_unit_price_yen else unit_rate end)
        *1.5
      );
      a:=round(night_days*night_rate);
      b:=0;
      c:=round(night_overtime*s.overtime_hour_rate_yen);

      lines:=lines||jsonb_build_array(jsonb_build_object(
        'site_label',s.name,'work_content','夜間作業',
        'quantity',night_days,'unit_price',night_rate,
        'unit_price_text',night_rate::int::text,'amount',a
      ));

      for allowance_cfg in
        select allowance_name as name,count(*)::numeric as qty
        from public.attendance_entries e,
             unnest(coalesce(e.allowance_names,'{}'::text[])) allowance_name
        where e.company_id=cid
          and e.site_id=s.id
          and e.work_date between first_day and last_day
          and e.work_category in ('night','holiday_night')
          and nullif(trim(allowance_name),'') is not null
        group by allowance_name
        order by allowance_name
      loop
        allowance_count:=allowance_cfg.qty;
        allowance_rate:=case
          when allowance_cfg.name=s.allowance_1_name then s.allowance_1_amount
          when allowance_cfg.name=s.allowance_2_name then s.allowance_2_amount
          when allowance_cfg.name=s.allowance_3_name then s.allowance_3_amount
          else 0
        end;
        b:=b+round(allowance_count*allowance_rate);
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label','〃','work_content','（手当て）',
          'quantity',allowance_count,'unit_price',allowance_rate,
          'unit_price_text',allowance_rate::int::text,
          'amount',round(allowance_count*allowance_rate),
          'allowance_name',allowance_cfg.name
        ));
      end loop;

      early_amount:=round(night_early*s.early_hour_rate_yen);
      if night_early>0 then
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label','〃','work_content','（早出）',
          'quantity',night_early,'unit_price',s.early_hour_rate_yen,
          'unit_price_text',s.early_hour_rate_yen::int::text,
          'amount',early_amount
        ));
      end if;

      if night_overtime>0 then
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label','〃','work_content','（残業）',
          'quantity',night_overtime,'unit_price',s.overtime_hour_rate_yen,
          'unit_price_text',s.overtime_hour_rate_yen::int::text,'amount',c
        ));
      end if;

      d:=round((a+b+early_amount+c)*s.welfare_rate/100);
      set_pre_tax:=a+b+early_amount+c+d;
      site_tax:=round(set_pre_tax*v_tax_rate/100);
      total_welfare:=total_welfare+d;
      site_pre_tax:=site_pre_tax+set_pre_tax;
      site_tax_total:=site_tax_total+site_tax;

      lines:=lines||jsonb_build_array(
        jsonb_build_object(
          'site_label','〃','work_content','（法定福利費）',
          'quantity',0,'unit_price',0,'unit_price_text','',
          'amount',d
        ),
        jsonb_build_object(
          'site_label','〃','work_content','（消費税）',
          'quantity',0,'unit_price',0,
          'unit_price_text',trim(to_char(v_tax_rate,'FM999990.###'))||'%',
          'amount',site_tax
        )
      );
    end if;

    total_pre_tax:=total_pre_tax+site_pre_tax;
    total_tax:=total_tax+site_tax_total;

    sites_json:=sites_json||jsonb_build_array(jsonb_build_object(
      'site_id',s.id,
      'site_name',s.name,
      'manual_adjustment',0,
      'welfare_rate_bps',s.welfare_rate*100,
      'subtotal',site_pre_tax,
      'tax',site_tax_total,
      'grand_total',site_pre_tax+site_tax_total,
      'lines',lines
    ));
  end loop;

  if n=0 then
    if existing.id is not null
       and existing.status='draft'
       and existing.automatic_calculation then
      delete from public.invoices where id=existing.id;
    end if;
    return;
  end if;

  snapshot_value:=jsonb_build_object(
    'customer_name',customer_name,
    'customer_missing',v_system_customer,
    'billing_period',extract(year from first_day)::text||'年'||extract(month from first_day)::text||'月',
    'tax_rate_bps',v_tax_rate*100,
    'subtotal',total_pre_tax,
    'tax',total_tax,
    'grand_total',total_pre_tax+total_tax,
    'sites',sites_json
  );

  if existing.id is null then
    insert into public.invoices(
      company_id,customer_id,billing_period_start,billing_period_end,status,
      subtotal,tax,welfare_amount,grand_total,snapshot,
      automatic_calculation,calculation_blocked
    )
    values(
      cid,customer,first_day,last_day,'draft',
      total_pre_tax::int,total_tax::int,total_welfare::int,
      (total_pre_tax+total_tax)::int,snapshot_value,true,false
    );
  elsif existing.snapshot is distinct from snapshot_value
     or existing.calculation_blocked then
    perform set_config('sko.invoice_auto_refresh','1',true);
    update public.invoices
    set subtotal=total_pre_tax::int,
        tax=total_tax::int,
        welfare_amount=total_welfare::int,
        grand_total=(total_pre_tax+total_tax)::int,
        snapshot=snapshot_value,
        calculation_blocked=false,
        updated_at=now()
    where id=existing.id;
    perform set_config('sko.invoice_auto_refresh','0',true);
  end if;
end;
$function$;


create or replace function private.invoice_manual_override_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(current_setting('sko.invoice_auto_refresh',true),'') <> '1'
     and pg_trigger_depth()=1
     and old.automatic_calculation
     and (new.subtotal,new.tax,new.grand_total,new.snapshot)
       is distinct from
       (old.subtotal,old.tax,old.grand_total,old.snapshot) then
    new.automatic_calculation:=false;
  end if;
  return new;
end;
$$;
