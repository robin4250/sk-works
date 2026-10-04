-- Settings are allowed to be missing: attendance still produces an invoice draft.
-- When a site's customer is unset, use an internal placeholder customer so the
-- zero-value draft exists and the missing customer is surfaced as an attention item.

create or replace function private.ensure_unassigned_invoice_customer(cid uuid)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare v_id uuid;
begin
  select c.id into v_id
  from public.customers c
  where c.company_id=cid
    and c.notes='sko_system_unassigned_invoice_customer'
  order by c.created_at
  limit 1;

  if v_id is null then
    insert into public.customers(company_id,name,billing_name,notes)
    values(cid,'取引先未設定（自動下書き）','取引先未設定','sko_system_unassigned_invoice_customer')
    returning id into v_id;
  end if;
  return v_id;
end;
$function$;

create or replace function private.refresh_automatic_invoice(cid uuid, customer uuid, day date)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
 first_day date:=date_trunc('month',day)::date;
 last_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
 existing public.invoices%rowtype; s record; sites_json jsonb:='[]'; lines jsonb;
 n int:=0; site_total numeric; total numeric:=0; welfare_total numeric:=0; welfare numeric; v_tax_rate numeric; tax_value numeric;
 attendance_man_days numeric; customer_name text; snapshot_value jsonb; method_count int; rate numeric;
 v_system_customer boolean:=false;
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

   welfare:=case
     when s.welfare_rate is null or s.welfare_rate<0 or s.welfare_rate>100 then 0
     else round(site_total*s.welfare_rate/100)
   end;

   total:=total+site_total+welfare;
   welfare_total:=welfare_total+welfare;
   sites_json:=sites_json||jsonb_build_array(jsonb_build_object(
     'site_id',s.id,'site_name',s.name,'manual_adjustment',0,
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
$function$;

create or replace function private.refresh_generation_setting_issues(cid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  month_start date:=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date;
  active_keys text[]:='{}';
  r record;
  k text;
begin
  if cid is null then return; end if;

  for r in
    select distinct w.id,w.name
    from public.attendance_entries a
    join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
    left join public.worker_payroll_settings ps on ps.company_id=a.company_id and ps.worker_id=a.worker_id
    where a.company_id=cid and a.work_date>=month_start and ps.worker_id is null
    order by w.name
  loop
    k:='payroll:'||r.id::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(cid,k,'payroll','給与明細の設定未入力',r.name||'：個別給与設定が未入力です','payroll_settings',r.id);
  end loop;

  for r in
    select distinct s.id,s.name
    from public.attendance_entries a
    join public.sites s on s.id=a.site_id and s.company_id=a.company_id
    where a.company_id=cid and a.work_date>=month_start and s.customer_id is null
    order by s.name
  loop
    k:='invoice-customer:'||r.id::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(cid,k,'invoice','請求書の設定未入力',r.name||'：取引先が未入力です','admin_sites',r.id);
  end loop;

  for r in
    select distinct s.id,s.name
    from public.attendance_entries a
    join public.sites s on s.id=a.site_id and s.company_id=a.company_id
    left join public.site_financial_settings fs on fs.site_id=s.id and fs.company_id=s.company_id
    where a.company_id=cid and a.work_date>=month_start
      and (
        fs.site_id is null or
        ((case when coalesce(fs.billing_unit_price_yen,0)>0 then 1 else 0 end)
         +(case when coalesce(fs.billing_square_meter_unit_price_yen,0)>0 and coalesce(fs.billing_square_meter_quantity,0)>0 then 1 else 0 end)
         +(case when coalesce(fs.billing_contract_amount_yen,0)>0 then 1 else 0 end))<>1
      )
    order by s.name
  loop
    k:='invoice-site:'||r.id::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(cid,k,'invoice','請求書の設定未入力',r.name||'：請求方式が未入力です','admin_sites',r.id);
  end loop;

  if exists(
    select 1 from public.attendance_entries a
    where a.company_id=cid and a.work_date>=month_start
  ) and exists(
    select 1 from public.companies c
    where c.id=cid and (
      nullif(trim(coalesce(c.bank_name,'')),'') is null
      or nullif(trim(coalesce(c.bank_branch,'')),'') is null
      or nullif(trim(coalesce(c.bank_account_number,'')),'') is null
      or nullif(trim(coalesce(c.bank_account_holder,'')),'') is null
    )
  ) then
    k:='invoice-bank:'||cid::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(cid,k,'invoice','請求書の設定未入力','請求書設定：振込口座が未入力です','settings',cid);
  end if;

  for r in
    select distinct pc.id,pc.name
    from public.attendance_entries a
    join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
    join public.partner_companies pc on pc.id=w.partner_company_id and pc.company_id=w.company_id
    left join public.partner_payment_settings pps on pps.company_id=pc.company_id and pps.partner_company_id=pc.id
    where a.company_id=cid and a.work_date>=month_start and pps.partner_company_id is null
    order by pc.name
  loop
    k:='payment:'||r.id::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(cid,k,'payment_certificate','支払証明書の設定未入力',r.name||'：支払証明書設定が未入力です','payment_certificate_settings',r.id);
  end loop;

  update public.generation_setting_issues
  set resolved_at=now(),updated_at=now()
  where company_id=cid
    and resolved_at is null
    and not (issue_key=any(active_keys));
end;
$function$;
