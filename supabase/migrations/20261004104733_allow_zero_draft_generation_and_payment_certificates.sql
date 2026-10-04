-- Mirrors production migration 20261004104733.
-- Any attendance row creates draft output even when financial settings are missing.
-- Missing settings calculate as zero and are surfaced separately as attention items.

create table if not exists public.partner_payment_settings (
  company_id uuid not null references public.companies(id) on delete cascade,
  partner_company_id uuid not null references public.partner_companies(id) on delete cascade,
  daily_rate_yen integer not null default 0 check (daily_rate_yen >= 0),
  overtime_hour_rate_yen integer not null default 0 check (overtime_hour_rate_yen >= 0),
  early_hour_rate_yen integer not null default 0 check (early_hour_rate_yen >= 0),
  night_hour_rate_yen integer not null default 0 check (night_hour_rate_yen >= 0),
  updated_at timestamptz not null default now(),
  primary key (company_id, partner_company_id)
);

alter table public.partner_payment_settings enable row level security;

drop policy if exists partner_payment_settings_management_select on public.partner_payment_settings;
create policy partner_payment_settings_management_select
on public.partner_payment_settings for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = partner_payment_settings.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
);

drop policy if exists partner_payment_settings_management_write on public.partner_payment_settings;
create policy partner_payment_settings_management_write
on public.partner_payment_settings for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = partner_payment_settings.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = partner_payment_settings.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

create table if not exists public.payment_certificates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  partner_company_id uuid not null references public.partner_companies(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','finalized')),
  gross_amount integer not null default 0,
  deductions integer not null default 0,
  net_amount integer not null default 0,
  snapshot jsonb not null default '{}'::jsonb,
  automatic_calculation boolean not null default true,
  calculation_blocked boolean not null default false,
  revision integer not null default 1,
  finalized_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, partner_company_id, period_start, period_end)
);

alter table public.payment_certificates enable row level security;

drop policy if exists payment_certificates_management_select on public.payment_certificates;
create policy payment_certificates_management_select
on public.payment_certificates for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = payment_certificates.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
);

drop policy if exists payment_certificates_management_write on public.payment_certificates;
create policy payment_certificates_management_write
on public.payment_certificates for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = payment_certificates.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = payment_certificates.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

create or replace function private.refresh_automatic_payroll(cid uuid, wid uuid, day date)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  start_day date:=date_trunc('month',day)::date;
  end_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
  settings jsonb; a record; current_statement public.payroll_statements%rowtype;
  total numeric:=0; v_deductions numeric:=0; count_rows int:=0;
  category text; allowance text; allowance_index int; seen text[]:='{}'; token text;
  line_detail jsonb; fingerprint text; saved_id uuid; saved_revision int;
begin
  if auth.uid() is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(cid::text||wid::text||start_day::text,0));

  select * into current_statement
  from public.payroll_statements
  where company_id=cid and worker_id=wid and period_start=start_day and period_end=end_day
  for update;

  if found and (not current_statement.automatic_calculation or current_statement.workflow_state<>'draft') then
    return;
  end if;

  select to_jsonb(s) into settings
  from public.worker_payroll_settings s
  where s.company_id=cid and s.worker_id=wid;

  select md5(
    coalesce((settings-'updated_at')::text,'')||
    coalesce(jsonb_agg(to_jsonb(ae)-'updated_at'-'created_at' order by ae.work_date,ae.id)::text,'')
  )
  into fingerprint
  from public.attendance_entries ae
  where ae.company_id=cid and ae.worker_id=wid
    and ae.work_date between start_day and end_day
    and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date;

  for a in
    select ae.*
    from public.attendance_entries ae
    where ae.company_id=cid and ae.worker_id=wid
      and ae.work_date between start_day and end_day
      and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    order by ae.work_date,ae.id
  loop
    count_rows:=count_rows+1;
    category:=a.work_category;
    total:=total
      + round(coalesce(a.base_man_days,0) * coalesce((settings->>(category||'_daily'))::numeric,0))
      + round(coalesce(a.overtime_hours,0) * coalesce((settings->>(category||'_overtime'))::numeric,0))
      + round(coalesce(a.early_hours,0) * coalesce((settings->>(category||'_early'))::numeric,0));

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
  line_detail:=jsonb_build_object('出勤に基づく支給額',greatest(total-v_deductions,0));

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
begin
 if auth.uid() is null or customer is null then return; end if;
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
   where st.company_id=cid and st.customer_id=customer
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

create or replace function private.refresh_automatic_payment_certificate(cid uuid, partner uuid, day date)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
 first_day date:=date_trunc('month',day)::date;
 last_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
 existing public.payment_certificates%rowtype;
 settings public.partner_payment_settings%rowtype;
 attendance_count int:=0;
 gross numeric:=0;
 partner_name text;
 snapshot_value jsonb;
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

 select count(*),
        coalesce(sum(
          coalesce(a.base_man_days,0)*coalesce(settings.daily_rate_yen,0)
          +coalesce(a.overtime_hours,0)*coalesce(settings.overtime_hour_rate_yen,0)
          +coalesce(a.early_hours,0)*coalesce(settings.early_hour_rate_yen,0)
          +coalesce(a.night_hours,0)*coalesce(settings.night_hour_rate_yen,0)
        ),0)
 into attendance_count,gross
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

 snapshot_value:=jsonb_build_object(
   'partner_company_name',coalesce(partner_name,''),
   'period_start',first_day,
   'period_end',last_day,
   'attendance_count',attendance_count,
   'settings_missing',settings.partner_company_id is null
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
$function$;

create or replace function private.attendance_refresh_payment_certificate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare partner uuid;
begin
 if tg_op<>'INSERT' then
   select w.partner_company_id into partner
   from public.workers w where w.id=old.worker_id and w.company_id=old.company_id;
   if partner is not null then
     perform private.refresh_automatic_payment_certificate(old.company_id,partner,old.work_date);
   end if;
 end if;

 if tg_op<>'DELETE' then
   select w.partner_company_id into partner
   from public.workers w where w.id=new.worker_id and w.company_id=new.company_id;
   if partner is not null then
     perform private.refresh_automatic_payment_certificate(new.company_id,partner,new.work_date);
   end if;
 end if;

 return null;
end;
$function$;

drop trigger if exists attendance_refresh_payment_certificate_trigger on public.attendance_entries;
create trigger attendance_refresh_payment_certificate_trigger
after insert or update or delete on public.attendance_entries
for each row execute function private.attendance_refresh_payment_certificate();

create or replace function private.partner_payment_settings_refresh_certificate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare m date;
begin
 for m in
   select distinct date_trunc('month',a.work_date)::date
   from public.attendance_entries a
   join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
   where a.company_id=new.company_id and w.partner_company_id=new.partner_company_id
   order by 1
 loop
   perform private.refresh_automatic_payment_certificate(new.company_id,new.partner_company_id,m);
 end loop;

 return null;
end;
$function$;

drop trigger if exists partner_payment_settings_refresh_certificate_trigger on public.partner_payment_settings;
create trigger partner_payment_settings_refresh_certificate_trigger
after insert or update on public.partner_payment_settings
for each row execute function private.partner_payment_settings_refresh_certificate();

create or replace function public.current_generation_setting_attention()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
 uid uuid:=auth.uid();
 cid uuid;
 role_text text;
 issues jsonb:='[]'::jsonb;
 r record;
begin
 if uid is null then return jsonb_build_object('count',0,'issues','[]'::jsonb); end if;

 select cm.company_id,cm.role::text into cid,role_text
 from public.company_members cm where cm.user_id=uid limit 1;

 if cid is null or role_text not in ('owner','admin','manager') then
   return jsonb_build_object('count',0,'issues','[]'::jsonb);
 end if;

 for r in
   select distinct w.id,w.name
   from public.attendance_entries a
   join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
   left join public.worker_payroll_settings ps on ps.company_id=a.company_id and ps.worker_id=a.worker_id
   where a.company_id=cid
     and a.work_date>=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date
     and ps.worker_id is null
   order by w.name
 loop
   issues:=issues||jsonb_build_array(jsonb_build_object(
     'type','payroll','key','payroll:'||r.id::text,
     'message',r.name||'：個別給与設定が未入力です'
   ));
 end loop;

 for r in
   select distinct s.id,s.name
   from public.attendance_entries a
   join public.sites s on s.id=a.site_id and s.company_id=a.company_id
   left join public.site_financial_settings fs on fs.site_id=s.id and fs.company_id=s.company_id
   where a.company_id=cid
     and a.work_date>=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date
     and (
       fs.site_id is null or
       ((case when coalesce(fs.billing_unit_price_yen,0)>0 then 1 else 0 end)
        +(case when coalesce(fs.billing_square_meter_unit_price_yen,0)>0 and coalesce(fs.billing_square_meter_quantity,0)>0 then 1 else 0 end)
        +(case when coalesce(fs.billing_contract_amount_yen,0)>0 then 1 else 0 end))<>1
     )
   order by s.name
 loop
   issues:=issues||jsonb_build_array(jsonb_build_object(
     'type','invoice','key','invoice-site:'||r.id::text,
     'message',r.name||'：請求方式が未入力です'
   ));
 end loop;

 for r in
   select distinct pc.id,pc.name
   from public.attendance_entries a
   join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
   join public.partner_companies pc on pc.id=w.partner_company_id and pc.company_id=w.company_id
   left join public.partner_payment_settings pps on pps.company_id=pc.company_id and pps.partner_company_id=pc.id
   where a.company_id=cid
     and a.work_date>=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date
     and pps.partner_company_id is null
   order by pc.name
 loop
   issues:=issues||jsonb_build_array(jsonb_build_object(
     'type','payment_certificate','key','payment:'||r.id::text,
     'message',r.name||'：支払証明書設定が未入力です'
   ));
 end loop;

 if exists(
   select 1 from public.attendance_entries a
   where a.company_id=cid
     and a.work_date>=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date
 ) and exists(
   select 1 from public.companies c
   where c.id=cid and (
     nullif(trim(coalesce(c.bank_name,'')),'') is null
     or nullif(trim(coalesce(c.bank_branch,'')),'') is null
     or nullif(trim(coalesce(c.bank_account_number,'')),'') is null
     or nullif(trim(coalesce(c.bank_account_holder,'')),'') is null
   )
 ) then
   issues:=issues||jsonb_build_array(jsonb_build_object(
     'type','invoice','key','invoice-bank:'||cid::text,
     'message','請求書設定：振込口座が未入力です'
   ));
 end if;

 return jsonb_build_object('count',jsonb_array_length(issues),'issues',issues);
end;
$function$;

revoke execute on function public.current_generation_setting_attention() from public, anon;
grant execute on function public.current_generation_setting_attention() to authenticated;
