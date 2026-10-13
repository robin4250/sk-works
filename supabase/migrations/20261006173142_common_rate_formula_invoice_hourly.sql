-- Common editable rate formula engine with daily/hourly base support.

CREATE OR REPLACE FUNCTION private.resolve_rate_formula(p_base_rate numeric, p_formula jsonb, p_overrides jsonb, p_kind text)
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
$function$
;

CREATE OR REPLACE FUNCTION private.rate_formula_label(p_formula jsonb, p_kind text)
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
$function$
;

CREATE OR REPLACE FUNCTION private.refresh_automatic_invoice(cid uuid, customer uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  first_day date:=date_trunc('month',day)::date;
  last_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
  existing public.invoices%rowtype;
  s record;
  pref record;
  allowance_cfg record;
  rate_group record;
  category_kind text;
  category_label text;
  category_rate numeric;
  overtime_rate numeric;
  early_rate numeric;
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
      coalesce(fs.billing_overtime_hour_rate_yen,0) as billing_overtime_hour_rate_yen,
      coalesce(fs.billing_early_hour_rate_yen,0) as billing_early_hour_rate_yen,
      coalesce(fs.billing_rate_formula,'{}'::jsonb) as billing_rate_formula,
      coalesce(fs.billing_rate_overrides,'{}'::jsonb) as billing_rate_overrides,
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

    -- Common rate-formula calculation. Day-rate and hourly-base modes use
    -- the same multipliers. A positive override wins over auto calculation.
    for rate_group in
      select
        coalesce(e.work_category,'day') as category,
        coalesce(sum(e.base_man_days),0) as days,
        coalesce(sum(e.overtime_hours),0) as overtime_hours,
        coalesce(sum(e.early_hours),0) as early_hours
      from public.attendance_entries e
      where e.company_id=cid
        and e.site_id=s.id
        and e.work_date between first_day and last_day
      group by coalesce(e.work_category,'day')
      order by coalesce(e.work_category,'day')
    loop
      category_kind:=case rate_group.category
        when 'night' then 'night'
        when 'holiday' then 'holiday'
        when 'holiday_night' then 'holiday_night'
        else 'daily'
      end;
      category_label:=case rate_group.category
        when 'night' then '夜勤'
        when 'holiday' then '休日出勤'
        when 'holiday_night' then '休日夜勤'
        else ''
      end;

      category_rate:=private.resolve_rate_formula(
        unit_rate,s.billing_rate_formula,s.billing_rate_overrides,category_kind
      );
      overtime_rate:=private.resolve_rate_formula(
        unit_rate,s.billing_rate_formula,s.billing_rate_overrides,
        case rate_group.category
          when 'night' then 'night_overtime'
          when 'holiday' then 'holiday_overtime'
          when 'holiday_night' then 'holiday_night_overtime'
          else 'overtime'
        end
      );
      early_rate:=case
        when rate_group.category='day' then private.resolve_rate_formula(
          unit_rate,s.billing_rate_formula,s.billing_rate_overrides,'early'
        )
        else round(
          category_rate
          / greatest(coalesce((s.billing_rate_formula->>'hours_per_day')::numeric,8),0.01)
          * coalesce((s.billing_rate_formula->>'early_multiplier')::numeric,1.25)
        )
      end;

      if rate_group.days>0 then
        a:=round(rate_group.days*category_rate);
        site_pre_tax:=site_pre_tax+a;
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label',case when jsonb_array_length(lines)=0 then s.name else '〃' end,
          'work_content',category_label,
          'quantity',rate_group.days,
          'unit_price',category_rate,
          'unit_price_text',category_rate::int::text,
          'formula',private.rate_formula_label(
            s.billing_rate_formula,category_kind
          ),
          'amount',a
        ));
      end if;

      if rate_group.early_hours>0 then
        a:=round(rate_group.early_hours*early_rate);
        site_pre_tax:=site_pre_tax+a;
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label','〃',
          'work_content',case
            when category_label='' then '（早出）'
            else '（'||category_label||'早出）'
          end,
          'quantity',rate_group.early_hours,
          'unit_price',early_rate,
          'unit_price_text',early_rate::int::text,
          'formula',private.rate_formula_label(
            s.billing_rate_formula,'early'
          ),
          'amount',a
        ));
      end if;

      if rate_group.overtime_hours>0 then
        a:=round(rate_group.overtime_hours*overtime_rate);
        site_pre_tax:=site_pre_tax+a;
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label','〃',
          'work_content',case
            when category_label='' then '（残業）'
            else '（'||category_label||'残業）'
          end,
          'quantity',rate_group.overtime_hours,
          'unit_price',overtime_rate,
          'unit_price_text',overtime_rate::int::text,
          'formula',private.rate_formula_label(
            s.billing_rate_formula,
            case rate_group.category
              when 'night' then 'night_overtime'
              when 'holiday' then 'holiday_overtime'
              when 'holiday_night' then 'holiday_night_overtime'
              else 'overtime'
            end
          ),
          'amount',a
        ));
      end if;
    end loop;

    -- Named allowances are calculated once per site/month.
    for allowance_cfg in
      select allowance_name as name,count(*)::numeric as qty
      from public.attendance_entries e,
           unnest(coalesce(e.allowance_names,'{}'::text[])) allowance_name
      where e.company_id=cid
        and e.site_id=s.id
        and e.work_date between first_day and last_day
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
      if allowance_rate>0 then
        a:=round(allowance_count*allowance_rate);
        site_pre_tax:=site_pre_tax+a;
        lines:=lines||jsonb_build_array(jsonb_build_object(
          'site_label','〃',
          'work_content','（'||allowance_cfg.name||'）',
          'quantity',allowance_count,
          'unit_price',allowance_rate,
          'unit_price_text',allowance_rate::int::text,
          'amount',a,
          'allowance_name',allowance_cfg.name
        ));
      end if;
    end loop;

    d:=round(site_pre_tax*s.welfare_rate/100);
    if d>0 then
      lines:=lines||jsonb_build_array(jsonb_build_object(
        'site_label','〃','work_content','（法定福利費）',
        'quantity',0,'unit_price',0,'unit_price_text','',
        'amount',d
      ));
    end if;
    site_pre_tax:=site_pre_tax+d;
    total_welfare:=total_welfare+d;

    site_tax:=round(site_pre_tax*v_tax_rate/100);
    if site_tax>0 then
      lines:=lines||jsonb_build_array(jsonb_build_object(
        'site_label','〃','work_content','（消費税）',
        'quantity',0,'unit_price',0,
        'unit_price_text',trim(to_char(v_tax_rate,'FM999990.###'))||'%',
        'amount',site_tax
      ));
    end if;
    site_tax_total:=site_tax;
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
$function$
;
