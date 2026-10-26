-- INCOMPLETE REVIEW ONLY. NOT DEPLOYABLE.
CREATE OR REPLACE FUNCTION private.refresh_automatic_invoice(cid uuid, customer uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  named_items jsonb; named_item jsonb; named_final numeric:=0;
  expense_component jsonb; expense_amount numeric:=0;
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
  billing_method text;
  fixed_quantity numeric;
  fixed_unit_price numeric;
  effective_overrides jsonb;
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
  route_parts jsonb; route_blocked boolean:=false;
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

  if found and (existing.status<>'draft' or existing.finalized_at is not null or existing.approval_finalized_at is not null or coalesce(existing.invoice_seal_frozen,false) or exists(select 1 from public.invoice_approvals ia where ia.invoice_id=existing.id and ia.status='approved')) then
    return;
  end if;
  if existing.id is null and exists(
    select 1 from public.invoices
    where company_id=cid
      and customer_id=customer
      and billing_period_start=first_day
  ) then return; end if;

  if existing.snapshot?'document_adjustments_v1' and not exists(
    select 1 from document_adjustment_private.rollout r where r.company_id=cid and r.enabled
  ) then return;end if;
  perform document_adjustment_private.ensure_occurrences(cid,'invoice',customer,first_day);
  named_items:=document_adjustment_private.active_items(cid,'invoice',customer,first_day);
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
      and (exists(
        select 1
        from public.attendance_entries e
        where e.site_id=st.id
          and e.company_id=cid
          and e.work_date between first_day and last_day
      ) or exists(select 1 from jsonb_array_elements(named_items) x where x->>'calculation_mode'='before_charges' and x->>'site_id'=st.id::text))
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

    billing_method:='daily';
    fixed_quantity:=1;
    fixed_unit_price:=0;
    if pref.source='trade_company' then
      if pref.contract_method='daily' then
        unit_rate:=pref.daily_rate_yen;
        method_label:=unit_rate::int::text;
      elsif pref.contract_method='monthly' then
        billing_method:='monthly';
        unit_rate:=pref.monthly_rate_yen;
        method_label:=unit_rate::int::text;
      elsif pref.contract_method='square_meter' then
        billing_method:='square_meter';
        fixed_quantity:=pref.square_meter_quantity;
        fixed_unit_price:=pref.square_meter_unit_price_yen;
        unit_rate:=round(pref.square_meter_unit_price_yen*pref.square_meter_quantity);
        method_label:=pref.square_meter_unit_price_yen::int::text||'×'||pref.square_meter_quantity::text;
      elsif pref.contract_method='contract' then
        billing_method:='contract';
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
      billing_method:='monthly';
      unit_rate:=s.billing_monthly_rate_yen;
      method_label:=unit_rate::int::text;
    elsif s.billing_square_meter_unit_price_yen>0 and s.billing_square_meter_quantity>0 then
      billing_method:='square_meter';
      fixed_quantity:=s.billing_square_meter_quantity;
      fixed_unit_price:=s.billing_square_meter_unit_price_yen;
      unit_rate:=round(s.billing_square_meter_unit_price_yen*s.billing_square_meter_quantity);
      method_label:=s.billing_square_meter_unit_price_yen::int::text||'×'||s.billing_square_meter_quantity::text;
    elsif s.billing_contract_amount_yen>0 then
      billing_method:='contract';
      unit_rate:=s.billing_contract_amount_yen;
      method_label:=unit_rate::int::text;
    else
      unit_rate:=0;
      method_label:='未設定';
    end if;

    -- Existing registered month/area/contract fields describe one fixed
    -- site-month charge, not an attendance-day unit price.
    if billing_method<>'daily' and unit_rate>0 then
      site_pre_tax:=unit_rate;
      lines:=lines||jsonb_build_array(jsonb_build_object(
        'site_label',s.name,
        'work_content',case billing_method when 'monthly' then '月単価'
          when 'square_meter' then '平米' else '請負金額' end,
        'quantity',fixed_quantity,
        'unit_price',case when billing_method='square_meter' then fixed_unit_price else unit_rate end,
        'unit_price_text',case when billing_method='square_meter' then fixed_unit_price::text else unit_rate::text end,
        'amount',unit_rate
      ));
    end if;
    -- Positive JSON overrides win; retained legacy direct amounts are next.
    -- Zero JSON values mean automatic calculation in the existing editor.
    effective_overrides:=s.billing_rate_overrides;
    if coalesce((effective_overrides->>'overtime')::numeric,0)<=0
       and s.billing_overtime_hour_rate_yen>0 then
      effective_overrides:=jsonb_set(effective_overrides,'{overtime}',to_jsonb(s.billing_overtime_hour_rate_yen),true);
    end if;
    if coalesce((effective_overrides->>'early')::numeric,0)<=0
       and s.billing_early_hour_rate_yen>0 then
      effective_overrides:=jsonb_set(effective_overrides,'{early}',to_jsonb(s.billing_early_hour_rate_yen),true);
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
        unit_rate,s.billing_rate_formula,effective_overrides,category_kind
      );
      overtime_rate:=private.resolve_rate_formula(
        unit_rate,s.billing_rate_formula,effective_overrides,
        case rate_group.category
          when 'night' then 'night_overtime'
          when 'holiday' then 'holiday_overtime'
          when 'holiday_night' then 'holiday_night_overtime'
          else 'overtime'
        end
      );
      early_rate:=case
        when coalesce((effective_overrides->>'early')::numeric,0)>0 then round((effective_overrides->>'early')::numeric)
        when rate_group.category='day' then private.resolve_rate_formula(
          unit_rate,s.billing_rate_formula,effective_overrides,'early'
        )
        else round(
          category_rate
          / greatest(coalesce((s.billing_rate_formula->>'hours_per_day')::numeric,8),0.01)
          * coalesce((s.billing_rate_formula->>'early_multiplier')::numeric,1.25)
        )
      end;

      if billing_method='daily' and rate_group.days>0 then
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
            s.billing_rate_formula,case rate_group.category
              when 'night' then 'night_early' when 'holiday' then 'holiday_early'
              when 'holiday_night' then 'holiday_night_early' else 'early' end
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

    for named_item in select value from jsonb_array_elements(
      document_adjustment_private.active_items(cid,'invoice',customer,first_day))
      where value->>'calculation_mode'='before_charges' and value->>'site_id'=s.id::text
    loop
      a:=(named_item->>'amount_yen')::numeric * case when named_item->>'sign'='minus' then -1 else 1 end;
      site_pre_tax:=site_pre_tax+a;
      lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃',
        'work_content',named_item->>'title','quantity',1,'unit_price',a,
        'unit_price_text',a::text,'amount',a,'document_adjustment',named_item));
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
        'unit_price_text',trim(trailing '.' from trim(trailing '0' from to_char(v_tax_rate,'FM999999990.999999999')))||'%',
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

  route_parts:=private.route_billing_invoice_components(cid,customer,first_day,last_day);
  route_blocked:=(route_parts->>'blocked')::boolean;
  sites_json:=sites_json||(route_parts->'sites');
  total_pre_tax:=total_pre_tax+(route_parts->>'subtotal')::numeric;
  total_tax:=total_tax+(route_parts->>'tax')::numeric;
  total_welfare:=total_welfare+(route_parts->>'welfare')::numeric;
  if (route_parts->>'has_requests')::boolean or route_blocked then n:=n+1;end if;
  
 expense_component:=private.expense_cost_components('invoice',cid,customer,first_day,last_day,existing.id);
 expense_amount:=(expense_component->>'amount_yen')::numeric;
  if n=0 and expense_amount=0 and jsonb_array_length(named_items)=0 and not coalesce(existing.snapshot?'document_adjustments_v1',false) and existing.id is not null and existing.snapshot?'expense_extra_source_version' then
  update public.invoices set subtotal=0,tax=0,welfare_amount=0,grand_total=0,
   snapshot=existing.snapshot||jsonb_build_object('sites','[]'::jsonb,'subtotal',0,'tax',0,'grand_total',0,
    'route_quantity_pending',false,'route_source_pending',route_blocked,
    'route_signed_checkout_version',1,'expense_extra_amount_yen',0,'expense_extra_claims','[]'::jsonb),
   calculation_blocked=route_blocked,updated_at=now() where id=existing.id;
  return;
 end if;
 if n=0 and expense_amount=0 and jsonb_array_length(named_items)=0 and not coalesce(existing.snapshot?'document_adjustments_v1',false) then
 
    if existing.id is not null
       and existing.status='draft'
       and existing.automatic_calculation then
      delete from public.invoices where id=existing.id;
    end if;
    return;
  end if;

  named_items:=document_adjustment_private.active_items(cid,'invoice',customer,first_day);
  select coalesce(sum((x->>'amount_yen')::numeric * case when x->>'sign'='minus' then -1 else 1 end),0)
  into named_final from jsonb_array_elements(named_items) x where x->>'calculation_mode'='settlement_yen';
  snapshot_value:=jsonb_build_object(
    'customer_name',customer_name,
    'customer_missing',v_system_customer,
    'billing_period',extract(year from first_day)::text||'年'||extract(month from first_day)::text||'月',
    'tax_rate_bps',v_tax_rate*100,
    'subtotal',total_pre_tax,
    'tax',total_tax,
    'grand_total',total_pre_tax+total_tax+expense_amount+named_final,
    'sites',sites_json
  );

  if jsonb_array_length(named_items)>0 or coalesce(existing.snapshot?'document_adjustments_v1',false) then
  snapshot_value:=snapshot_value||jsonb_build_object('document_adjustments_v1',named_items,'document_final_adjustment_yen',named_final);
  end if;
  snapshot_value:=snapshot_value||jsonb_build_object('route_quantity_pending',false,
  'route_source_pending',route_blocked,'route_signed_checkout_version',1,
  'route_source_issues',route_parts->'source_issues');
  
 if coalesce((expense_component->>'has_choices')::boolean,false) or existing.snapshot?'expense_extra_source_version' then
  snapshot_value:=snapshot_value||jsonb_build_object('expense_extra_amount_yen',expense_amount,
   'expense_extra_claims',expense_component->'claims','expense_extra_source_version',1);
 end if;
 snapshot_value:=snapshot_value||private.document_company_seal_snapshot
 (existing.snapshot,cid,existing.id is null);
  if existing.id is null then
    insert into public.invoices(
      company_id,customer_id,billing_period_start,billing_period_end,status,
      subtotal,tax,welfare_amount,grand_total,snapshot,
      automatic_calculation,calculation_blocked
    )
    values(
      cid,customer,first_day,last_day,'draft',
      total_pre_tax::int,total_tax::int,total_welfare::int,
      (total_pre_tax+total_tax+expense_amount+named_final)::int,snapshot_value,true,route_blocked
    );
  elsif existing.snapshot is distinct from snapshot_value
     or existing.calculation_blocked is distinct from route_blocked then
    perform set_config('sko.invoice_auto_refresh','1',true);
    update public.invoices
    set subtotal=total_pre_tax::int,
        tax=total_tax::int,
        welfare_amount=total_welfare::int,
        grand_total=(total_pre_tax+total_tax+expense_amount+named_final)::int,
        snapshot=snapshot_value,
        calculation_blocked=route_blocked,
        updated_at=now()
    where id=existing.id;
    perform set_config('sko.invoice_auto_refresh','0',true);
  end if;
  if jsonb_array_length(named_items)>0 then
  perform document_adjustment_private.bind_occurrences(cid,'invoice',customer,first_day,
    (select id from public.invoices where company_id=cid and customer_id=customer and billing_period_start=first_day and automatic_calculation));
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.certificate_calculation_rows(v_company_id uuid, v_partner_id uuid, v_start date, v_end date)
 RETURNS TABLE(site_name text, work_content text, quantity_label text, unit_price_yen integer, amount_yen integer)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  settings public.partner_payment_settings%rowtype;
  hours_per_day numeric:=8;
  overtime_mul numeric:=1.25;
  early_mul numeric:=1.25;
  night_mul numeric:=1.5;
  night_ot_mul numeric:=1.5;
  holiday_mul numeric:=1.35;
  holiday_ot_mul numeric:=1.35;
  holiday_night_mul numeric:=1.6;
  holiday_night_ot_mul numeric:=1.6;
  r_daily integer:=0;
  r_ot integer:=0;
  r_early integer:=0;
  r_night integer:=0;
  r_night_ot integer:=0;
  r_holiday integer:=0;
  r_holiday_ot integer:=0;
  r_holiday_night integer:=0;
  r_holiday_night_ot integer:=0;
  r_night_early integer:=0;
  r_holiday_early integer:=0;
  r_holiday_night_early integer:=0;
begin
  select * into settings from public.partner_payment_settings
  where company_id=v_company_id and partner_company_id=v_partner_id;

  r_daily:=private.resolve_rate_formula(coalesce(settings.daily_rate_yen,0),settings.rate_formula,'{}'::jsonb,'daily')::integer;
  r_ot:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('overtime',coalesce(settings.overtime_hour_rate_yen,0)),
    'overtime'
  )::integer;
  r_early:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('early',coalesce(settings.early_hour_rate_yen,0)),
    'early'
  )::integer;
  r_night:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('night',coalesce(settings.night_day_rate_yen,0)),
    'night'
  )::integer;
  r_night_ot:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('night_overtime',coalesce(settings.night_overtime_hour_rate_yen,0)),
    'night_overtime'
  )::integer;
  r_holiday:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('holiday',coalesce(settings.holiday_day_rate_yen,0)),
    'holiday'
  )::integer;
  r_holiday_ot:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('holiday_overtime',coalesce(settings.holiday_overtime_hour_rate_yen,0)),
    'holiday_overtime'
  )::integer;
  r_holiday_night:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('holiday_night',coalesce(settings.holiday_night_day_rate_yen,0)),
    'holiday_night'
  )::integer;
  r_holiday_night_ot:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('holiday_night_overtime',coalesce(settings.holiday_night_overtime_hour_rate_yen,0)),
    'holiday_night_overtime'
  )::integer;

  -- Early work uses the independently registered early multiplier in every category.
  -- A positive direct early rate overrides every category consistently.
  hours_per_day:=greatest(coalesce((settings.rate_formula->>'hours_per_day')::numeric,8),0.01);
  early_mul:=coalesce((settings.rate_formula->>'early_multiplier')::numeric,1.25);
  r_night_early:=case when coalesce(settings.early_hour_rate_yen,0)>0
    then settings.early_hour_rate_yen else round(r_night/hours_per_day*early_mul)::integer end;
  r_holiday_early:=case when coalesce(settings.early_hour_rate_yen,0)>0
    then settings.early_hour_rate_yen else round(r_holiday/hours_per_day*early_mul)::integer end;
  r_holiday_night_early:=case when coalesce(settings.early_hour_rate_yen,0)>0
    then settings.early_hour_rate_yen else round(r_holiday_night/hours_per_day*early_mul)::integer end;

  return query
  with source as (
    select
      coalesce(nullif(s.formal_name,''),s.name,'現場未設定') as site_name,
      coalesce(a.work_category,'day') as work_category,
      sum(coalesce(a.base_man_days,0)) as man_days,
      sum(coalesce(a.overtime_hours,0)) as overtime_hours,
      sum(coalesce(a.early_hours,0)) as early_hours
    from public.attendance_entries a
    join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
    left join public.sites s on s.id=a.site_id and s.company_id=a.company_id
    where a.company_id=v_company_id
      and w.partner_company_id=v_partner_id
      and a.work_date between v_start and v_end
    group by
      coalesce(nullif(s.formal_name,''),s.name,'現場未設定'),
      coalesce(a.work_category,'day')
  ),
  base_lines as (
    select src.site_name,
      case src.work_category
        when 'night' then '夜勤'
        when 'holiday' then '休日出勤'
        when 'holiday_night' then '休日夜勤'
        else '通常作業'
      end as work_content,
      trim_scale(src.man_days)::text||'人' as quantity_label,
      case src.work_category
        when 'night' then r_night
        when 'holiday' then r_holiday
        when 'holiday_night' then r_holiday_night
        else r_daily
      end as unit_price_yen,
      round(src.man_days * case src.work_category
        when 'night' then r_night
        when 'holiday' then r_holiday
        when 'holiday_night' then r_holiday_night
        else r_daily
      end)::integer as amount_yen,
      1 as sort_order
    from source src where man_days<>0
    union all
    select src.site_name,
      case src.work_category
        when 'night' then '夜勤残業'
        when 'holiday' then '休日残業'
        when 'holiday_night' then '休日夜勤残業'
        else '残業'
      end,
      trim_scale(src.overtime_hours)::text||'H',
      case src.work_category
        when 'night' then r_night_ot
        when 'holiday' then r_holiday_ot
        when 'holiday_night' then r_holiday_night_ot
        else r_ot
      end,
      round(src.overtime_hours * case src.work_category
        when 'night' then r_night_ot
        when 'holiday' then r_holiday_ot
        when 'holiday_night' then r_holiday_night_ot
        else r_ot
      end)::integer,
      2
    from source src where overtime_hours<>0
    union all
    select src.site_name,'早出',
      trim_scale(src.early_hours)::text||'H',
      case src.work_category
        when 'night' then r_night_early
        when 'holiday' then r_holiday_early
        when 'holiday_night' then r_holiday_night_early
        else r_early
      end,
      round(src.early_hours * case src.work_category
        when 'night' then r_night_early
        when 'holiday' then r_holiday_early
        when 'holiday_night' then r_holiday_night_early
        else r_early
      end)::integer,
      3
    from source src where early_hours<>0
  ),
  allowance_lines as (
    select
      coalesce(nullif(s.formal_name,''),s.name,'現場未設定') as site_name,
      '（'||cfg.name||'）'::text as work_content,
      count(*)::text||'回' as quantity_label,
      cfg.amount_yen::integer as unit_price_yen,
      (count(*)*cfg.amount_yen)::integer as amount_yen,
      4 as sort_order
    from public.attendance_entries a
    join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
    left join public.sites s on s.id=a.site_id and s.company_id=a.company_id
    cross join lateral unnest(coalesce(a.allowance_names,'{}'::text[])) n(name)
    join lateral (
      select
        x->>'name' as name,
        greatest(coalesce((x->>'amount_yen')::integer,0),0) as amount_yen
      from jsonb_array_elements(coalesce(settings.allowances,'[]'::jsonb)) x
      where x->>'name'=n.name
    ) cfg on true
    where a.company_id=v_company_id
      and w.partner_company_id=v_partner_id
      and a.work_date between v_start and v_end
      and cfg.amount_yen>0
    group by coalesce(nullif(s.formal_name,''),s.name,'現場未設定'),cfg.name,cfg.amount_yen
  ),
  named_lines as (
    select '〃'::text as site_name,x->>'title' as work_content,'1'::text as quantity_label,
      ((x->>'amount_yen')::bigint * case when x->>'sign'='minus' then -1 else 1 end)::integer as unit_price_yen,
      ((x->>'amount_yen')::bigint * case when x->>'sign'='minus' then -1 else 1 end)::integer as amount_yen,
      5 as sort_order
    from jsonb_array_elements(document_adjustment_private.active_items(
      v_company_id,'payment_certificate',v_partner_id,v_start)) x
    where x->>'calculation_mode'='before_charges'
  ),
  pre_totals as (
    select coalesce(sum(q.amount_yen),0)::integer as subtotal
    from (
      select bl.amount_yen from base_lines bl
      union all
      select al.amount_yen from allowance_lines al
      union all select nl.amount_yen from named_lines nl
    ) q
  ),
  summary_lines as (
    select '〃'::text as site_name,'福利厚生費'::text as work_content,
      trim_scale(settings.welfare_rate)::text||'%' as quantity_label,
      0::integer as unit_price_yen,
      round(p.subtotal*coalesce(settings.welfare_rate,0)/100)::integer as amount_yen,
      90 as sort_order
    from pre_totals p where coalesce(settings.welfare_rate,0)>0
    union all
    select '〃','消費税',
      trim_scale(settings.tax_rate)::text||'%',
      0,
      round((p.subtotal + round(p.subtotal*coalesce(settings.welfare_rate,0)/100))
        *coalesce(settings.tax_rate,10)/100)::integer,
      91
    from pre_totals p where coalesce(settings.tax_rate,0)>0
  ),
  lines as (
    select * from base_lines
    union all select * from allowance_lines
    union all select * from named_lines
    union all select * from summary_lines
  )
  select l.site_name,l.work_content,l.quantity_label,l.unit_price_yen,l.amount_yen
  from lines l
  order by l.site_name,l.sort_order,l.work_content;
end
$function$
;

CREATE OR REPLACE FUNCTION private.refresh_automatic_payment_certificate(cid uuid, partner uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 named_items jsonb;named_plus numeric:=0;named_minus numeric:=0;
 expense_component jsonb; expense_amount numeric:=0;
 first_day date:=date_trunc('month',day)::date;
 last_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
 existing public.payment_certificates%rowtype;
 settings public.partner_payment_settings%rowtype;
 attendance_count int:=0;
 gross numeric:=0;
 subtotal numeric:=0;
 welfare numeric:=0;
 tax numeric:=0;
 partner_name text;
 snapshot_value jsonb;
 use_v2 boolean; direction_doc uuid; direction_revision integer;
 expense_deductions numeric:=0; expense_net numeric;
 calculation_rows jsonb;
 s record;
 allowance_cfg record;
 allowance_qty numeric;
 allowance_rate numeric;
 hours_per_day numeric:=8;
 overtime_mul numeric:=1.25;
 early_mul numeric:=1.25;
 night_mul numeric:=1.5;
 night_ot_mul numeric:=1.5;
 holiday_mul numeric:=1.35;
 holiday_ot_mul numeric:=1.35;
 holiday_night_mul numeric:=1.6;
 holiday_night_ot_mul numeric:=1.6;
 r_daily numeric:=0;
 r_ot numeric:=0;
 r_early numeric:=0;
 r_night numeric:=0;
 r_night_ot numeric:=0;
 r_holiday numeric:=0;
 r_holiday_ot numeric:=0;
 r_holiday_night numeric:=0;
 r_holiday_night_ot numeric:=0;
begin
 if auth.uid() is null or partner is null then return; end if;
 perform pg_advisory_xact_lock(hashtextextended(
   'payment-certificate:'||cid::text||partner::text||first_day::text,0
 ));

 select * into existing
 from public.payment_certificates
 where company_id=cid and partner_company_id=partner
   and period_start=first_day and period_end=last_day
 for update;
 if found and (existing.status<>'draft' or existing.finalized_at is not null or not existing.automatic_calculation) then return; end if;
 if existing.snapshot?'document_adjustments_v1' and not exists(select 1 from document_adjustment_private.rollout r where r.company_id=cid and r.enabled) then return;end if;
 perform document_adjustment_private.ensure_occurrences(cid,'payment_certificate',partner,first_day);
 named_items:=document_adjustment_private.active_items(cid,'payment_certificate',partner,first_day);
 if existing.snapshot?'expense_cost_direction_v2' and not private.expense_cost_direction_v2_enabled(cid) then return;end if;
 use_v2:=private.expense_cost_direction_v2_enabled(cid) and (existing.id is null or existing.snapshot?'expense_cost_direction_v2');
 direction_doc:=coalesce(existing.id,gen_random_uuid());direction_revision:=coalesce(existing.revision,1);

 select * into settings
 from public.partner_payment_settings
 where company_id=cid and partner_company_id=partner;

 select pc.name into partner_name
 from public.partner_companies pc
 where pc.id=partner and pc.company_id=cid;

 select count(*) into attendance_count
 from public.attendance_entries a
 join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
 where a.company_id=cid
   and w.partner_company_id=partner
   and a.work_date between first_day and last_day;

 
 expense_component:=private.expense_cost_components('paymentCertificate',cid,partner,first_day,last_day,existing.id);
 expense_amount:=(expense_component->>'amount_yen')::numeric;
 if attendance_count=0 and jsonb_array_length(named_items)=0 and not coalesce(existing.snapshot?'document_adjustments_v1',false) and not (expense_component->>'has_choices')::boolean
  and existing.id is not null and existing.snapshot?'expense_extra_source_version' then
  update public.payment_certificates set gross_amount=0,deductions=0,net_amount=0,
   snapshot=existing.snapshot||jsonb_build_object('calculation_rows','[]'::jsonb,'attendance_count',0,
    'expense_extra_amount_yen',0,'expense_extra_claims','[]'::jsonb),
   calculation_blocked=false,revision=revision+1,updated_at=now() where id=existing.id;
  return;
 end if;
 if attendance_count=0 and jsonb_array_length(named_items)=0 and not coalesce(existing.snapshot?'document_adjustments_v1',false) and not (expense_component->>'has_choices')::boolean and (not use_v2 or existing.id is null) then
 
   if existing.id is not null and existing.status='draft'
      and existing.automatic_calculation then
     delete from public.payment_certificates where id=existing.id;
   end if;
   return;
 end if;

 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb),coalesce(sum(r.amount_yen),0)
 into calculation_rows,gross
 from private.certificate_calculation_rows(cid,partner,first_day,last_day) r;

 if use_v2 then expense_deductions:=expense_amount;else gross:=gross+expense_amount;end if;
 named_items:=document_adjustment_private.active_items(cid,'payment_certificate',partner,first_day);
 select coalesce(sum((x->>'amount_yen')::numeric) filter(where x->>'sign'='plus'),0),
        coalesce(sum((x->>'amount_yen')::numeric) filter(where x->>'sign'='minus'),0)
 into named_plus,named_minus from jsonb_array_elements(named_items) x
 where x->>'calculation_mode'='settlement_yen';
 gross:=gross+named_plus;expense_deductions:=expense_deductions+named_minus;
 expense_net:=gross-expense_deductions;
 snapshot_value:=jsonb_build_object(
   'partner_company_name',coalesce(partner_name,''),
   'period_start',first_day,'period_end',last_day,
   'attendance_count',attendance_count,
   'settings_missing',settings.partner_company_id is null,
   'rate_formula',coalesce(settings.rate_formula,'{}'::jsonb),
   'welfare_rate',coalesce(settings.welfare_rate,0),
   'tax_rate',coalesce(settings.tax_rate,10),
   'calculation_rows',calculation_rows,
   'calculation_version',2
 );

 
 if jsonb_array_length(named_items)>0 or coalesce(existing.snapshot?'document_adjustments_v1',false) then
 snapshot_value:=snapshot_value||jsonb_build_object('document_adjustments_v1',named_items,'document_final_plus_yen',named_plus,'document_final_minus_yen',named_minus);
 end if;
 if use_v2 then
 snapshot_value:=snapshot_value||jsonb_build_object(
 'expense_cost_direction_v2',private.expense_payment_v2_envelope(cid,direction_doc,partner,first_day,direction_revision,expense_amount,expense_component->'claims'),
 'expense_cost_basis',jsonb_build_object('company_id',cid,'document_id',direction_doc,'subject_id',partner,'month',to_char(first_day,'YYYY-MM'),'document_revision',direction_revision,'gross_before_expense_yen',gross,'other_deductions_yen',named_minus));
 elsif coalesce((expense_component->>'has_choices')::boolean,false) or existing.snapshot?'expense_extra_source_version' then
  snapshot_value:=snapshot_value||jsonb_build_object('expense_extra_amount_yen',expense_amount,
   'expense_extra_claims',expense_component->'claims','expense_extra_source_version',1);
 end if;
 snapshot_value:=snapshot_value||private.document_company_seal_snapshot
 (existing.snapshot,cid,existing.id is null);
  if existing.id is null then
   insert into public.payment_certificates(
     id,company_id,partner_company_id,period_start,period_end,status,
     gross_amount,deductions,net_amount,snapshot,
     automatic_calculation,calculation_blocked
   )
   values(
     direction_doc,cid,partner,first_day,last_day,'draft',
     gross::int,expense_deductions::int,expense_net::int,snapshot_value,true,false
   );
 elsif existing.gross_amount is distinct from gross::int
    or existing.net_amount is distinct from expense_net::int
    or (use_v2 and existing.deductions is distinct from expense_deductions::int)
    or existing.snapshot is distinct from snapshot_value
    or existing.calculation_blocked then
   update public.payment_certificates
   set gross_amount=gross::int,deductions=expense_deductions::int,net_amount=expense_net::int,
       snapshot=case when use_v2 then jsonb_set(jsonb_set(snapshot_value,'{expense_cost_direction_v2,document_revision}',to_jsonb(existing.revision+1)),'{expense_cost_basis,document_revision}',to_jsonb(existing.revision+1)) else snapshot_value end,calculation_blocked=false,
       revision=revision+1,updated_at=now()
   where id=existing.id;
 end if;
 if jsonb_array_length(named_items)>0 then
 perform document_adjustment_private.bind_occurrences(cid,'payment_certificate',partner,first_day,
   (select id from public.payment_certificates where company_id=cid and partner_company_id=partner and period_start=first_day));
 end if;
end
$function$
;

CREATE OR REPLACE FUNCTION private.expense_payment_v2_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare envelope jsonb:=new.snapshot->'expense_cost_direction_v2';basis jsonb;expected jsonb;gross numeric;named_plus numeric:=0;named_minus numeric:=0;named_expected jsonb;
begin
 if tg_op='DELETE' then
 if old.snapshot?'expense_cost_direction_v2' and old.status='finalized' then raise exception 'finalized v2 payment immutable';end if;
 return old;end if;
 if tg_op='UPDATE' and old.snapshot?'expense_cost_direction_v2' then
 if not new.snapshot?'expense_cost_direction_v2' then raise exception 'v2 downgrade refused';end if;
 if old.status='finalized' and (to_jsonb(old)-'updated_at') is distinct from (to_jsonb(new)-'updated_at') then raise exception 'finalized v2 payment immutable';end if;
 end if;
 if not new.snapshot?'expense_cost_direction_v2' then return new;end if;
 if not new.automatic_calculation or new.snapshot?'expense_extra_source_version'
 or new.snapshot?'expense_extra_amount_yen' or new.snapshot?'expense_extra_claims'
 then raise exception 'mixed or manual v2 expense source refused';end if;
 if new.company_id is null or new.id is null or new.partner_company_id is null or new.period_start is null or new.period_end is null
 or new.revision is null or new.gross_amount is null or new.deductions is null or new.net_amount is null
 or jsonb_typeof(new.snapshot->'calculation_rows') is distinct from 'array'
 or jsonb_typeof(envelope) is distinct from 'object' or envelope->>'version' is distinct from '2'
 or new.period_start<>date_trunc('month',new.period_start)::date
 or new.period_end<>(date_trunc('month',new.period_start)+interval '1 month - 1 day')::date
 then raise exception 'v2 document period differs';end if;
 expected:=private.expense_payment_v2_envelope(new.company_id,new.id,new.partner_company_id,new.period_start,new.revision,
 (envelope->>'amount_yen')::numeric,envelope->'claims');
 if envelope is distinct from expected then raise exception 'v2 document scope or claims differ';end if;
 select coalesce(sum((r->>'amount_yen')::numeric),0) into gross from jsonb_array_elements(new.snapshot->'calculation_rows') r;
if new.snapshot?'document_adjustments_v1' then
 named_expected:=document_adjustment_private.ledger_items(new.company_id,'payment_certificate',new.partner_company_id,new.period_start);
 if new.snapshot->'document_adjustments_v1' is distinct from named_expected then
  raise exception 'payment adjustments differ from canonical company/party/month ledger';end if;
 select coalesce(sum((x->>'amount_yen')::numeric) filter(where x->>'sign'='plus'),0),
        coalesce(sum((x->>'amount_yen')::numeric) filter(where x->>'sign'='minus'),0)
 into named_plus,named_minus from jsonb_array_elements(named_expected) x
 where x->>'calculation_mode'='settlement_yen';
 if new.snapshot->'document_final_plus_yen' is distinct from to_jsonb(named_plus)
    or new.snapshot->'document_final_minus_yen' is distinct from to_jsonb(named_minus) then
  raise exception 'payment final adjustment amounts differ from ledger';end if;
elsif new.snapshot?'document_final_plus_yen' or new.snapshot?'document_final_minus_yen' then
 raise exception 'orphan payment adjustment amounts refused';
end if;
gross:=gross+named_plus;
 basis:=jsonb_build_object('company_id',new.company_id,'document_id',new.id,'subject_id',new.partner_company_id,
 'month',to_char(new.period_start,'YYYY-MM'),'document_revision',new.revision,'gross_before_expense_yen',gross,'other_deductions_yen',named_minus);
 if new.snapshot->'expense_cost_basis' is distinct from basis or gross<0 or new.gross_amount<>gross
 or new.deductions<>(envelope->>'amount_yen')::numeric+named_minus or new.net_amount<>gross-new.deductions
 then raise exception 'v2 payment amount or calculation basis differs';end if;
 return new;
end $function$;

