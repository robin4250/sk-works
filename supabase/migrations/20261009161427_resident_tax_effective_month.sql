-- Staged direct resident-tax timeline integration. No seeds, backfill or production apply.
-- Exact reviewed calculator bodies only; never dynamically patch unknown functions.
do $$
begin
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.refresh_automatic_payroll_internal(uuid,uuid,date)') and prosecdef and proconfig=array['search_path=""'] and md5(prosrc)='27736089b8e19c35e1941a1a4d17ab60') or
 not exists(select 1 from pg_proc where oid=to_regprocedure('private.sync_payroll_attendance_detail(uuid,uuid,date)') and prosecdef and proconfig=array['search_path=""'] and md5(prosrc)='a9ba9225758f82353293c429106d65f0') or
 not exists(select 1 from pg_proc where oid=to_regprocedure('private.apply_payroll_custom_money()') and prosecdef and proconfig=array['search_path=""'] and md5(prosrc)='721226099ad188dc50a0be042339ce7b') or
 to_regprocedure('private.payroll_settings_allowed(uuid,uuid,text)') is null then
  raise exception 'reviewed payroll calculator/access prerequisite differs';
 end if;
end $$;
create schema resident_tax_private;
revoke all on schema resident_tax_private from public,anon,authenticated;
grant usage on schema resident_tax_private to authenticated;
create table resident_tax_private.state (
 company_id uuid not null references public.companies(id) on delete cascade,
 worker_id uuid not null references public.workers(id) on delete cascade,
 version bigint not null check(version>0),
 mode text not null check(mode in ('legacy','timeline')),
 cutover_month date,
 updated_by uuid not null,
 updated_at timestamptz not null,
 primary key(company_id,worker_id),
 check((mode='legacy' and cutover_month is null) or
  (mode='timeline' and cutover_month is not null and extract(day from cutover_month)=1))
);
create table resident_tax_private.entries (
 company_id uuid not null,
 worker_id uuid not null,
 effective_month date not null check(extract(day from effective_month)=1),
 amount_yen integer not null check(amount_yen>=0),
 primary key(company_id,worker_id,effective_month),
 foreign key(company_id,worker_id) references resident_tax_private.state(company_id,worker_id) on delete cascade
);
create table resident_tax_private.history (
 company_id uuid not null,
 worker_id uuid not null,
 version bigint not null,
 before_value jsonb,
 after_value jsonb not null,
 actor_id uuid not null,
 changed_at timestamptz not null,
 primary key(company_id,worker_id,version)
);
alter table resident_tax_private.state enable row level security;
alter table resident_tax_private.entries enable row level security;
alter table resident_tax_private.history enable row level security;
revoke all on all tables in schema resident_tax_private from public,anon,authenticated;

create function resident_tax_private.require_access(cid uuid,wid uuid,cap text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if cap not in ('view','edit') or auth.uid() is null or private.account_access_allowed() is distinct from true or
 private.payroll_settings_allowed(cid,wid,cap) is distinct from true then
  raise exception 'resident tax payroll access denied' using errcode='42501';
 end if;
 perform 1 from public.companies c where c.id=cid for key share;
 if not found then raise exception 'resident tax company unavailable' using errcode='42501'; end if;
 perform 1 from public.workers w where w.id=wid and w.company_id=cid for key share;
 if not found then raise exception 'resident tax worker unavailable' using errcode='42501'; end if;
end $$;

create function resident_tax_private.resolve(cid uuid,wid uuid,p_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s resident_tax_private.state%rowtype; e resident_tax_private.entries%rowtype; v_legacy integer;
begin
 select * into s from resident_tax_private.state where company_id=cid and worker_id=wid;
 if s.mode='timeline' and date_trunc('month',p_month)::date>=s.cutover_month then
  select * into e from resident_tax_private.entries where company_id=cid and worker_id=wid and effective_month<=date_trunc('month',p_month)::date
   order by effective_month desc limit 1;
  if not found then raise exception 'resident tax timeline has no effective entry'; end if;
  return jsonb_build_object('mode','timeline','effective_month',e.effective_month,'amount_yen',e.amount_yen);
 end if;
 select round(coalesce(resident_tax_monthly,0))::integer into v_legacy from public.worker_payroll_settings where company_id=cid and worker_id=wid;
 return jsonb_build_object('mode','legacy','amount_yen',coalesce(v_legacy,0));
end $$;

create function resident_tax_private.state_value(cid uuid,wid uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('version',s.version,'mode',s.mode,'cutover_month',s.cutover_month,
 'entries',coalesce((select jsonb_agg(jsonb_build_object('effective_month',e.effective_month,'amount_yen',e.amount_yen) order by e.effective_month)
 from resident_tax_private.entries e where e.company_id=s.company_id and e.worker_id=s.worker_id),'[]'::jsonb),
 'updated_by',s.updated_by,'updated_at',s.updated_at)
 from resident_tax_private.state s where s.company_id=cid and s.worker_id=wid;
$$;

create function resident_tax_private.read_state(cid uuid,wid uuid,p_month text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_month date; v_history jsonb;
begin
 perform resident_tax_private.require_access(cid,wid,'view');
 if p_month is null or p_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])-01$' then raise exception 'explicit resident tax month required' using errcode='22023'; end if;
 v_month := p_month::date;
 select coalesce(jsonb_agg(to_jsonb(h)-'company_id'-'worker_id' order by h.version desc),'[]'::jsonb)
 into v_history from (select * from resident_tax_private.history where company_id=cid and worker_id=wid order by version desc limit 100) h;
 return jsonb_build_object('state',resident_tax_private.state_value(cid,wid),'resolved',resident_tax_private.resolve(cid,wid,v_month),'history',v_history);
end $$;

create function resident_tax_private.save_state(cid uuid,wid uuid,p_expected_version bigint,p_mode text,p_cutover_month text,p_entries jsonb,p_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_before jsonb; v_after jsonb; v_version bigint; v_cutover date; v_at timestamptz;
 v_old_periods jsonb; entry jsonb; month_text text; amount_text text; v_month date;
 seen_months date[]:='{}'; first_month date; period jsonb;
begin
 perform resident_tax_private.require_access(cid,wid,'edit');
 if p_expected_version is null or p_expected_version<0 or p_confirmed is distinct from true or p_mode is null or p_mode not in ('legacy','timeline') or
 p_entries is null or jsonb_typeof(p_entries) is distinct from 'array' or jsonb_array_length(p_entries)>120 or octet_length(p_entries::text)>16384 then
  raise exception 'invalid or unconfirmed resident tax settings' using errcode='22023';
 end if;
 if p_mode='legacy' then
  if p_cutover_month is not null or p_entries<>'[]'::jsonb then raise exception 'legacy mode must not contain a timeline' using errcode='22023'; end if;
 else
  if p_cutover_month is null or p_cutover_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])-01$' or jsonb_array_length(p_entries)=0 then
   raise exception 'explicit cutover and first entry required' using errcode='22023';
  end if;
  v_cutover := p_cutover_month::date;
  for entry in select value from jsonb_array_elements(p_entries) loop
   month_text := entry->>'effective_month'; amount_text := entry->>'amount_yen';
   if jsonb_typeof(entry) is distinct from 'object' or entry-array['effective_month','amount_yen']<>'{}'::jsonb or
    jsonb_typeof(entry->'effective_month') is distinct from 'string' or month_text !~ '^[0-9]{4}-(0[1-9]|1[0-2])-01$' or
    jsonb_typeof(entry->'amount_yen') is distinct from 'number' or amount_text !~ '^[0-9]{1,10}$' or amount_text::bigint>2147483647 then
    raise exception 'invalid resident tax monthly entry' using errcode='22023';
   end if;
   v_month := month_text::date;
   if v_month<v_cutover or v_month=any(seen_months) then raise exception 'duplicate or pre-cutover resident tax month' using errcode='22023'; end if;
   seen_months := array_append(seen_months,v_month);
   if first_month is null or v_month<first_month then first_month:=v_month; end if;
  end loop;
  if first_month<>v_cutover then raise exception 'first entry must equal explicit cutover' using errcode='22023'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(cid::text||':'||wid::text||':resident-tax',0));
 perform 1 from resident_tax_private.state where company_id=cid and worker_id=wid for update;
 v_before := resident_tax_private.state_value(cid,wid);
 if coalesce((v_before->>'version')::bigint,0)<>p_expected_version then raise exception 'resident tax version conflict' using errcode='40001'; end if;
 -- Snapshot only existing automatic drafts; future registration must not create
 -- or mutate an unrelated current-month placeholder via unconditional refresh.
 select coalesce(jsonb_agg(jsonb_build_object('period_start',ps.period_start,'resolved',resident_tax_private.resolve(cid,wid,ps.period_start)) order by ps.period_start),'[]'::jsonb)
 into v_old_periods from public.payroll_statements ps where ps.company_id=cid and ps.worker_id=wid and ps.automatic_calculation and ps.workflow_state='draft';
 v_version := p_expected_version+1; v_at := clock_timestamp();
 insert into resident_tax_private.state(company_id,worker_id,version,mode,cutover_month,updated_by,updated_at)
 values(cid,wid,v_version,p_mode,v_cutover,auth.uid(),v_at)
 on conflict(company_id,worker_id) do update set version=excluded.version,mode=excluded.mode,cutover_month=excluded.cutover_month,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
 delete from resident_tax_private.entries where company_id=cid and worker_id=wid;
 if p_mode='timeline' then
  insert into resident_tax_private.entries(company_id,worker_id,effective_month,amount_yen)
  select cid,wid,(value->>'effective_month')::date,(value->>'amount_yen')::integer from jsonb_array_elements(p_entries);
 end if;
 v_after := resident_tax_private.state_value(cid,wid);
 insert into resident_tax_private.history(company_id,worker_id,version,before_value,after_value,actor_id,changed_at)
 values(cid,wid,v_version,v_before,v_after,auth.uid(),v_at);
 for period in select value from jsonb_array_elements(v_old_periods) loop
  v_month := (period->>'period_start')::date;
  if period->'resolved' is distinct from resident_tax_private.resolve(cid,wid,v_month) then
   perform private.refresh_automatic_payroll_internal(cid,wid,v_month);
   perform private.sync_payroll_attendance_detail(cid,wid,v_month);
  end if;
 end loop;
 return v_after;
end $$;
create function public.read_worker_resident_tax_schedule(p_company_id uuid,p_worker_id uuid,p_month text)
returns jsonb language sql security invoker set search_path='' as $$ select resident_tax_private.read_state(p_company_id,p_worker_id,p_month) $$;
create function public.save_worker_resident_tax_schedule(p_company_id uuid,p_worker_id uuid,p_expected_version bigint,p_mode text,p_cutover_month text,p_entries jsonb,p_confirmed boolean)
returns jsonb language sql security invoker set search_path='' as $$
 select resident_tax_private.save_state(p_company_id,p_worker_id,p_expected_version,p_mode,p_cutover_month,p_entries,p_confirmed)
$$;
revoke all on all functions in schema resident_tax_private from public,anon,authenticated;
grant execute on function resident_tax_private.read_state(uuid,uuid,text),resident_tax_private.save_state(uuid,uuid,bigint,text,text,jsonb,boolean) to authenticated;
revoke all on function public.read_worker_resident_tax_schedule(uuid,uuid,text),public.save_worker_resident_tax_schedule(uuid,uuid,bigint,text,text,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.read_worker_resident_tax_schedule(uuid,uuid,text),public.save_worker_resident_tax_schedule(uuid,uuid,bigint,text,text,jsonb,boolean) to authenticated;

-- Full reviewed function definitions, explicitly replacing the three direct reads.
CREATE OR REPLACE FUNCTION private.refresh_automatic_payroll_internal(cid uuid, wid uuid, day date)
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
  custom_earnings_total numeric:=0;
  regular_day_base numeric:=0;
  leave_days integer:=0; leave_daily numeric:=0; leave_total numeric:=0;
begin
  perform pg_advisory_xact_lock(hashtextextended(cid::text||wid::text||start_day::text,0));
  select * into current_statement
  from public.payroll_statements
  where company_id=cid and worker_id=wid and period_start=start_day and period_end=end_day
  for update;
  if found and (not current_statement.automatic_calculation or current_statement.workflow_state<>'draft') then return; end if;

  select to_jsonb(s) into settings
  from public.worker_payroll_settings s
  where s.company_id=cid and s.worker_id=wid;

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
    and coalesce((settings->>'monthly_salary_yen')::numeric,0)>0) then
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
  expected_net:=greatest(expected_gross-v_deductions,0);
  -- Capture the calculation settings with the generated draft; history is not relabeled later.
  line_detail:=jsonb_build_object(
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

CREATE OR REPLACE FUNCTION private.sync_payroll_attendance_detail(cid uuid, wid uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  start_day date := date_trunc('month', day)::date;
  end_day date := (date_trunc('month', day) + interval '1 month - 1 day')::date;
  settings jsonb := '{}'::jsonb;
  v_work_days numeric := 0;
  v_holiday_days numeric := 0;
  v_overtime numeric := 0;
  v_early numeric := 0;
  v_night numeric := 0;
  v_paid_leave numeric := 0;
  v_base_yen integer := 0;
  v_overtime_yen integer := 0;
  v_early_yen integer := 0;
  v_family_yen integer := 0;
  v_transport_yen integer := 0;
  v_income_tax integer := 0;
  v_resident_tax integer := 0;
  v_social_insurance integer := 0;
  v_other_deduction integer := 0;
  v_custom_deduction_detail jsonb := '{}'::jsonb;
  v_allowance_total integer := 0;
  v_allowances jsonb := '{}'::jsonb;
  v_gross integer := 0;
  v_other_earnings integer := 0;
begin
  select coalesce(to_jsonb(s),'{}'::jsonb)
  into settings
  from public.worker_payroll_settings s
  where s.company_id=cid and s.worker_id=wid;

  select
    coalesce(sum(coalesce(ae.base_man_days,0)),0),
    coalesce(sum(case when ae.work_category in ('holiday','holiday_night') then coalesce(ae.base_man_days,0) else 0 end),0),
    coalesce(sum(coalesce(ae.overtime_hours,0)),0),
    coalesce(sum(coalesce(ae.early_hours,0)),0),
    coalesce(sum(coalesce(ae.night_hours,0)),0),
    coalesce(sum(
      case when not exists (
        select 1
        from public.site_calculation_source_preferences scsp
        where scsp.company_id=ae.company_id
          and scsp.site_id=ae.site_id
          and scsp.output_type='payroll'
          and scsp.source='trade_company'
      ) then round(
        coalesce(ae.base_man_days,0)
        * coalesce((settings->>(coalesce(ae.work_category,'day')||'_daily'))::numeric,0)
      ) else 0 end
    ),0)::integer,
    coalesce(sum(
      case when not exists (
        select 1
        from public.site_calculation_source_preferences scsp
        where scsp.company_id=ae.company_id
          and scsp.site_id=ae.site_id
          and scsp.output_type='payroll'
          and scsp.source='trade_company'
      ) then round(
        coalesce(ae.overtime_hours,0)
        * coalesce((settings->>(coalesce(ae.work_category,'day')||'_overtime'))::numeric,0)
      ) else 0 end
    ),0)::integer,
    coalesce(sum(
      case when not exists (
        select 1
        from public.site_calculation_source_preferences scsp
        where scsp.company_id=ae.company_id
          and scsp.site_id=ae.site_id
          and scsp.output_type='payroll'
          and scsp.source='trade_company'
      ) then round(
        coalesce(ae.early_hours,0)
        * coalesce((settings->>(coalesce(ae.work_category,'day')||'_early'))::numeric,0)
      ) else 0 end
    ),0)::integer
  into
    v_work_days,v_holiday_days,v_overtime,v_early,v_night,
    v_base_yen,v_overtime_yen,v_early_yen
  from public.attendance_entries ae
  where ae.company_id=cid
    and ae.worker_id=wid
    and ae.work_date between start_day and end_day
    and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date;

  select coalesce(count(*),0)
  into v_paid_leave
  from public.paid_leave_requests pl
  where pl.company_id=cid
    and pl.worker_id=wid
    and pl.leave_date between start_day and end_day
    and pl.leave_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    and pl.status='approved' and not exists (
      select 1 from public.attendance_entries ae where ae.company_id=pl.company_id
        and ae.worker_id=pl.worker_id and ae.work_date=pl.leave_date
        and (coalesce(ae.base_man_days,0)>0 or coalesce(ae.overtime_hours,0)>0
          or coalesce(ae.early_hours,0)>0 or coalesce(ae.night_hours,0)>0)
    );

  select
    coalesce(
      jsonb_object_agg(x.allowance_name,x.amount_yen)
        filter (where x.allowance_name is not null and x.amount_yen <> 0),
      '{}'::jsonb
    ),
    coalesce(sum(x.amount_yen),0)::integer
  into v_allowances,v_allowance_total
  from (
    select
      a.allowance_name,
      (
        count(distinct ae.work_date)
        * case
            when nullif(trim(settings->>'allowance_name_1'),'')=a.allowance_name
              then coalesce((settings->>'allowance_1')::numeric,0)
            when nullif(trim(settings->>'allowance_name_2'),'')=a.allowance_name
              then coalesce((settings->>'allowance_2')::numeric,0)
            when nullif(trim(settings->>'allowance_name_3'),'')=a.allowance_name
              then coalesce((settings->>'allowance_3')::numeric,0)
            else 0
          end
      )::integer as amount_yen
    from public.attendance_entries ae
    cross join lateral unnest(coalesce(ae.allowance_names,'{}'::text[])) a(allowance_name)
    where ae.company_id=cid
      and ae.worker_id=wid
      and ae.work_date between start_day and end_day
      and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    group by a.allowance_name
  ) x;

  v_family_yen := round(coalesce((settings->>'family_monthly')::numeric,0))::integer;
  v_transport_yen := round(coalesce((settings->>'transport_monthly')::numeric,0))::integer;
  v_income_tax := round(coalesce((settings->>'income_tax_monthly')::numeric,0))::integer;
  v_resident_tax := (resident_tax_private.resolve(cid,wid,start_day)->>'amount_yen')::integer;
  v_social_insurance := round(coalesce((settings->>'social_insurance_monthly')::numeric,0))::integer;
  v_other_deduction := round(coalesce((settings->>'other_deduction_monthly')::numeric,0))::integer;

  select coalesce(jsonb_object_agg(x.name,-x.amount_yen),'{}'::jsonb)
  into v_custom_deduction_detail from (
    select trim(item->>'name') name,
      sum(greatest(coalesce((item->>'amount_yen')::integer,0),0))::integer amount_yen
    from jsonb_array_elements(coalesce(settings->'custom_deductions','[]'::jsonb)) item
    where nullif(trim(item->>'name'),'') is not null
    group by trim(item->>'name')
  ) x where x.amount_yen<>0;

  select coalesce(ps.gross_pay,0)
  into v_gross
  from public.payroll_statements ps
  where ps.company_id=cid
    and ps.worker_id=wid
    and ps.period_start=start_day
    and ps.period_end=end_day
    and ps.automatic_calculation
    and ps.workflow_state='draft'
  limit 1;

  if settings->>'pay_type'='monthly' then
    v_base_yen:=v_base_yen-coalesce((select sum(round(coalesce(ae.base_man_days,0)
      *coalesce((settings->>'day_daily')::numeric,0))) from public.attendance_entries ae
      where ae.company_id=cid and ae.worker_id=wid
        and ae.work_date between start_day and end_day
        and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
        and coalesce(ae.work_category,'day')='day'
        and not exists(select 1 from public.site_calculation_source_preferences pref
          where pref.company_id=ae.company_id and pref.site_id=ae.site_id
            and pref.output_type='payroll' and pref.source='trade_company')),0)
      +round(coalesce((settings->>'monthly_salary_yen')::numeric,0))::integer;
  end if;

  v_other_earnings := greatest(
    v_gross
      - coalesce((select (ps.detail->>'有給支給額')::numeric from public.payroll_statements ps where ps.company_id=cid and ps.worker_id=wid and ps.period_start=start_day and ps.period_end=end_day and ps.automatic_calculation and ps.workflow_state='draft' limit 1),0)
      - v_base_yen
      - v_overtime_yen
      - v_early_yen
      - v_family_yen
      - v_transport_yen
      - v_allowance_total,
    0
  );

  update public.payroll_statements ps
  set detail=
      (coalesce(ps.detail,'{}'::jsonb)-'その他支給')
      || jsonb_build_object(
        '出勤日数',v_work_days,
        '休出日数',v_holiday_days,
        '残業時間',v_overtime,
        '早出時間',v_early,
        '夜間時間',v_night,
        '有給日数',v_paid_leave,
        '基本給',v_base_yen,
        '残業手当',v_overtime_yen,
        '早出手当',v_early_yen,
        '家族手当',v_family_yen,
        '交通費',v_transport_yen,
        '所得税',v_income_tax,
        '住民税',v_resident_tax,
        'resident_tax_source',resident_tax_private.resolve(cid,wid,start_day),
        '社会保険',v_social_insurance,
        'その他控除',v_other_deduction
      )
      || case
           when v_other_earnings > 0
             then jsonb_build_object('その他支給',v_other_earnings)
           else '{}'::jsonb
         end
      || v_allowances
      || v_custom_deduction_detail,
      updated_at=now()
  where ps.company_id=cid
    and ps.worker_id=wid
    and ps.period_start=start_day
    and ps.period_end=end_day
    and ps.automatic_calculation
    and ps.workflow_state='draft';
end;
$function$;

CREATE OR REPLACE FUNCTION private.apply_payroll_custom_money()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  settings jsonb := '{}'::jsonb;
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

  select coalesce(to_jsonb(s),'{}'::jsonb)
  into settings
  from public.worker_payroll_settings s
  where s.company_id=new.company_id
    and s.worker_id=new.worker_id;

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
    'custom_earnings',normalized_earnings,
    'custom_deductions',normalized_deductions,
    'custom_earnings_total',custom_earnings_total,
    '支払日',payment_day
  );

  return new;
end
$function$
;
