-- Source migration only; no production data is backfilled.
DO $$ BEGIN
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.refresh_automatic_payroll_internal(uuid,uuid,date)') and md5(prosrc)='234054ce86ccb6dea92c53e44bf9b4d1' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'payroll unit prerequisite differs: private.refresh_automatic_payroll_internal(uuid,uuid,date)';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.apply_payroll_custom_money()') and md5(prosrc)='c3ecf4620ff2486306def20ae7456dd3' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'payroll unit prerequisite differs: private.apply_payroll_custom_money()';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('payroll_tax_private.calculate(uuid,uuid,date,date,bigint,bigint)') and md5(prosrc)='d571cc488b2e07b25a2a174609d1b115' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'payroll unit prerequisite differs: payroll_tax_private.calculate(uuid,uuid,date,date,bigint,bigint)';end if;
END $$;
-- Unit conditions are separate from legacy direct monthly amounts.
create schema if not exists payroll_unit_private;
revoke all on schema payroll_unit_private from public, anon, authenticated;
grant usage on schema payroll_unit_private to authenticated;
create table payroll_unit_private.conditions (
 company_id uuid not null references public.companies(id) on delete cascade,
 worker_id uuid not null references public.workers(id) on delete cascade,
 starts_on date not null check(starts_on=date_trunc('month',starts_on)::date),
 version bigint not null check(version>0), items jsonb not null check(jsonb_typeof(items)='array'),
 updated_by uuid not null references auth.users(id), updated_at timestamptz not null default now(),
 primary key(company_id,worker_id,starts_on)
);
create table payroll_unit_private.quantities (
 company_id uuid not null references public.companies(id) on delete cascade,
 worker_id uuid not null references public.workers(id) on delete cascade,
 item_id uuid not null, month date not null check(month=date_trunc('month',month)::date),
 hours numeric(12,4) not null check(hours>=0), updated_by uuid not null references auth.users(id),
 updated_at timestamptz not null default now(), primary key(company_id,worker_id,item_id,month)
);
alter table payroll_unit_private.conditions enable row level security;
alter table payroll_unit_private.quantities enable row level security;
revoke all on payroll_unit_private.conditions,payroll_unit_private.quantities from public,anon,authenticated;

create function payroll_unit_private.require_access(cid uuid,wid uuid,operation text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or private.account_access_allowed() is distinct from true
 or private.payroll_settings_allowed(cid,wid,operation) is distinct from true then
  raise exception 'payroll access denied' using errcode='42501';
 end if;
 perform 1 from public.companies where id=cid for key share;
 if not found then raise exception 'payroll access denied' using errcode='42501';end if;
 if operation='edit' then
  perform 1 from public.workers where id=wid and company_id=cid for update;
 else
  perform 1 from public.workers where id=wid and company_id=cid for share;
 end if;
 if not found then raise exception 'payroll access denied' using errcode='42501';end if;
end $$;

create function payroll_unit_private.resolve(cid uuid,wid uuid,p_start date,p_end date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare config payroll_unit_private.conditions%rowtype; item jsonb; quantity numeric; amount numeric;
 rows jsonb:='[]'; earnings jsonb:='[]'; deductions jsonb:='[]'; blocked boolean:=false; v_days numeric;
begin
 if p_start<>date_trunc('month',p_start)::date or p_end<>(p_start+interval '1 month - 1 day')::date then
  raise exception 'canonical payroll month required' using errcode='22023';end if;
 select * into config from payroll_unit_private.conditions where company_id=cid and worker_id=wid
 and starts_on<=p_start order by starts_on desc limit 1;
 if not found then return jsonb_build_object('contract_version',1,'items',rows,'earnings',earnings,'deductions',deductions,'blocked',false);end if;
 for item in select value from jsonb_array_elements(config.items) loop
  quantity:=null;amount:=null;
  if item->>'unit'='month' then quantity:=1;
  elsif item->>'unit'='day' then
   select count(distinct ae.work_date) into quantity from public.attendance_entries ae
   where ae.company_id=cid and ae.worker_id=wid and ae.work_date between p_start and p_end
    and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date and ae.base_man_days>0;
  elsif item->>'source'='manual_hours' then
   select q.hours into quantity from payroll_unit_private.quantities q where q.company_id=cid
    and q.worker_id=wid and q.item_id=(item->>'id')::uuid and q.month=p_start;
  else
   -- Only explicitly recorded component hours; normal hours are never inferred from man-days.
   select case when count(*)=0 then 0
    when count(*) filter(where (to_jsonb(ae)->>(item->>'source')) is null)>0 then null
    else sum((to_jsonb(ae)->>(item->>'source'))::numeric) end into quantity
   from public.attendance_entries ae where ae.company_id=cid and ae.worker_id=wid
    and ae.work_date between p_start and p_end and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date;
  end if;
  if quantity is null or quantity<0 then blocked:=true;
  else amount:=round((item->>'rate_yen')::numeric*quantity);
   if amount>2147483647 then raise exception 'payroll item amount exceeds range' using errcode='22023';end if;
   if item->>'section'='earning' then earnings:=earnings||jsonb_build_array(jsonb_build_object('name',item->>'name','amount_yen',amount));
   else deductions:=deductions||jsonb_build_array(jsonb_build_object('name',item->>'name','amount_yen',amount));end if;
  end if;
  rows:=rows||jsonb_build_array(item||jsonb_build_object('quantity',quantity,'amount_yen',amount,'quantity_month',p_start));
 end loop;
 return jsonb_build_object('contract_version',1,'condition_version',config.version,'starts_on',config.starts_on,
 'items',rows,'earnings',earnings,'deductions',deductions,'blocked',blocked);
end $$;

create function payroll_unit_private.augment_settings(cid uuid,wid uuid,p_start date,p_end date,settings jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare resolved jsonb;
begin
 resolved:=payroll_unit_private.resolve(cid,wid,p_start,p_end);
 if resolved->'items'='[]'::jsonb then return settings;end if;
 return coalesce(settings,'{}')||jsonb_build_object(
 'custom_earnings',coalesce(settings->'custom_earnings','[]')||(resolved->'earnings'),
 'custom_deductions',coalesce(settings->'custom_deductions','[]')||(resolved->'deductions'),
 '_unit_resolution',resolved);
end $$;

create function payroll_unit_private.read_conditions(cid uuid,wid uuid,p_month date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare config payroll_unit_private.conditions%rowtype; items jsonb;
begin
 perform payroll_unit_private.require_access(cid,wid,'view');
 if p_month is null or p_month<>date_trunc('month',p_month)::date then raise exception 'canonical month required';end if;
 select * into config from payroll_unit_private.conditions where company_id=cid and worker_id=wid
 and starts_on<=p_month order by starts_on desc limit 1;
 select coalesce(jsonb_agg(item||jsonb_build_object('quantity',q.hours) order by ord),'[]') into items
 from jsonb_array_elements(coalesce(config.items,'[]')) with ordinality e(item,ord)
 left join payroll_unit_private.quantities q on q.company_id=cid and q.worker_id=wid
 and q.item_id=(item->>'id')::uuid and q.month=p_month;
 return jsonb_build_object('version',coalesce(config.version,0),'month',p_month,'items',items,
 'can_edit',private.payroll_settings_allowed(cid,wid,'edit'),'resolved',payroll_unit_private.resolve(cid,wid,p_month,(p_month+interval '1 month - 1 day')::date));
end $$;

create function payroll_unit_private.save_conditions(cid uuid,wid uuid,p_month date,p_expected_version bigint,p_items jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare prior payroll_unit_private.conditions%rowtype; item jsonb; normalized jsonb:='[]'; iid uuid;
 rate numeric; qty numeric; seen uuid[]:='{}'; names text[]:='{}'; identity text; period record;
begin
 perform payroll_unit_private.require_access(cid,wid,'edit');
 if p_month is null or p_month<>date_trunc('month',p_month)::date or p_expected_version is null
 or p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>100 then raise exception 'invalid unit conditions';end if;
 -- Match the formal calculator order before modifying conditions. Every affected
 -- existing month is locked in date order so concurrent finalization cannot win
 -- between the immutable-state check and saving a quantity.
 perform pg_advisory_xact_lock_shared(hashtextextended(cid::text||':payroll-rate-registry',0));
 for period in
  select month from (
   select p_month as month union select period_start from public.payroll_statements
   where company_id=cid and worker_id=wid and period_start>=p_month
    and automatic_calculation and workflow_state='draft'
  ) affected order by month
 loop
  perform pg_advisory_xact_lock(hashtextextended(cid::text||wid::text||period.month::text,0));
 end loop;
 perform pg_advisory_xact_lock(hashtextextended(cid::text||wid::text||':unit-conditions',0));
 select * into prior from payroll_unit_private.conditions where company_id=cid and worker_id=wid
 and starts_on<=p_month order by starts_on desc limit 1;
 if coalesce(prior.version,0)<>p_expected_version then raise exception 'payroll unit version conflict';end if;
 if exists(select 1 from public.payroll_statements where company_id=cid and worker_id=wid and period_start=p_month
  and (workflow_state<>'draft' or not automatic_calculation)) then raise exception 'finalized/manual payroll is unchanged';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  if jsonb_typeof(item)<>'object' or coalesce(item->>'section','') not in ('earning','deduction')
  or coalesce(item->>'unit','') not in ('hour','day','month') or nullif(trim(item->>'name'),'') is null
  or length(trim(item->>'name'))>100 or coalesce(item->>'rate_yen','') !~ '^\d+$' then raise exception 'invalid payroll unit item';end if;
  rate:=(item->>'rate_yen')::numeric;
  if rate>2147483647 then raise exception 'payroll rate exceeds range';end if;
  if item->>'unit'='hour' and coalesce(item->>'source','') not in ('manual_hours','overtime_hours','early_hours','night_hours') then raise exception 'explicit hours source required';end if;
  iid:=case when item->>'id' is null then gen_random_uuid() else (item->>'id')::uuid end;
  if item->>'id' is not null and not exists(select 1 from jsonb_array_elements(coalesce(prior.items,'[]')) x where x->>'id'=iid::text) then raise exception 'unknown payroll item identity';end if;
  identity:=(item->>'section')||'/'||(item->>'unit')||'/'||trim(item->>'name');
  if iid=any(seen) or identity=any(names) then raise exception 'duplicate payroll unit item';end if;
  seen:=array_append(seen,iid);names:=array_append(names,identity);
  -- Explicit monthly hours are required when selected; zero is accepted only when actually entered.
  if item->>'unit'='hour' and item->>'source'='manual_hours' then
   if coalesce(item->>'quantity','') !~ '^\d+(\.\d{1,4})?$' then raise exception 'explicit monthly hours required';end if;
   qty:=(item->>'quantity')::numeric;
   if qty>99999999 then raise exception 'quantity exceeds range';end if;
   insert into payroll_unit_private.quantities values(cid,wid,iid,p_month,qty,auth.uid(),now())
   on conflict(company_id,worker_id,item_id,month) do update set hours=excluded.hours,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
  end if;
  normalized:=normalized||jsonb_build_array(jsonb_build_object('id',iid,'section',item->>'section','unit',item->>'unit',
   'name',trim(item->>'name'),'rate_yen',rate,'source',case item->>'unit' when 'hour' then item->>'source' when 'day' then 'attendance_days' else 'monthly_fixed' end));
 end loop;
 insert into payroll_unit_private.conditions values(cid,wid,p_month,coalesce(prior.version,0)+1,normalized,auth.uid(),now())
 on conflict(company_id,worker_id,starts_on) do update set version=excluded.version,items=excluded.items,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
 -- Recalculate real automatic drafts at/after the effective month; finalized/manual rows remain untouched.
 for period in select distinct period_start from public.payroll_statements where company_id=cid and worker_id=wid
 and period_start>=p_month and automatic_calculation and workflow_state='draft' order by period_start loop
  perform private.refresh_automatic_payroll(cid,wid,period.period_start);
  perform private.sync_payroll_attendance_detail(cid,wid,period.period_start);
 end loop;
 perform private.refresh_automatic_payroll(cid,wid,p_month);
 perform private.sync_payroll_attendance_detail(cid,wid,p_month);
 return payroll_unit_private.read_conditions(cid,wid,p_month);
end $$;

revoke all on all functions in schema payroll_unit_private from public,anon,authenticated;
grant execute on function payroll_unit_private.read_conditions(uuid,uuid,date),payroll_unit_private.save_conditions(uuid,uuid,date,bigint,jsonb) to authenticated;
create function public.payroll_unit_conditions_contract_version() returns integer language sql stable security invoker set search_path='' as $$select 1$$;
create function public.payroll_unit_conditions(p_company_id uuid,p_worker_id uuid,p_month date) returns jsonb
language sql security invoker set search_path='' as $$select payroll_unit_private.read_conditions(p_company_id,p_worker_id,p_month)$$;
create function public.save_payroll_unit_conditions(p_company_id uuid,p_worker_id uuid,p_month date,p_expected_version bigint,p_items jsonb) returns jsonb
language sql security invoker set search_path='' as $$select payroll_unit_private.save_conditions(p_company_id,p_worker_id,p_month,p_expected_version,p_items)$$;
revoke all on function public.payroll_unit_conditions_contract_version(),public.payroll_unit_conditions(uuid,uuid,date),public.save_payroll_unit_conditions(uuid,uuid,date,bigint,jsonb) from public,anon;
grant execute on function public.payroll_unit_conditions_contract_version(),public.payroll_unit_conditions(uuid,uuid,date),public.save_payroll_unit_conditions(uuid,uuid,date,bigint,jsonb) to authenticated;


create or replace function private.refresh_automatic_payroll_internal(cid uuid, wid uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  start_day date:=date_trunc('month',day)::date;
  end_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
  settings jsonb; resident_source jsonb; a record; current_statement public.payroll_statements%rowtype;
  total numeric:=0; v_deductions numeric:=0; v_custom_deductions numeric:=0; count_rows int:=0;
  category text; allowance text; allowance_index int; seen text[]:='{}'; token text;
  line_detail jsonb; fingerprint text; saved_id uuid; saved_revision int;
  pref record;
  fixed_trade_seen uuid[]:='{}';
  trade_amount numeric;
  expected_gross numeric:=0;
  expected_net numeric:=0;
  tax_result jsonb;
  custom_earnings_total numeric:=0;
  regular_day_base numeric:=0;
  leave_days integer:=0; leave_daily numeric:=0; leave_total numeric:=0;
begin
  perform pg_advisory_xact_lock_shared(hashtextextended(cid::text||':payroll-rate-registry',0));
  perform pg_advisory_xact_lock(hashtextextended(cid::text||wid::text||start_day::text,0));
  select * into current_statement
  from public.payroll_statements
  where company_id=cid and worker_id=wid and period_start=start_day and period_end=end_day
  for update;
  if found and (not current_statement.automatic_calculation or current_statement.workflow_state<>'draft') then return; end if;

  select to_jsonb(s) into settings
  from public.worker_payroll_settings s
  where s.company_id=cid and s.worker_id=wid;

  settings:=payroll_unit_private.augment_settings(cid,wid,start_day,end_day,settings);
  resident_source := resident_tax_private.resolve(cid,wid,start_day);

  select md5(
    'paid_leave_wage_contract:1'||
    case when resident_source->>'mode'='timeline' then
      coalesce((settings-'updated_at'-'payment_day'-'resident_tax_monthly')::text,'')||resident_source::text
      else coalesce((settings-'updated_at'-'payment_day')::text,'') end||
    coalesce((select jsonb_build_object('payment_day',c.payroll_payment_day,
      'payment_month_offset',c.payroll_payment_month_offset,
      'closing_day',c.payroll_closing_day)::text from public.companies c where c.id=cid),'')||
    coalesce((
      select jsonb_agg(to_jsonb(ae)-'updated_at'-'created_at' order by ae.work_date,ae.id)::text
      from public.attendance_entries ae
      where ae.company_id=cid and ae.worker_id=wid
        and ae.work_date between start_day and end_day
        and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    ),'')||
    coalesce((select jsonb_agg(jsonb_build_object('leave_date',pl.leave_date,'status',pl.status)
      order by pl.leave_date)::text from public.paid_leave_requests pl
      where pl.company_id=cid and pl.worker_id=wid and pl.leave_date between start_day and end_day
        and pl.leave_date<=(current_timestamp at time zone 'Asia/Tokyo')::date),'')||
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

  select count(distinct pl.leave_date) into leave_days
  from public.paid_leave_requests pl
  where pl.company_id=cid and pl.worker_id=wid and pl.status='approved'
    and pl.leave_date between start_day and end_day
    and pl.leave_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    and not exists(select 1 from public.attendance_entries ae
      where ae.company_id=pl.company_id and ae.worker_id=pl.worker_id and ae.work_date=pl.leave_date
        and (coalesce(ae.base_man_days,0)>0 or coalesce(ae.overtime_hours,0)>0
          or coalesce(ae.early_hours,0)>0 or coalesce(ae.night_hours,0)>0));
  leave_daily:=private.paid_leave_daily_amount(settings);
  if coalesce(settings->>'pay_type','daily')<>'monthly' then
    leave_total:=leave_days*leave_daily;
    total:=total+leave_total;
  end if;

  -- A registered positive monthly salary is payable independently of attendance.
  -- Daily/hourly approved leave-only months use the configured wage contract.
  if count_rows=0 and leave_days=0 and not (coalesce(settings->>'pay_type','daily')='monthly'
    and coalesce((settings->>'monthly_salary_yen')::numeric,0)>0)
    and jsonb_array_length(coalesce(settings#>'{_unit_resolution,items}','[]'))=0 then
    if current_statement.id is not null and current_statement.workflow_state='draft' and current_statement.automatic_calculation then
      delete from public.payroll_statements where id=current_statement.id;
    end if;
    return;
  end if;

  if settings is not null then
    total:=total+round(coalesce((settings->>'family_monthly')::numeric,0))
      +round(coalesce((settings->>'transport_monthly')::numeric,0));
    select coalesce(sum(greatest(coalesce((item->>'amount_yen')::integer,0),0)),0)
    into v_custom_deductions
    from jsonb_array_elements(coalesce(settings->'custom_deductions','[]'::jsonb)) item
    where nullif(trim(item->>'name'),'') is not null;

    v_deductions:=round(coalesce((settings->>'income_tax_monthly')::numeric,0))
      +(resident_source->>'amount_yen')::integer
      +round(coalesce((settings->>'social_insurance_monthly')::numeric,0))
      +round(coalesce((settings->>'other_deduction_monthly')::numeric,0))
      +round(v_custom_deductions);
  end if;

  -- Timeline remains a direct tax source even before wage settings exist.
  if settings is null then v_deductions := (resident_source->>'amount_yen')::integer; end if;
  total:=greatest(coalesce(total,0),0);
  v_deductions:=greatest(coalesce(v_deductions,0),0);
  -- Compare the same final amounts that the existing normalization triggers persist.
  -- INSERT/UPDATE below still provide raw attendance totals to those triggers.
  expected_gross:=total;
  if settings->>'pay_type'='monthly' then
    select coalesce(round(sum(coalesce(ae.base_man_days,0)
      *coalesce((settings->>'day_daily')::numeric,0))),0)
    into regular_day_base
    from public.attendance_entries ae
    where ae.company_id=cid and ae.worker_id=wid
      and ae.work_date between start_day and end_day
      and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
      and coalesce(ae.work_category,'day')='day';
    expected_gross:=greatest(expected_gross-regular_day_base
      +round(coalesce((settings->>'monthly_salary_yen')::numeric,0)),0);
  end if;
  select coalesce(sum(greatest(coalesce((item->>'amount_yen')::integer,0),0)),0)
  into custom_earnings_total
  from jsonb_array_elements(coalesce(settings->'custom_earnings','[]'::jsonb)) item
  where nullif(trim(item->>'name'),'') is not null;
  expected_gross:=greatest(expected_gross+custom_earnings_total,0);
  tax_result:=payroll_tax_private.calculate(cid,wid,start_day,end_day,expected_gross::bigint,v_deductions::bigint);
  if tax_result is not null then
    v_deductions:=(tax_result->>'deductions')::numeric;
    fingerprint:=md5(fingerprint||tax_result::text);
  end if;
  expected_net:=greatest(expected_gross-v_deductions,0);
  -- Capture the calculation settings with the generated draft; history is not relabeled later.
  line_detail:=jsonb_build_object(
    'unit_resolution',settings->'_unit_resolution',
    'resident_tax_source',resident_source,
    'paid_leave_wage_contract',1,
    '有給単価',leave_daily,
    '有給支給額',leave_total,
    '有給内訳額',leave_days*leave_daily,
    'pay_type',coalesce(settings->>'pay_type','daily'),
    'rate_formula',coalesce(settings->'rate_formula','{}'::jsonb),
    'hourly_rate_yen',coalesce(settings->'hourly_rate_yen','0'::jsonb),
    '出勤日数',coalesce((select sum(coalesce(ae.base_man_days,0)) from public.attendance_entries ae
      where ae.company_id=cid and ae.worker_id=wid and ae.work_date between start_day and end_day
        and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date),0),
    '有給日数',coalesce((select count(*) from public.paid_leave_requests pl
      where pl.company_id=cid and pl.worker_id=wid and pl.leave_date between start_day and end_day
        and pl.leave_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
        and pl.status='approved' and not exists (
      select 1 from public.attendance_entries ae where ae.company_id=pl.company_id
        and ae.worker_id=pl.worker_id and ae.work_date=pl.leave_date
        and (coalesce(ae.base_man_days,0)>0 or coalesce(ae.overtime_hours,0)>0
          or coalesce(ae.early_hours,0)>0 or coalesce(ae.night_hours,0)>0)
    )),0),
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
            and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
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
  elsif current_statement.gross_pay is distinct from expected_gross::int
      or current_statement.deductions is distinct from v_deductions::int
      or current_statement.net_pay is distinct from expected_net::int
      or current_statement.calculation_fingerprint is distinct from fingerprint
      or current_statement.calculation_blocked is distinct from (coalesce((tax_result->>'blocked')::boolean,false) or coalesce((settings#>>'{_unit_resolution,blocked}')::boolean,false)) then
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

create or replace function private.apply_payroll_custom_money()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  settings jsonb := '{}'::jsonb;
  tax_result jsonb;
  custom_earnings_total integer := 0;
  custom_deductions_total integer := 0;
  previous_earnings_total integer := 0;
  fixed_deductions_total integer := 0;
  normalized_earnings jsonb := '[]'::jsonb;
  normalized_deductions jsonb := '[]'::jsonb;
  item jsonb;
  item_name text;
  item_amount integer;
  payment_day integer := 25;
begin
  if not new.automatic_calculation or new.workflow_state <> 'draft' then
    return new;
  end if;

  perform pg_advisory_xact_lock_shared(hashtextextended(new.company_id::text||':payroll-rate-registry',0));

  select coalesce(to_jsonb(s),'{}'::jsonb)
  into settings
  from public.worker_payroll_settings s
  where s.company_id=new.company_id
    and s.worker_id=new.worker_id;

  settings:=payroll_unit_private.augment_settings(new.company_id,new.worker_id,new.period_start,new.period_end,settings);
  if coalesce((settings#>>'{_unit_resolution,blocked}')::boolean,false) then new.calculation_blocked:=true;end if;
  -- Company policy is the only source; legacy worker payment_day is ignored.
  select c.payroll_payment_day into payment_day
  from public.companies c where c.id=new.company_id;
  payment_day:=greatest(least(coalesce(payment_day,25),31),1);

  -- Fresh calculator detail does not contain previously applied named earnings.
  -- Only subtract them for an edit carrying the normalized prior detail.
  if tg_op='UPDATE' and coalesce(new.detail,'{}'::jsonb) ? 'custom_earnings_total' then
    previous_earnings_total :=
      coalesce((old.detail->>'custom_earnings_total')::integer,0);
  end if;

  if jsonb_typeof(settings->'custom_earnings')='array' then
    for item in
      select value
      from jsonb_array_elements(settings->'custom_earnings')
    loop
      item_name := nullif(trim(item->>'name'),'');
      item_amount := greatest(coalesce((item->>'amount_yen')::integer,0),0);
      if item_name is null then continue; end if;
      normalized_earnings := normalized_earnings || jsonb_build_array(
        jsonb_build_object('name',item_name,'amount_yen',item_amount)
      );
      custom_earnings_total := custom_earnings_total + item_amount;
    end loop;
  end if;

  if jsonb_typeof(settings->'custom_deductions')='array' then
    for item in
      select value
      from jsonb_array_elements(settings->'custom_deductions')
    loop
      item_name := nullif(trim(item->>'name'),'');
      item_amount := greatest(coalesce((item->>'amount_yen')::integer,0),0);
      if item_name is null then continue; end if;
      normalized_deductions := normalized_deductions || jsonb_build_array(
        jsonb_build_object('name',item_name,'amount_yen',item_amount)
      );
      custom_deductions_total := custom_deductions_total + item_amount;
    end loop;
  end if;

  fixed_deductions_total :=
      round(coalesce((settings->>'income_tax_monthly')::numeric,0))::integer
    + (resident_tax_private.resolve(new.company_id,new.worker_id,new.period_start)->>'amount_yen')::integer
    + round(coalesce((settings->>'social_insurance_monthly')::numeric,0))::integer
    + round(coalesce((settings->>'other_deduction_monthly')::numeric,0))::integer;

  new.gross_pay := greatest(
    coalesce(new.gross_pay,0) - previous_earnings_total + custom_earnings_total,
    0
  );
  new.deductions := greatest(
    fixed_deductions_total + custom_deductions_total,
    0
  );
  new.net_pay := greatest(new.gross_pay - new.deductions,0);
  new.detail := (
    coalesce(new.detail,'{}'::jsonb)
      - '勤続手当'
      - '役職手当'
      - '働き方手当'
      - '介護保険料'
      - '厚生年金保険'
      - '雇用保険料'
      - 'SKB会費'
  ) || jsonb_build_object(
    'resident_tax_source',resident_tax_private.resolve(new.company_id,new.worker_id,new.period_start),
    '家族手当',round(coalesce((settings->>'family_monthly')::numeric,0))::integer,
    'unit_resolution',settings->'_unit_resolution',
    'custom_earnings',normalized_earnings,
    'custom_deductions',normalized_deductions,
    'custom_earnings_total',custom_earnings_total,
    '支払日',payment_day
  );

  tax_result:=payroll_tax_private.calculate(new.company_id,new.worker_id,new.period_start,new.period_end,new.gross_pay,new.deductions);
  if tax_result->>'blocked'='true' then
    new.calculation_blocked:=true;
    new.detail:=new.detail||jsonb_build_object('tax_calculation',tax_result);
  elsif tax_result is not null then
    new.deductions:=(tax_result->>'deductions')::integer;
    new.net_pay:=greatest(new.gross_pay-new.deductions,0);
    new.detail:=new.detail||jsonb_build_object('所得税',(tax_result->>'income_tax_yen')::integer,'tax_calculation',tax_result);
    if tax_result#>>'{conditions,insurance_mode}'='rates' then
      new.detail:=(new.detail-array['社会保険','健康保険料','介護保険料','厚生年金保険','雇用保険料','子ども・子育て支援金'])||(tax_result->'premiums');
    else
      new.detail:=new.detail||jsonb_build_object('社会保険',(tax_result->>'social_yen')::integer);
    end if;
  else
    new.detail:=new.detail-'tax_calculation';
  end if;
  return new;
end
$function$;

create or replace function payroll_tax_private.calculate(cid uuid,wid uuid,p_start date,p_end date,p_gross bigint,p_legacy_deductions bigint)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare profile payroll_tax_private.worker_conditions%rowtype; v jsonb; settings jsonb;
 payday date; additions bigint; gross bigint; social bigint; income bigint; legacy_social bigint; legacy_income bigint;
 premiums jsonb:='{}'; evidence jsonb:='[]'; item jsonb; val jsonb; kind text; flag text; label text;
 base bigint; premium integer; insured_month date; birth date; age_start date; age_end date;
 deduction bigint; taxable bigint; month_offset integer; expected_payment date;
 health_raw numeric:=0; health_rounded integer:=0; health_month date;
begin
 select * into profile from payroll_tax_private.worker_conditions where company_id=cid and worker_id=wid and starts_on<=p_start order by starts_on desc limit 1;
 if not found then return null;end if;
 v:=profile.value;perform payroll_tax_private.validate_conditions(v);
 if p_start<>date_trunc('month',p_start)::date or p_end<>(p_start+interval '1 month - 1 day')::date then raise exception '税自動計算は月次給与を対象とします' using errcode='22023';end if;
 select to_jsonb(s) into settings from public.worker_payroll_settings s where company_id=cid and worker_id=wid;
 if settings is null then raise exception '個別給与設定がありません' using errcode='22023';end if;
 settings:=payroll_unit_private.augment_settings(cid,wid,p_start,p_end,settings);
 legacy_social:=round(coalesce((settings->>'social_insurance_monthly')::numeric,0));
 legacy_income:=round(coalesce((settings->>'income_tax_monthly')::numeric,0));
 payday:=private.payroll_payment_date(p_end,cid,'{}'::jsonb);
 select coalesce(sum(amount_yen) filter(where direction='addition'),0) into additions from public.payroll_adjustments
 where company_id=cid and worker_id=wid and effective_date between p_start and p_end and cancelled_at is null;
 gross:=p_gross+additions;
 if gross<0 or (v->>'income_mode'<>'fixed' and (v->>'non_taxable_yen')::bigint>gross) or (v->>'insurance_mode'='rates' and (v->>'employment')::boolean and (v->>'employment_excluded_yen')::bigint>gross) then
  raise exception '非課税額・雇用保険対象外額が支給額を超えています' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(coalesce(settings->'custom_deductions','[]')) x where coalesce((x->>'amount_yen')::numeric,0)<>0 and (
 (v->>'insurance_mode'='rates' and trim(x->>'name') in ('健康保険料','社会保険','社会保険料','介護保険料','厚生年金保険','厚生年金保険料','雇用保険料','子ども・子育て支援金')) or
 (v->>'income_mode'<>'fixed' and trim(x->>'name')='所得税'))) then
 raise exception '自由控除に同じ税・保険料があります。二重控除を避けるため確認してください' using errcode='22023';end if;
 if exists(select 1 from public.payroll_adjustments a where a.company_id=cid and a.worker_id=wid and a.effective_date between p_start and p_end and a.cancelled_at is null and a.amount_yen<>0 and (
  (v->>'insurance_mode'='rates' and trim(a.label_snapshot) in ('健康保険料','社会保険','社会保険料','介護保険料','厚生年金保険','厚生年金保険料','雇用保険料','子ども・子育て支援金')) or
  (v->>'income_mode'<>'fixed' and trim(a.label_snapshot)='所得税'))) then
  raise exception '給与調整に同じ税・保険料があります。二重計上を避けるため確認してください' using errcode='22023';end if;
 social:=legacy_social;
 if v->>'insurance_mode'='rates' then
  social:=0;
  foreach kind in array array['health_insurance','nursing_insurance','pension_insurance','employment_insurance','child_support'] loop
   flag:=case kind when 'health_insurance' then 'health' when 'nursing_insurance' then 'nursing' when 'pension_insurance' then 'pension' when 'employment_insurance' then 'employment' else 'child_support' end;
   label:=case kind when 'health_insurance' then '健康保険料' when 'nursing_insurance' then '介護保険料' when 'pension_insurance' then '厚生年金保険' when 'employment_insurance' then '雇用保険料' else '子ども・子育て支援金' end;
   premium:=0;
   if (v->>flag)::boolean then
    item:=payroll_tax_private.rate_for_month(cid,kind,p_start);
    if item is null then raise exception '適用月の料率が未設定です: %',label using errcode='22023';end if;
    val:=item->'value';perform payroll_rate_private.validate_value(val);
    month_offset:=(extract(year from (val->>'insurance_month')::date)::integer-extract(year from (val->>'payroll_month')::date)::integer)*12+extract(month from (val->>'insurance_month')::date)::integer-extract(month from (val->>'payroll_month')::date)::integer;
    insured_month:=(p_start+make_interval(months=>month_offset))::date;
    month_offset:=(extract(year from (val->>'payment_month')::date)::integer-extract(year from (val->>'payroll_month')::date)::integer)*12+extract(month from (val->>'payment_month')::date)::integer-extract(month from (val->>'payroll_month')::date)::integer;
    expected_payment:=(p_start+make_interval(months=>month_offset))::date;
    if expected_payment<>date_trunc('month',payday)::date then raise exception '料率の支払月と会社の給与支払月が一致しません: %',label using errcode='22023';end if;
    base:=case kind when 'pension_insurance' then (v->>'pension_base_yen')::bigint when 'employment_insurance' then gross-(v->>'employment_excluded_yen')::bigint else (v->>'health_base_yen')::bigint end;
    if kind='nursing_insurance' then
     birth:=(v->>'birth_date')::date;
     age_start:=date_trunc('month',birth+interval '40 years'-interval '1 day')::date;
     age_end:=date_trunc('month',birth+interval '65 years'-interval '1 day')::date;
     if insured_month<age_start or insured_month>=age_end then base:=0;end if;
    end if;
    if kind in ('health_insurance','nursing_insurance','child_support') then
     if health_month is not null and health_month<>insured_month then raise exception '健康保険・介護・支援金の適用月が一致しません' using errcode='22023';end if;
     health_month:=insured_month;
     health_raw:=health_raw+base::numeric*(val->>'employee')::bigint/100000000;
     premium:=greatest(ceil(health_raw-0.5),0)::integer-health_rounded;
     health_rounded:=health_rounded+premium;
    else
     premium:=payroll_tax_private.employee_premium(base,(val->>'employee')::bigint);
    end if;
    evidence:=evidence||jsonb_build_array(item||jsonb_build_object('insurance_month',insured_month,'base_yen',base,'employee_yen',premium));
   end if;
   social:=social+premium;premiums:=premiums||jsonb_build_object(label,premium);
  end loop;
 end if;
 taxable:=greatest(gross-(v->>'non_taxable_yen')::bigint-social-(v->>'additional_social_deduction_yen')::bigint,0);
 income:=legacy_income;
 if v->>'income_mode'<>'fixed' then income:=payroll_tax_private.monthly_income_tax(payday,taxable,v->>'income_mode',(v->>'dependents')::integer);end if;
 deduction:=p_legacy_deductions-legacy_income-legacy_social+income+social;
 if deduction<0 then raise exception '控除合計が不整合です' using errcode='22023';end if;
 return jsonb_build_object('calculator_version','payroll-tax-20261010-v1','condition_version',profile.version,'conditions_start',profile.starts_on,'conditions',v,
 'payment_date',payday,'gross_with_adjustments',gross,'income_tax_base_yen',taxable,'income_tax_yen',income,'social_yen',social,'deductions',deduction,
 'premiums',premiums,'rates',evidence,'income_table',case when v->>'income_mode'='fixed' then null else 'nta-monthly-2026-c583c9c3' end);
exception when sqlstate '22023' then
 return jsonb_build_object('calculator_version','payroll-tax-20261010-v1','blocked',true,'reason',sqlerrm,'deductions',p_legacy_deductions,'conditions_start',profile.starts_on,'condition_version',profile.version);
end $$;
