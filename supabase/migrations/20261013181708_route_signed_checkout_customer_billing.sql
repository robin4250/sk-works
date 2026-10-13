-- CLI-generated. Signed checkout confirms route billing; payroll and source evidence remain unchanged.
begin;
do $guard$ begin
 if (select md5(prosrc) from pg_proc where oid='private.refresh_automatic_invoice(uuid,uuid,date)'::regprocedure) not in ('b3d4c999d7847162f8dcaed5735077c1','9173c4e7237b764ecb4c1e79bad85005') then raise exception 'Current refresh_automatic_invoice differs; inspect before applying';end if;
 if (select md5(prosrc) from pg_proc where oid='private.pending_route_billing_quantity_rows()'::regprocedure) not in ('df9231b2f00cb5db7af408df5c6bc9ae','a714fef775fcf9b85d811afa3dc22dec') then raise exception 'Current pending_route_billing_quantity_rows differs; inspect before applying';end if;
 if (select md5(prosrc) from pg_proc where oid='private.route_billing_invoice_blocked(uuid,uuid,date,date)'::regprocedure) not in ('dc3c2feb9e704414052238608676b147','2601bbc4fe21fa0a609c52686e315ee7') then raise exception 'Current route_billing_invoice_blocked differs; inspect before applying';end if;
 if (select md5(prosrc) from pg_proc where oid='private.route_billing_invoice_components(uuid,uuid,date,date)'::regprocedure) not in ('48e9d427777c409724a36125d315914b','115ebedbcc5e02c7adef762829b77cee') then raise exception 'Current route_billing_invoice_components differs; inspect before applying';end if;
end $guard$;

create index if not exists route_signed_checkout_entry_report_idx on public.attendance_entries(source_report_id,worker_id) where route_assignment_id is not null;
create index if not exists route_signed_checkout_attendance_report_idx on public.attendance_verifications(daily_report_id,worker_id,work_date) where route_assignment_id is not null;

-- Internal read-only partition. Only a signed checkout report is a billing source.
-- Intermediate visit signatures cannot establish a checkout or an extra man-day.
create or replace function private.route_signed_checkout_sources(
  p_company uuid, p_first date, p_last date
) returns table(
  report_id uuid, worker_id uuid, work_date date, customer_id uuid,
  source_clock_in_id uuid, source_quantity numeric, quantity numeric,
  site_ids uuid[], site_names text[], visit_ids uuid[], visit_started_ats timestamptz[], visit_count bigint,
  work_category text, overtime_hours numeric, early_hours numeric,
  allowance_names text[], source_ready boolean, source_issue text
)
language sql stable security definer set search_path='' as $$
  with signed_entries as (
    select e.*, d.id checkout_report_id, d.route_assignment_id checkout_route,
      d.report_date checkout_date,
      count(*) over(partition by d.id,e.worker_id) entry_count
    from public.daily_reports d
    join public.attendance_entries e on e.source_report_id=d.id
      and e.company_id=d.company_id and e.route_assignment_id=d.route_assignment_id
      and e.work_date=d.report_date and e.site_id is null
    where d.company_id=p_company and d.route_assignment_id is not null
      and d.site_id is null and d.status='signed' and d.signed_at is not null
      and d.signature_json is not null and d.signature_json <> '[]'::jsonb
      and d.report_date between p_first and p_last
      and exists(select 1 from public.daily_report_workers rw
        where rw.report_id=d.id and rw.worker_id=e.worker_id)
  ), sources as (
    select e.*, s.id start_id, s.confirmed_at start_at, o.confirmed_at end_at,
      (select count(*) from public.attendance_verifications a
        where a.daily_report_id=e.checkout_report_id and a.worker_id=e.worker_id
          and a.company_id=p_company and a.route_assignment_id=e.checkout_route
          and a.work_date=e.checkout_date and a.event_type='clock_in') start_count,
      (select count(*) from public.attendance_verifications a
        where a.source_clock_in_id=s.id and a.event_type='clock_out') end_count
    from signed_entries e
    join public.attendance_verifications s on s.daily_report_id=e.checkout_report_id
      and s.company_id=e.company_id and s.worker_id=e.worker_id
      and s.route_assignment_id=e.checkout_route and s.site_id is null
      and s.work_date=e.checkout_date and s.event_type='clock_in'
    join public.attendance_verifications o on o.source_clock_in_id=s.id
      and o.company_id=s.company_id and o.worker_id=s.worker_id
      and o.route_assignment_id=s.route_assignment_id and o.site_id is null
      and o.work_date=s.work_date and o.daily_report_id=e.checkout_report_id
      and o.event_type='clock_out' and o.confirmed_at>=s.confirmed_at
  ), visits as (
    select e.*, c.id visit_id, c.recorded_at visited_at,
      st.id actual_site_id, st.customer_id actual_customer_id,
      coalesce(nullif(st.formal_name,''),st.name) actual_site_name,
      ec.id finish_capture_id, ec.recorded_at finished_at,
      ec.company_id end_company, ec.source_clock_in_id end_source,
      ec.route_assignment_id end_route, ec.route_stop_id end_stop,
      ec.worker_id end_worker, c.route_stop_id start_stop,
      ec.work_date end_work_date,
      count(*) over(partition by e.checkout_report_id,e.worker_id,c.id) visit_duplicates
    from sources e
    join private.route_journey_visit_events v on v.source_clock_in_id=e.start_id
      and v.kind='start' and v.capture_id=v.start_capture_id
    join private.route_journey_captures c on c.id=v.capture_id
      and c.company_id=e.company_id and c.source_clock_in_id=e.start_id
      and c.route_assignment_id=e.checkout_route and c.work_date=e.checkout_date
      and c.worker_id=e.worker_id
      and c.route_stop_id=v.route_stop_id
    left join private.route_journey_visit_events ve on ve.start_capture_id=c.id
      and ve.kind='end' and ve.source_clock_in_id=e.start_id
      and ve.route_stop_id=c.route_stop_id
    left join private.route_journey_captures ec on ec.id=ve.capture_id
    left join public.route_stops stop on stop.id=c.route_stop_id
      and stop.route_assignment_id=e.checkout_route
    left join public.sites st on st.id=stop.site_id and st.company_id=e.company_id
  ), partitioned as (
    select checkout_report_id, worker_id, checkout_date, actual_customer_id,
      start_id, min(base_man_days) source_quantity,
      array_agg(actual_site_id order by visited_at,visit_id) site_ids,
      array_agg(actual_site_name order by visited_at,visit_id) site_names,
      array_agg(visit_id order by visited_at,visit_id) visit_ids,
      array_agg(visited_at order by visited_at,visit_id) visit_started_ats,
      count(*) visit_count, min(coalesce(work_category,'day')) work_category,
      min(coalesce(overtime_hours,0)) overtime_hours,
      min(coalesce(early_hours,0)) early_hours,
      allowance_names,
      bool_and(entry_count=1 and start_count=1 and end_count=1
        and base_man_days>0 and actual_site_id is not null
        and actual_customer_id is not null and actual_site_name is not null
        and finish_capture_id is not null and visit_duplicates=1
        and end_company=p_company and end_source=start_id
        and end_route=checkout_route and end_work_date=checkout_date
        and end_stop=start_stop and end_worker=worker_id
        and finished_at>=visited_at and visited_at>=start_at and finished_at<=end_at)
        source_ready
    from visits
    group by checkout_report_id,worker_id,checkout_date,actual_customer_id,start_id,allowance_names
  )
  select checkout_report_id,worker_id,checkout_date,actual_customer_id,start_id,
    source_quantity,
    -- Explicit user contract: one man-day per worker/day/customer, not per visit.
    1::numeric,
    site_ids,site_names,visit_ids,visit_started_ats,visit_count,work_category,overtime_hours,early_hours,
    coalesce(allowance_names,'{}'::text[]),coalesce(source_ready,false),
    case when coalesce(source_ready,false) then null else 'checkout_visit_source_unconfirmed' end
  from partitioned
$$;
revoke all on function private.route_signed_checkout_sources(uuid,date,date)
  from public, anon, authenticated;


create or replace function private.route_signed_site_rates(
 p_company uuid,p_site uuid,p_category text
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare f public.site_financial_settings%rowtype; pref record;
 base_rate numeric; overrides jsonb; formula jsonb; category_kind text;
 day_rate numeric; overtime_rate numeric; early_rate numeric; daily boolean;
begin
 select * into f from public.site_financial_settings
 where company_id=p_company and site_id=p_site;
 select c.contract_method,c.daily_rate_yen into pref
 from public.site_calculation_source_preferences p
 join public.trade_companies t on t.id=p.trade_company_id and t.company_id=p_company
 left join public.trade_company_contracts c on c.company_id=p_company and c.trade_company_id=t.id
 where p.company_id=p_company and p.site_id=p_site and p.output_type='invoice'
 and p.source='trade_company' limit 1;
 if found then
  daily:=pref.contract_method='daily';base_rate:=pref.daily_rate_yen;
 else
  base_rate:=f.billing_unit_price_yen;
  select coalesce(r.man_day_method,false) into daily
  from private.route_billing_site_daily_rate(p_company,p_site) r;
 end if;
 formula:=coalesce(f.billing_rate_formula,'{}');
 overrides:=coalesce(f.billing_rate_overrides,'{}');
 if coalesce((overrides->>'overtime')::numeric,0)<=0 and f.billing_overtime_hour_rate_yen>0 then
  overrides:=jsonb_set(overrides,'{overtime}',to_jsonb(f.billing_overtime_hour_rate_yen),true);
 end if;
 if coalesce((overrides->>'early')::numeric,0)<=0 and f.billing_early_hour_rate_yen>0 then
  overrides:=jsonb_set(overrides,'{early}',to_jsonb(f.billing_early_hour_rate_yen),true);
 end if;
 category_kind:=case p_category when 'night' then 'night' when 'holiday' then 'holiday'
  when 'holiday_night' then 'holiday_night' else 'daily' end;
 day_rate:=private.resolve_rate_formula(coalesce(base_rate,0),formula,overrides,category_kind);
 overtime_rate:=private.resolve_rate_formula(coalesce(base_rate,0),formula,overrides,
  case p_category when 'night' then 'night_overtime' when 'holiday' then 'holiday_overtime'
  when 'holiday_night' then 'holiday_night_overtime' else 'overtime' end);
 early_rate:=case when coalesce((overrides->>'early')::numeric,0)>0 then round((overrides->>'early')::numeric)
  when coalesce(p_category,'day')='day' then private.resolve_rate_formula(coalesce(base_rate,0),formula,overrides,'early')
  else round(day_rate/greatest(coalesce((formula->>'hours_per_day')::numeric,8),0.01)
    *coalesce((formula->>'early_multiplier')::numeric,1.25)) end;
 return jsonb_build_object('daily',coalesce(daily,false),'unit_price_yen',day_rate,
  'overtime_rate',overtime_rate,'early_rate',early_rate,
  'welfare_rate',case when f.welfare_rate between 0 and 100 then f.welfare_rate else 0 end,
  'allowance_rates',coalesce((select jsonb_object_agg(name,amount) from (
   select distinct on(name) name,amount from (values
    (nullif(trim(f.billing_allowance_1_name),''),coalesce(f.billing_allowance_1_amount_yen,0),1),
    (nullif(trim(f.billing_allowance_2_name),''),coalesce(f.billing_allowance_2_amount_yen,0),2),
    (nullif(trim(f.billing_allowance_3_name),''),coalesce(f.billing_allowance_3_amount_yen,0),3)) v(name,amount,priority)
    where name is not null order by name,priority) a),'{}'));
end $$;
revoke all on function private.route_signed_site_rates(uuid,uuid,text) from public,anon,authenticated;


create or replace function private.route_signed_checkout_components(
 cid uuid,customer uuid,first_day date,last_day date
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r record; visit record; cfg jsonb; chosen jsonb; named record;
 sites_json jsonb:='[]'; lines jsonb; ordered_ids uuid[]; ordered_names text[];
 report_ids uuid[]; source_ids uuid[]; visits uuid[]; source_ready boolean;
 base numeric; extras numeric; welfare numeric; tax numeric; tax_rate numeric;
 overtime numeric; early numeric; allowance_rate numeric; category text;
 subtotal numeric:=0; tax_total numeric:=0; welfare_total numeric:=0;
 blocked boolean:=false; has_sources boolean:=false; issues jsonb:='[]'; unassigned boolean:=false; source_data jsonb;
begin
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into source_data
 from private.route_signed_checkout_sources(cid,first_day,last_day) x;
 select coalesce(c.notes='sko_system_unassigned_invoice_customer',false) into unassigned
 from public.customers c where c.company_id=cid and c.id=customer;
 select greatest(coalesce(c.tax_rate,0),0) into tax_rate from public.companies c where c.id=cid;
 for r in select x.worker_id,x.work_date,
   min(x.work_category) min_category,max(x.work_category) max_category,
   bool_and(x.source_ready) source_ready,
   array_agg(distinct x.report_id) report_ids,
   array_agg(distinct x.source_clock_in_id) source_ids,
   sum(x.overtime_hours) overtime_hours,sum(x.early_hours) early_hours
 from jsonb_to_recordset(source_data) as x(report_id uuid,worker_id uuid,work_date date,customer_id uuid,source_clock_in_id uuid,source_quantity numeric,quantity numeric,site_ids uuid[],site_names text[],visit_ids uuid[],visit_started_ats timestamptz[],visit_count bigint,work_category text,overtime_hours numeric,early_hours numeric,allowance_names text[],source_ready boolean,source_issue text)
 where (x.customer_id=customer or (coalesce(unassigned,false) and x.customer_id is null))
 group by x.worker_id,x.work_date order by x.work_date,x.worker_id loop
  has_sources:=true;
  -- Prior actual reviews are history, never manufactured or recalculated here.
  if exists(select 1 from private.route_billing_quantity_requests q where q.company_id=cid
    and q.worker_id=r.worker_id and q.work_date=r.work_date and q.customer_id=customer
    and q.status='approved') then continue;end if;
  chosen:=null;ordered_ids:='{}';ordered_names:='{}';visits:='{}';
  source_ready:=r.source_ready and r.min_category=r.max_category
    and r.min_category in ('day','night','holiday','holiday_night');
  category:=r.min_category;
  for visit in select v.site_id,v.site_name,v.visit_id,v.started_at
   from jsonb_to_recordset(source_data) as x(report_id uuid,worker_id uuid,work_date date,customer_id uuid,source_clock_in_id uuid,source_quantity numeric,quantity numeric,site_ids uuid[],site_names text[],visit_ids uuid[],visit_started_ats timestamptz[],visit_count bigint,work_category text,overtime_hours numeric,early_hours numeric,allowance_names text[],source_ready boolean,source_issue text),
   lateral unnest(x.site_ids,x.site_names,x.visit_ids,x.visit_started_ats)
    v(site_id,site_name,visit_id,started_at)
   where (x.customer_id=customer or (coalesce(unassigned,false) and x.customer_id is null)) and x.worker_id=r.worker_id and x.work_date=r.work_date
   order by v.started_at,v.visit_id loop
   ordered_ids:=array_append(ordered_ids,visit.site_id);
   ordered_names:=array_append(ordered_names,visit.site_name);
   visits:=array_append(visits,visit.visit_id);
   cfg:=private.route_signed_site_rates(cid,visit.site_id,category);
   source_ready:=source_ready and coalesce((cfg->>'daily')::boolean,false)
     and coalesce((cfg->>'unit_price_yen')::numeric,0)>0;
   if chosen is null then chosen:=cfg;
   else
    source_ready:=source_ready and chosen->'unit_price_yen'=cfg->'unit_price_yen'
      and chosen->'welfare_rate'=cfg->'welfare_rate';
    if r.overtime_hours>0 then source_ready:=source_ready
      and chosen->'overtime_rate'=cfg->'overtime_rate';end if;
    if r.early_hours>0 then source_ready:=source_ready
      and chosen->'early_rate'=cfg->'early_rate';end if;
    for named in select distinct label from jsonb_to_recordset(source_data) as x(report_id uuid,worker_id uuid,work_date date,customer_id uuid,source_clock_in_id uuid,source_quantity numeric,quantity numeric,site_ids uuid[],site_names text[],visit_ids uuid[],visit_started_ats timestamptz[],visit_count bigint,work_category text,overtime_hours numeric,early_hours numeric,allowance_names text[],source_ready boolean,source_issue text),
      lateral unnest(x.allowance_names) label
      where (x.customer_id=customer or (coalesce(unassigned,false) and x.customer_id is null)) and x.worker_id=r.worker_id and x.work_date=r.work_date loop
      source_ready:=source_ready and chosen->'allowance_rates'->named.label
       =cfg->'allowance_rates'->named.label;
    end loop;
   end if;
  end loop;
  -- Whole-report hours/allowances cannot be copied to several customers.
  if exists(select 1 from jsonb_to_recordset(source_data) as x(report_id uuid,worker_id uuid,work_date date,customer_id uuid,source_clock_in_id uuid,source_quantity numeric,quantity numeric,site_ids uuid[],site_names text[],visit_ids uuid[],visit_started_ats timestamptz[],visit_count bigint,work_category text,overtime_hours numeric,early_hours numeric,allowance_names text[],source_ready boolean,source_issue text)
    where x.report_id=any(r.report_ids) and x.worker_id=r.worker_id
    and (x.overtime_hours>0 or x.early_hours>0 or cardinality(x.allowance_names)>0)
    and (select count(distinct z.customer_id)+case when bool_or(z.customer_id is null) then 1 else 0 end from jsonb_to_recordset(source_data) as z(report_id uuid,worker_id uuid,work_date date,customer_id uuid,source_clock_in_id uuid,source_quantity numeric,quantity numeric,site_ids uuid[],site_names text[],visit_ids uuid[],visit_started_ats timestamptz[],visit_count bigint,work_category text,overtime_hours numeric,early_hours numeric,allowance_names text[],source_ready boolean,source_issue text)
      where z.report_id=x.report_id and z.worker_id=x.worker_id)>1) then
    source_ready:=false;
  end if;
  if not coalesce(source_ready,false) or chosen is null or cardinality(ordered_ids)=0 then
   blocked:=true;issues:=issues||jsonb_build_array(jsonb_build_object('worker_id',r.worker_id,
    'work_date',r.work_date,'source_report_ids',r.report_ids,'reason','signed_checkout_rate_or_source_unconfirmed'));
   continue;
  end if;
  base:=round((chosen->>'unit_price_yen')::numeric);
  lines:=jsonb_build_array(jsonb_build_object('site_label',array_to_string(ordered_names,'〜'),
   'work_content','複数現場','quantity',1,'unit_price',(chosen->>'unit_price_yen')::numeric,
   'unit_price_text',chosen->>'unit_price_yen','amount',base,'work_category',category,
   'route_signed_checkout_version',1,'quantity_contract','one_per_worker_day_customer',
   'source_report_ids',r.report_ids,'source_clock_in_ids',r.source_ids,'visit_ids',visits));
  early:=r.early_hours;overtime:=r.overtime_hours;
  if early>0 then
   if coalesce((chosen->>'early_rate')::numeric,0)<=0 then blocked:=true;continue;end if;
   extras:=round(early*(chosen->>'early_rate')::numeric);base:=base+extras;
   lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃','work_content','（早出）',
    'quantity',early,'unit_price',(chosen->>'early_rate')::numeric,'amount',extras));
  end if;
  if overtime>0 then
   if coalesce((chosen->>'overtime_rate')::numeric,0)<=0 then blocked:=true;continue;end if;
   extras:=round(overtime*(chosen->>'overtime_rate')::numeric);base:=base+extras;
   lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃','work_content','（残業）',
    'quantity',overtime,'unit_price',(chosen->>'overtime_rate')::numeric,'amount',extras));
  end if;
  for named in select label,count(*) quantity from jsonb_to_recordset(source_data) as x(report_id uuid,worker_id uuid,work_date date,customer_id uuid,source_clock_in_id uuid,source_quantity numeric,quantity numeric,site_ids uuid[],site_names text[],visit_ids uuid[],visit_started_ats timestamptz[],visit_count bigint,work_category text,overtime_hours numeric,early_hours numeric,allowance_names text[],source_ready boolean,source_issue text),
   lateral unnest(x.allowance_names) label where (x.customer_id=customer or (coalesce(unassigned,false) and x.customer_id is null))
    and x.worker_id=r.worker_id and x.work_date=r.work_date group by label order by label loop
   allowance_rate:=(chosen->'allowance_rates'->>named.label)::numeric;
   if coalesce(allowance_rate,0)<=0 then source_ready:=false;exit;end if;
   extras:=round(named.quantity*allowance_rate);base:=base+extras;
   lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃','work_content','（'||named.label||'）',
    'allowance_name',named.label,'quantity',named.quantity,'unit_price',allowance_rate,'amount',extras));
  end loop;
  if not coalesce(source_ready,false) then blocked:=true;continue;end if;
  welfare:=round(base*(chosen->>'welfare_rate')::numeric/100);
  tax:=round((base+welfare)*tax_rate/100);
  if welfare>0 then lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃',
    'work_content','（法定福利費）','quantity',0,'unit_price',0,'unit_price_text','','amount',welfare));end if;
  if tax>0 then lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃',
    'work_content','（消費税）','quantity',0,'unit_price',0,'unit_price_text',tax_rate::text||'%','amount',tax));end if;
  sites_json:=sites_json||jsonb_build_array(jsonb_build_object('site_id',ordered_ids[1],
   'site_name',array_to_string(ordered_names,'〜'),'visited_site_ids',ordered_ids,
   'source_report_ids',r.report_ids,'source_clock_in_ids',r.source_ids,
   'route_signed_checkout_version',1,'quantity_contract','one_per_worker_day_customer',
   'manual_adjustment',0,'welfare_rate_bps',(chosen->>'welfare_rate')::numeric*100,
   'subtotal',base+welfare,'tax',tax,'grand_total',base+welfare+tax,'lines',lines));
  subtotal:=subtotal+base+welfare;tax_total:=tax_total+tax;welfare_total:=welfare_total+welfare;
 end loop;
 return jsonb_build_object('sites',sites_json,'subtotal',subtotal,'tax',tax_total,
  'welfare',welfare_total,'blocked',blocked,'has_sources',has_sources,'issues',issues);
end $$;
revoke all on function private.route_signed_checkout_components(uuid,uuid,date,date)
 from public,anon,authenticated;


-- No legacy request, reviewer identity, attendance entry or payroll is rewritten.
create or replace function private.route_billing_invoice_blocked(
 cid uuid,customer uuid,first_day date,last_day date
) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((private.route_signed_checkout_components(cid,customer,first_day,last_day)->>'blocked')::boolean,false)
 or exists(
  select 1 from private.route_journey_visit_events v
  join private.route_journey_captures c on c.id=v.capture_id
  join public.attendance_verifications a on a.id=v.source_clock_in_id
   and a.company_id=c.company_id and a.route_assignment_id=c.route_assignment_id
   and a.worker_id=c.worker_id and a.work_date=c.work_date
  join public.route_stops stop on stop.id=c.route_stop_id and stop.route_assignment_id=c.route_assignment_id
  join public.sites s on s.id=stop.site_id and s.company_id=c.company_id
  where v.kind='start' and c.company_id=cid and s.customer_id=customer
   and c.work_date between first_day and last_day
   and not exists(select 1 from private.route_signed_checkout_sources(cid,first_day,last_day) x
    where x.customer_id=customer and x.worker_id=a.worker_id
     and x.source_clock_in_id=a.id and c.id=any(x.visit_ids))
 )
$$;
revoke all on function private.route_billing_invoice_blocked(uuid,uuid,date,date)
 from public,anon,authenticated;

-- The old pending records remain readable through their existing detail/history
-- APIs; they are not new approval work under the signed-checkout contract.
create or replace function private.pending_route_billing_quantity_rows()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.account_access_allowed() then
  raise exception 'account unavailable' using errcode='42501';end if;
 return '[]'::jsonb;
end $$;

create or replace function private.route_checkout_billing_contract()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.account_access_allowed()
  or not exists(select 1 from public.company_members where user_id=auth.uid()) then
  raise exception 'account unavailable' using errcode='42501';end if;
 return jsonb_build_object('contract_version',1,'checkout_signature_required',true,
  'quantity_contract','one_per_worker_day_customer','separate_quantity_approval_required',false);
end $$;
revoke all on function private.route_checkout_billing_contract() from public,anon;
grant execute on function private.route_checkout_billing_contract() to authenticated;
create or replace function public.route_checkout_billing_contract()
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.route_checkout_billing_contract()
$$;
revoke all on function public.route_checkout_billing_contract() from public,anon;
grant execute on function public.route_checkout_billing_contract() to authenticated;

create or replace function private.refresh_route_checkout_report_invoices(p_report_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare d public.daily_reports%rowtype;c record;changed integer:=0;
begin
 if auth.uid() is null then return 0;end if;
 select * into d from public.daily_reports where id=p_report_id;
 if not found or d.route_assignment_id is null then return 0;end if;
 if not private.account_access_allowed() or not exists(select 1 from public.company_members m
  where m.company_id=d.company_id and m.user_id=auth.uid()) then
  raise exception 'company unavailable' using errcode='42501';end if;
 for c in select distinct s.customer_id from public.attendance_verifications a
  join private.route_journey_captures cap on cap.source_clock_in_id=a.id
   and cap.company_id=a.company_id and cap.worker_id=a.worker_id
   and cap.route_assignment_id=a.route_assignment_id and cap.work_date=a.work_date
  join private.route_journey_visit_events v on v.capture_id=cap.id and v.kind='start'
  join public.route_stops stop on stop.id=cap.route_stop_id and stop.route_assignment_id=cap.route_assignment_id
  left join public.sites s on s.id=stop.site_id and s.company_id=d.company_id
  where a.daily_report_id=d.id and a.company_id=d.company_id
   and a.route_assignment_id=d.route_assignment_id and a.work_date=d.report_date
   and a.event_type='clock_in'
  order by s.customer_id loop
  perform private.refresh_automatic_invoice(d.company_id,c.customer_id,d.report_date);
  changed:=changed+1;
 end loop;
 return changed;
end $$;
revoke all on function private.refresh_route_checkout_report_invoices(uuid) from public,anon,authenticated;

create or replace function private.route_checkout_invoice_refresh_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='daily_reports' then
  perform private.refresh_route_checkout_report_invoices(new.id);
 else
  if tg_op<>'INSERT' and old.source_report_id is not null then
   perform private.refresh_route_checkout_report_invoices(old.source_report_id);end if;
  if tg_op<>'DELETE' and new.source_report_id is not null then
   perform private.refresh_route_checkout_report_invoices(new.source_report_id);end if;
 end if;
 return null;
end $$;
revoke all on function private.route_checkout_invoice_refresh_trigger() from public,anon,authenticated;
drop trigger if exists route_checkout_invoice_refresh on public.daily_reports;
create trigger route_checkout_invoice_refresh after insert or update on public.daily_reports
 for each row execute function private.route_checkout_invoice_refresh_trigger();
drop trigger if exists route_checkout_entry_invoice_refresh on public.attendance_entries;
create trigger route_checkout_entry_invoice_refresh after insert or update or delete on public.attendance_entries
 for each row execute function private.route_checkout_invoice_refresh_trigger();

create or replace function private.refresh_signed_checkout_invoices(p_company_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d record;checked integer:=0;
begin
 if auth.uid() is null or not private.account_access_allowed()
  or not private.has_company_feature(p_company_id,'can_manage_invoices')
  or not exists(select 1 from public.company_members m
    where m.company_id=p_company_id and m.user_id=auth.uid()) then
  raise exception 'invoice management unavailable' using errcode='42501';end if;
 for d in select distinct s.customer_id,date_trunc('month',a.work_date)::date work_month
  from public.attendance_verifications a
  join public.daily_reports report on report.id=a.daily_report_id
   and report.company_id=a.company_id and report.route_assignment_id=a.route_assignment_id
  join private.route_journey_captures cap on cap.source_clock_in_id=a.id
   and cap.company_id=a.company_id and cap.worker_id=a.worker_id
   and cap.route_assignment_id=a.route_assignment_id and cap.work_date=a.work_date
  join private.route_journey_visit_events v on v.capture_id=cap.id and v.kind='start'
  join public.route_stops stop on stop.id=cap.route_stop_id and stop.route_assignment_id=cap.route_assignment_id
  left join public.sites s on s.id=stop.site_id and s.company_id=a.company_id
  where a.company_id=p_company_id and a.event_type='clock_in'
   and report.route_assignment_id is not null
  order by 2,1 loop
  perform private.refresh_automatic_invoice(p_company_id,d.customer_id,d.work_month);
  checked:=checked+1;
 end loop;
 return jsonb_build_object('contract_version',1,'checked_customer_periods',checked);
end $$;
revoke all on function private.refresh_signed_checkout_invoices(uuid) from public,anon;
grant execute on function private.refresh_signed_checkout_invoices(uuid) to authenticated;
create or replace function public.refresh_signed_checkout_invoices(p_company_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select private.refresh_signed_checkout_invoices(p_company_id)
$$;
revoke all on function public.refresh_signed_checkout_invoices(uuid) from public,anon;
grant execute on function public.refresh_signed_checkout_invoices(uuid) to authenticated;


CREATE OR REPLACE FUNCTION private.route_billing_invoice_components(cid uuid, customer uuid, first_day date, last_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; blocks jsonb:='[]'; lines jsonb; base numeric; welfare numeric; tax numeric;
 subtotal numeric:=0; tax_total numeric:=0; welfare_total numeric:=0; tax_rate numeric; signed_parts jsonb;
begin
 select greatest(coalesce(c.tax_rate,0),0) into tax_rate from public.companies c where c.id=cid;
 for r in select q.*,coalesce(nullif(s.formal_name,''),s.name) site_name,
  case when f.welfare_rate between 0 and 100 then f.welfare_rate else 0 end welfare_rate
  from private.route_billing_quantity_requests q join public.sites s on s.id=q.representative_site_id
  left join public.site_financial_settings f on f.company_id=cid and f.site_id=s.id
  where q.company_id=cid and q.customer_id=customer and q.work_date between first_day and last_day
  and q.status='approved' and s.company_id=cid and s.customer_id=customer
  and not exists(select 1 from private.route_billing_quantity_evidence e join public.sites es on es.id=e.site_id
   where e.request_id=q.id and (es.company_id<>cid or es.customer_id is distinct from e.customer_id))
  order by q.work_date,q.worker_id,q.id loop
  base:=round(r.quantity*r.unit_price_yen);
  welfare:=round(base*r.welfare_rate/100);tax:=round((base+welfare)*tax_rate/100);
  lines:=jsonb_build_array(jsonb_build_object('site_label',r.site_name,'work_content','複数現場',
   'quantity',r.quantity,'unit_price',r.unit_price_yen,'unit_price_text',r.unit_price_yen::text,'amount',base,
   'route_billing_request_id',r.id,'route_billing_version',r.version));
  if welfare>0 then lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃','work_content','（法定福利費）',
   'quantity',0,'unit_price',0,'unit_price_text','','amount',welfare));end if;
  if tax>0 then lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃','work_content','（消費税）',
   'quantity',0,'unit_price',0,'unit_price_text',tax_rate::text||'%','amount',tax));end if;
  blocks:=blocks||jsonb_build_array(jsonb_build_object('site_id',r.representative_site_id,'site_name',r.site_name,
   'route_billing_request_id',r.id,'manual_adjustment',0,'welfare_rate_bps',r.welfare_rate*100,
   'subtotal',base+welfare,'tax',tax,'grand_total',base+welfare+tax,'lines',lines));
  subtotal:=subtotal+base+welfare;tax_total:=tax_total+tax;welfare_total:=welfare_total+welfare;
 end loop;
 signed_parts:=private.route_signed_checkout_components(cid,customer,first_day,last_day);
 blocks:=blocks||(signed_parts->'sites');
 subtotal:=subtotal+(signed_parts->>'subtotal')::numeric;
 tax_total:=tax_total+(signed_parts->>'tax')::numeric;
 welfare_total:=welfare_total+(signed_parts->>'welfare')::numeric;
 return jsonb_build_object('sites',blocks,'subtotal',subtotal,'tax',tax_total,'welfare',welfare_total,
  'blocked',private.route_billing_invoice_blocked(cid,customer,first_day,last_day),
  'route_signed_checkout_version',1,'source_issues',signed_parts->'issues',
  'has_requests',coalesce((signed_parts->>'has_sources')::boolean,false) or exists(select 1 from private.route_billing_quantity_requests q where q.company_id=cid
   and q.customer_id=customer and q.work_date between first_day and last_day));
end $function$;

CREATE OR REPLACE FUNCTION private.refresh_automatic_invoice(cid uuid, customer uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
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
  if n=0 and expense_amount=0 and existing.id is not null and existing.snapshot?'expense_extra_source_version' then
  update public.invoices set subtotal=0,tax=0,welfare_amount=0,grand_total=0,
   snapshot=existing.snapshot||jsonb_build_object('sites','[]'::jsonb,'subtotal',0,'tax',0,'grand_total',0,
    'route_quantity_pending',false,'route_source_pending',route_blocked,
    'route_signed_checkout_version',1,'expense_extra_amount_yen',0,'expense_extra_claims','[]'::jsonb),
   calculation_blocked=route_blocked,updated_at=now() where id=existing.id;
  return;
 end if;
 if n=0 and expense_amount=0 then
 
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
    'grand_total',total_pre_tax+total_tax+expense_amount,
    'sites',sites_json
  );

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
      (total_pre_tax+total_tax+expense_amount)::int,snapshot_value,true,route_blocked
    );
  elsif existing.snapshot is distinct from snapshot_value
     or existing.calculation_blocked is distinct from route_blocked then
    perform set_config('sko.invoice_auto_refresh','1',true);
    update public.invoices
    set subtotal=total_pre_tax::int,
        tax=total_tax::int,
        welfare_amount=total_welfare::int,
        grand_total=(total_pre_tax+total_tax+expense_amount)::int,
        snapshot=snapshot_value,
        calculation_blocked=route_blocked,
        updated_at=now()
    where id=existing.id;
    perform set_config('sko.invoice_auto_refresh','0',true);
  end if;
end;
$function$;

commit;
