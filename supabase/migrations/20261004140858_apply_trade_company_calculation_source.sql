-- Mirrors production migration applying the selected calculation source.\n-- Trade-company contracts and admin-site settings never calculate together.\n\nCREATE OR REPLACE FUNCTION private.refresh_automatic_invoice(cid uuid, customer uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 first_day date:=date_trunc('month',day)::date;
 last_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
 existing public.invoices%rowtype; s record; sites_json jsonb:='[]'; lines jsonb;
 n int:=0; site_total numeric; total numeric:=0; welfare_total numeric:=0; welfare numeric; v_tax_rate numeric; tax_value numeric;
 attendance_man_days numeric; customer_name text; snapshot_value jsonb; method_count int; rate numeric;
 v_system_customer boolean:=false;
 pref record;
 fixed_trade_seen uuid[]:='{}';
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
 perform pg_advisory_xact_lock(hashtextextended('invoice:'||cid::text||customer::text||first_day::text,0));

 select * into existing
 from public.invoices
 where company_id=cid and customer_id=customer and billing_period_start=first_day and automatic_calculation
 for update;

 if found and (existing.status<>'draft' or existing.finalized_at is not null) then return; end if;
 if existing.id is null and exists(
   select 1 from public.invoices
   where company_id=cid and customer_id=customer and billing_period_start=first_day
 ) then return; end if;

 select name into customer_name from public.customers where id=customer and company_id=cid;
 if customer_name is null then return; end if;
 select coalesce(c.tax_rate,0) into v_tax_rate from public.companies c where id=cid;

 for s in
   select st.id,coalesce(nullif(st.formal_name,''),st.name) as name,
          fs.billing_unit_price_yen,
          fs.billing_square_meter_unit_price_yen,
          fs.billing_square_meter_quantity,
          fs.billing_contract_amount_yen,
          fs.welfare_rate
   from public.sites st
   left join public.site_financial_settings fs on fs.site_id=st.id and fs.company_id=cid
   where st.company_id=cid
     and (
       (v_system_customer and st.customer_id is null)
       or (not v_system_customer and st.customer_id=customer)
     )
     and exists(
       select 1 from public.attendance_entries e
       where e.site_id=st.id and e.company_id=cid and e.work_date between first_day and last_day
     )
   order by st.id
 loop
   n:=n+1;
   lines:='[]';
   site_total:=0;

   select coalesce(sum(coalesce(e.base_man_days,0)),0)
   into attendance_man_days
   from public.attendance_entries e
   where e.company_id=cid and e.site_id=s.id and e.work_date between first_day and last_day;

   pref:=null;
   select scsp.source,tc.id as trade_company_id,
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
   where scsp.company_id=cid and scsp.site_id=s.id
     and scsp.output_type='invoice'
   limit 1;

   if pref.source='trade_company' then
     if pref.contract_method='daily' then
       rate:=pref.daily_rate_yen;
       site_total:=round(attendance_man_days*rate);
       lines:=jsonb_build_array(jsonb_build_object(
         'label','会社契約・1日単価','quantity',attendance_man_days,
         'unit_price',rate,'amount',site_total
       ));
     elsif pref.contract_method='monthly' then
       if pref.trade_company_id=any(fixed_trade_seen) then
         site_total:=0;
         lines:=jsonb_build_array(jsonb_build_object(
           'label','会社契約・月単価（他現場で計上済み）','quantity',1,
           'unit_price',0,'amount',0
         ));
       else
         fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
         site_total:=pref.monthly_rate_yen;
         lines:=jsonb_build_array(jsonb_build_object(
           'label','会社契約・月単価','quantity',1,
           'unit_price',site_total,'amount',site_total
         ));
       end if;
     elsif pref.contract_method='square_meter' then
       if pref.trade_company_id=any(fixed_trade_seen) then
         site_total:=0;
         lines:=jsonb_build_array(jsonb_build_object(
           'label','会社契約・平米（他現場で計上済み）','quantity',1,
           'unit_price',0,'amount',0
         ));
       else
         fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
         rate:=pref.square_meter_unit_price_yen;
         site_total:=round(pref.square_meter_quantity*rate);
         lines:=jsonb_build_array(jsonb_build_object(
           'label','会社契約・平米','quantity',pref.square_meter_quantity,
           'unit_price',rate,'amount',site_total
         ));
       end if;
     elsif pref.contract_method='contract' then
       if pref.trade_company_id=any(fixed_trade_seen) then
         site_total:=0;
         lines:=jsonb_build_array(jsonb_build_object(
           'label','会社契約・請負（他現場で計上済み）','quantity',1,
           'unit_price',0,'amount',0
         ));
       else
         fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
         site_total:=pref.contract_amount_yen;
         lines:=jsonb_build_array(jsonb_build_object(
           'label','会社契約・請負','quantity',1,
           'unit_price',site_total,'amount',site_total
         ));
       end if;
     else
       lines:=jsonb_build_array(jsonb_build_object(
         'label','会社契約・設定未入力','quantity',1,'unit_price',0,'amount',0
       ));
     end if;
   else
     method_count:=
       (case when coalesce(s.billing_unit_price_yen,0)>0 then 1 else 0 end)+
       (case when coalesce(s.billing_square_meter_unit_price_yen,0)>0 and coalesce(s.billing_square_meter_quantity,0)>0 then 1 else 0 end)+
       (case when coalesce(s.billing_contract_amount_yen,0)>0 then 1 else 0 end);

     if method_count=1 and coalesce(s.billing_unit_price_yen,0)>0 then
       rate:=s.billing_unit_price_yen;
       site_total:=round(attendance_man_days*rate);
       lines:=jsonb_build_array(jsonb_build_object('label','人工','quantity',attendance_man_days,'unit_price',rate,'amount',site_total));
     elsif method_count=1 and coalesce(s.billing_square_meter_unit_price_yen,0)>0 then
       rate:=s.billing_square_meter_unit_price_yen;
       site_total:=round(coalesce(s.billing_square_meter_quantity,0)*rate);
       lines:=jsonb_build_array(jsonb_build_object('label','平米','quantity',coalesce(s.billing_square_meter_quantity,0),'unit_price',rate,'amount',site_total));
     elsif method_count=1 and coalesce(s.billing_contract_amount_yen,0)>0 then
       site_total:=s.billing_contract_amount_yen;
       lines:=jsonb_build_array(jsonb_build_object('label','請負','quantity',1,'unit_price',site_total,'amount',site_total));
     else
       lines:=jsonb_build_array(jsonb_build_object('label','設定未入力','quantity',1,'unit_price',0,'amount',0));
     end if;
   end if;

   welfare:=case
     when s.welfare_rate is null or s.welfare_rate<0 or s.welfare_rate>100 then 0
     else round(site_total*s.welfare_rate/100)
   end;
   total:=total+site_total+welfare;
   welfare_total:=welfare_total+welfare;
   sites_json:=sites_json||jsonb_build_array(jsonb_build_object(
     'site_id',s.id,'site_name',s.name,'manual_adjustment',0,
     'calculation_source',coalesce(pref.source,'site'),
     'trade_company_id',pref.trade_company_id,
     'welfare_rate_bps',coalesce(s.welfare_rate,0)*100,
     'subtotal',site_total+welfare,'lines',lines
   ));
 end loop;

 if n=0 then
   if existing.id is not null and existing.status='draft' and existing.automatic_calculation then
     delete from public.invoices where id=existing.id;
   end if;
   return;
 end if;

 tax_value:=round(total*greatest(coalesce(v_tax_rate,0),0)/100);
 snapshot_value:=jsonb_build_object(
   'customer_name',customer_name,
   'customer_missing',v_system_customer,
   'billing_period',extract(year from first_day)::text||'年'||extract(month from first_day)::text||'月',
   'tax_rate_bps',greatest(coalesce(v_tax_rate,0),0)*100,
   'subtotal',total,'tax',tax_value,'grand_total',total+tax_value,'sites',sites_json
 );

 if existing.id is null then
   insert into public.invoices(
     company_id,customer_id,billing_period_start,billing_period_end,status,
     subtotal,tax,welfare_amount,grand_total,snapshot,automatic_calculation,calculation_blocked
   )
   values(cid,customer,first_day,last_day,'draft',total::int,tax_value::int,welfare_total::int,(total+tax_value)::int,snapshot_value,true,false);
 elsif existing.snapshot is distinct from snapshot_value or existing.calculation_blocked then
   update public.invoices
   set subtotal=total::int,tax=tax_value::int,welfare_amount=welfare_total::int,
       grand_total=(total+tax_value)::int,snapshot=snapshot_value,
       calculation_blocked=false,updated_at=now()
   where id=existing.id;
 end if;
end;
$function$;\n\nCREATE OR REPLACE FUNCTION private.refresh_automatic_payment_certificate(cid uuid, partner uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 first_day date:=date_trunc('month',day)::date;
 last_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
 existing public.payment_certificates%rowtype;
 settings public.partner_payment_settings%rowtype;
 attendance_count int:=0;
 gross numeric:=0;
 partner_name text;
 snapshot_value jsonb;
 s record;
 pref record;
 fixed_trade_seen uuid[]:='{}';
 source_amount numeric;
 trade_used boolean:=false;
begin
 if auth.uid() is null or partner is null then return; end if;
 perform pg_advisory_xact_lock(hashtextextended('payment-certificate:'||cid::text||partner::text||first_day::text,0));

 select * into existing
 from public.payment_certificates
 where company_id=cid and partner_company_id=partner and period_start=first_day and period_end=last_day
 for update;
 if found and (existing.status<>'draft' or not existing.automatic_calculation) then return; end if;

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

 if attendance_count=0 then
   if existing.id is not null and existing.status='draft' and existing.automatic_calculation then
     delete from public.payment_certificates where id=existing.id;
   end if;
   return;
 end if;

 for s in
   select a.site_id,
          coalesce(sum(coalesce(a.base_man_days,0)),0) as man_days,
          coalesce(sum(coalesce(a.overtime_hours,0)),0) as overtime_hours,
          coalesce(sum(coalesce(a.early_hours,0)),0) as early_hours,
          coalesce(sum(coalesce(a.night_hours,0)),0) as night_hours
   from public.attendance_entries a
   join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
   where a.company_id=cid
     and w.partner_company_id=partner
     and a.work_date between first_day and last_day
   group by a.site_id
 loop
   source_amount:=0;
   pref:=null;
   select scsp.source,tc.id as trade_company_id,
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
     and tc.partner_company_id=partner
   left join public.trade_company_contracts ct
     on ct.company_id=cid and ct.trade_company_id=tc.id
   where scsp.company_id=cid and scsp.site_id=s.site_id
     and scsp.output_type='payment_certificate'
   limit 1;

   if pref.source='trade_company' then
     trade_used:=true;
     if pref.contract_method='daily' then
       source_amount:=round(s.man_days*pref.daily_rate_yen);
     elsif pref.contract_method='monthly' then
       if not pref.trade_company_id=any(fixed_trade_seen) then
         fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
         source_amount:=pref.monthly_rate_yen;
       end if;
     elsif pref.contract_method='square_meter' then
       if not pref.trade_company_id=any(fixed_trade_seen) then
         fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
         source_amount:=round(pref.square_meter_quantity*pref.square_meter_unit_price_yen);
       end if;
     elsif pref.contract_method='contract' then
       if not pref.trade_company_id=any(fixed_trade_seen) then
         fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
         source_amount:=pref.contract_amount_yen;
       end if;
     end if;
   else
     source_amount:=
       coalesce(s.man_days,0)*coalesce(settings.daily_rate_yen,0)
       +coalesce(s.overtime_hours,0)*coalesce(settings.overtime_hour_rate_yen,0)
       +coalesce(s.early_hours,0)*coalesce(settings.early_hour_rate_yen,0)
       +coalesce(s.night_hours,0)*coalesce(settings.night_hour_rate_yen,0);
   end if;
   gross:=gross+source_amount;
 end loop;

 snapshot_value:=jsonb_build_object(
   'partner_company_name',coalesce(partner_name,''),
   'period_start',first_day,'period_end',last_day,
   'attendance_count',attendance_count,
   'trade_company_contract_used',trade_used,
   'settings_missing',settings.partner_company_id is null and not trade_used
 );

 if existing.id is null then
   insert into public.payment_certificates(
     company_id,partner_company_id,period_start,period_end,status,
     gross_amount,deductions,net_amount,snapshot,automatic_calculation,calculation_blocked
   )
   values(cid,partner,first_day,last_day,'draft',gross::int,0,gross::int,snapshot_value,true,false);
 elsif existing.gross_amount is distinct from gross::int
    or existing.net_amount is distinct from gross::int
    or existing.snapshot is distinct from snapshot_value
    or existing.calculation_blocked then
   update public.payment_certificates
   set gross_amount=gross::int,deductions=0,net_amount=gross::int,
       snapshot=snapshot_value,calculation_blocked=false,revision=revision+1,updated_at=now()
   where id=existing.id;
 end if;
end;
$function$;\n\nCREATE OR REPLACE FUNCTION private.refresh_automatic_payroll(cid uuid, wid uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  start_day date:=date_trunc('month',day)::date;
  end_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
  settings jsonb; a record; current_statement public.payroll_statements%rowtype;
  total numeric:=0; v_deductions numeric:=0; count_rows int:=0;
  category text; allowance text; allowance_index int; seen text[]:='{}'; token text;
  line_detail jsonb; fingerprint text; saved_id uuid; saved_revision int;
  pref record;
  fixed_trade_seen uuid[]:='{}';
  trade_amount numeric;
begin
  if auth.uid() is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(cid::text||wid::text||start_day::text,0));
  select * into current_statement
  from public.payroll_statements
  where company_id=cid and worker_id=wid and period_start=start_day and period_end=end_day
  for update;
  if found and (not current_statement.automatic_calculation or current_statement.workflow_state<>'draft') then return; end if;

  select to_jsonb(s) into settings
  from public.worker_payroll_settings s
  where s.company_id=cid and s.worker_id=wid;

  select md5(
    coalesce((settings-'updated_at')::text,'')||
    coalesce((
      select jsonb_agg(to_jsonb(ae)-'updated_at'-'created_at' order by ae.work_date,ae.id)::text
      from public.attendance_entries ae
      where ae.company_id=cid and ae.worker_id=wid
        and ae.work_date between start_day and end_day
        and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    ),'')||
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'site_id',scsp.site_id,'source',scsp.source,
          'trade_company_id',scsp.trade_company_id,
          'contract',to_jsonb(ct)-'updated_at'
        )
        order by scsp.site_id
      )::text
      from public.site_calculation_source_preferences scsp
      left join public.trade_company_contracts ct
        on ct.company_id=scsp.company_id and ct.trade_company_id=scsp.trade_company_id
      where scsp.company_id=cid and scsp.output_type='payroll'
    ),'')
  )
  into fingerprint;

  for a in
    select ae.*
    from public.attendance_entries ae
    where ae.company_id=cid and ae.worker_id=wid
      and ae.work_date between start_day and end_day
      and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    order by ae.work_date,ae.id
  loop
    count_rows:=count_rows+1;
    trade_amount:=0;
    pref:=null;

    select scsp.source,tc.id as trade_company_id,
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
    where scsp.company_id=cid and scsp.site_id=a.site_id
      and scsp.output_type='payroll'
    limit 1;

    if pref.source='trade_company' then
      if pref.contract_method='daily' then
        trade_amount:=round(coalesce(a.base_man_days,0)*pref.daily_rate_yen);
      elsif pref.contract_method='monthly' then
        if not pref.trade_company_id=any(fixed_trade_seen) then
          fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
          trade_amount:=pref.monthly_rate_yen;
        end if;
      elsif pref.contract_method='square_meter' then
        if not pref.trade_company_id=any(fixed_trade_seen) then
          fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
          trade_amount:=round(pref.square_meter_quantity*pref.square_meter_unit_price_yen);
        end if;
      elsif pref.contract_method='contract' then
        if not pref.trade_company_id=any(fixed_trade_seen) then
          fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
          trade_amount:=pref.contract_amount_yen;
        end if;
      end if;
      total:=total+trade_amount;
    else
      category:=a.work_category;
      total:=total
        + round(coalesce(a.base_man_days,0) * coalesce((settings->>(category||'_daily'))::numeric,0))
        + round(coalesce(a.overtime_hours,0) * coalesce((settings->>(category||'_overtime'))::numeric,0))
        + round(coalesce(a.early_hours,0) * coalesce((settings->>(category||'_early'))::numeric,0));
    end if;

    foreach allowance in array coalesce(a.allowance_names,'{}'::text[]) loop
      token:=a.work_date::text||':'||allowance;
      if token=any(seen) then continue; end if;
      seen:=array_append(seen,token);
      allowance_index:=null;
      if settings is not null then
        select min(i) into allowance_index
        from generate_series(1,3)i
        where nullif(trim(settings->>('allowance_name_'||i)),'')=allowance;
      end if;
      if allowance_index is not null then
        total:=total+round(coalesce((settings->>('allowance_'||allowance_index))::numeric,0));
      end if;
    end loop;
  end loop;

  if count_rows=0 then
    if current_statement.id is not null and current_statement.workflow_state='draft' and current_statement.automatic_calculation then
      delete from public.payroll_statements where id=current_statement.id;
    end if;
    return;
  end if;

  if settings is not null then
    total:=total+round(coalesce((settings->>'family_monthly')::numeric,0))
      +round(coalesce((settings->>'transport_monthly')::numeric,0));
    v_deductions:=round(coalesce((settings->>'income_tax_monthly')::numeric,0))
      +round(coalesce((settings->>'resident_tax_monthly')::numeric,0))
      +round(coalesce((settings->>'social_insurance_monthly')::numeric,0))
      +round(coalesce((settings->>'other_deduction_monthly')::numeric,0));
  end if;

  total:=greatest(coalesce(total,0),0);
  v_deductions:=greatest(coalesce(v_deductions,0),0);
  line_detail:=jsonb_build_object(
    '出勤に基づく支給額',greatest(total-v_deductions,0),
    '計算元選択あり',exists(
      select 1 from public.site_calculation_source_preferences scsp
      where scsp.company_id=cid and scsp.output_type='payroll'
        and scsp.source='trade_company'
        and exists(
          select 1 from public.attendance_entries ae
          where ae.company_id=cid and ae.worker_id=wid
            and ae.site_id=scsp.site_id
            and ae.work_date between start_day and end_day
        )
    )
  );

  if current_statement.id is null then
    insert into public.payroll_statements(
      company_id,worker_id,period_start,period_end,gross_pay,deductions,net_pay,
      detail,workflow_state,approver_ids,automatic_calculation,calculation_blocked,calculation_fingerprint
    )
    values(
      cid,wid,start_day,end_day,total::int,v_deductions::int,greatest(total-v_deductions,0)::int,
      line_detail,'draft',private.payroll_approver_ids(cid),true,false,fingerprint
    )
    returning id,revision into saved_id,saved_revision;
  elsif current_statement.gross_pay is distinct from total::int
      or current_statement.deductions is distinct from v_deductions::int
      or current_statement.net_pay is distinct from greatest(total-v_deductions,0)::int
      or current_statement.detail is distinct from line_detail
      or current_statement.calculation_fingerprint is distinct from fingerprint
      or current_statement.calculation_blocked then
    update public.payroll_statements
    set gross_pay=total::int,
        deductions=v_deductions::int,
        net_pay=greatest(total-v_deductions,0)::int,
        detail=line_detail,
        calculation_fingerprint=fingerprint,
        calculation_blocked=false,
        approved_ids='{}',
        revision=revision+1,
        updated_at=now()
    where id=current_statement.id
    returning id,revision into saved_id,saved_revision;
  end if;

  if saved_id is not null then
    insert into public.payroll_audit(company_id,statement_id,revision,action,actor_id)
    values(cid,saved_id,saved_revision,'automatic_recalculation',auth.uid());
  end if;
end;
$function$;\n\nCREATE OR REPLACE FUNCTION private.select_site_calculation_source(p_site_id uuid, p_output_type text, p_trade_company_id uuid, p_source text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cid uuid;
  v_customer uuid;
  v_day date;
  r record;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  if p_output_type not in ('invoice','payment_certificate','payroll') then
    raise exception '計算対象を確認してください。';
  end if;
  if p_source not in ('site','trade_company') then
    raise exception '計算元を選択してください。';
  end if;
  if not exists(select 1 from public.sites s where s.id=p_site_id and s.company_id=cid) then
    raise exception '現場が見つかりません。';
  end if;
  if p_source='trade_company' and not exists(
    select 1 from public.trade_companies tc
    where tc.id=p_trade_company_id and tc.company_id=cid
  ) then
    raise exception '取引会社が見つかりません。';
  end if;

  insert into public.site_calculation_source_preferences(
    company_id,site_id,output_type,trade_company_id,source,selected_by,selected_at
  )
  values(cid,p_site_id,p_output_type,p_trade_company_id,p_source,auth.uid(),now())
  on conflict(company_id,site_id,output_type) do update
  set trade_company_id=excluded.trade_company_id,
      source=excluded.source,
      selected_by=auth.uid(),
      selected_at=now();

  select s.customer_id into v_customer
  from public.sites s
  where s.id=p_site_id and s.company_id=cid;

  for r in
    select distinct ae.work_date
    from public.attendance_entries ae
    where ae.company_id=cid and ae.site_id=p_site_id
  loop
    v_day:=r.work_date;
    if p_output_type='invoice' then
      perform private.refresh_automatic_invoice(cid,v_customer,v_day);
    elsif p_output_type='payment_certificate' then
      for r in
        select distinct w.partner_company_id as partner_id
        from public.attendance_entries ae
        join public.workers w on w.id=ae.worker_id and w.company_id=ae.company_id
        where ae.company_id=cid and ae.site_id=p_site_id
          and w.partner_company_id is not null
          and date_trunc('month',ae.work_date)=date_trunc('month',v_day)
      loop
        perform private.refresh_automatic_payment_certificate(cid,r.partner_id,v_day);
      end loop;
    elsif p_output_type='payroll' then
      for r in
        select distinct ae.worker_id
        from public.attendance_entries ae
        where ae.company_id=cid and ae.site_id=p_site_id
          and date_trunc('month',ae.work_date)=date_trunc('month',v_day)
      loop
        perform private.refresh_automatic_payroll(cid,r.worker_id,v_day);
      end loop;
    end if;
  end loop;
end
$function$;\n\nrevoke all on function private.select_site_calculation_source(uuid,text,uuid,text)
from public,anon,authenticated;
