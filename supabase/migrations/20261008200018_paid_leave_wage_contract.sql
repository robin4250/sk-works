-- Future automatic drafts only. No backfill, no historical statement rewrites.
create or replace function private.paid_leave_daily_amount(settings jsonb)
returns numeric language sql immutable set search_path='' as $$
 select greatest(case coalesce(settings->>'pay_type','daily')
 when 'monthly' then round(coalesce((settings->>'calculation_daily_base_yen')::numeric,0))
 when 'hourly' then round(coalesce((settings->'rate_formula'->>'paid_leave_daily_yen')::numeric,
   coalesce((settings->>'hourly_rate_yen')::numeric,0)*8))
 else round(coalesce((settings->>'day_daily')::numeric,0)) end,0)
$$;
revoke all on function private.paid_leave_daily_amount(jsonb) from public,anon,authenticated;

create or replace function public.paid_leave_wage_contract_version()
returns integer language sql stable security invoker set search_path='' as $$ select 1 $$;
revoke all on function public.paid_leave_wage_contract_version() from public,anon;
grant execute on function public.paid_leave_wage_contract_version() to authenticated;

CREATE OR REPLACE FUNCTION private.refresh_automatic_payroll_internal(cid uuid, wid uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  start_day date:=date_trunc('month',day)::date;
  end_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
  settings jsonb; a record; current_statement public.payroll_statements%rowtype;
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

  select md5(
    'paid_leave_wage_contract:1'||
    coalesce((settings-'updated_at'-'payment_day')::text,'')||
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
      +round(coalesce((settings->>'resident_tax_monthly')::numeric,0))
      +round(coalesce((settings->>'social_insurance_monthly')::numeric,0))
      +round(coalesce((settings->>'other_deduction_monthly')::numeric,0))
      +round(v_custom_deductions);
  end if;

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
  v_resident_tax := round(coalesce((settings->>'resident_tax_monthly')::numeric,0))::integer;
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


create or replace function private.paid_leave_sync_payroll_detail()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op<>'INSERT' then
   perform private.refresh_automatic_payroll_internal(old.company_id,old.worker_id,old.leave_date);
   perform private.sync_payroll_attendance_detail(old.company_id,old.worker_id,old.leave_date);
 end if;
 if tg_op<>'DELETE' then
   perform private.refresh_automatic_payroll_internal(new.company_id,new.worker_id,new.leave_date);
   perform private.sync_payroll_attendance_detail(new.company_id,new.worker_id,new.leave_date);
 end if;
 return null;
end $$;
revoke all on function private.paid_leave_sync_payroll_detail() from public,anon,authenticated;

-- Read-only financial-condition warnings. Never invent wage rules or alter amounts/finalized history.
create or replace function private.payroll_condition_warnings(cid uuid,wid uuid,p_start date,p_end date)
returns text[] language plpgsql stable security definer set search_path='' as $$
declare settings jsonb; warnings text[]:='{}'; leave_count int; night_hours numeric; missing_categories text;
begin
 select to_jsonb(s) into settings from public.worker_payroll_settings s where s.company_id=cid and s.worker_id=wid;
 if settings is null then return warnings; end if;
 if coalesce(settings->>'pay_type','daily') in ('daily','hourly') then
 select count(*) into leave_count from public.paid_leave_requests pl where pl.company_id=cid and pl.worker_id=wid and pl.status='approved'
 and pl.leave_date between p_start and p_end and pl.leave_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
 and not exists(select 1 from public.attendance_entries ae where ae.company_id=pl.company_id and ae.worker_id=pl.worker_id and ae.work_date=pl.leave_date
 and (coalesce(ae.base_man_days,0)>0 or coalesce(ae.overtime_hours,0)>0 or coalesce(ae.early_hours,0)>0 or coalesce(ae.night_hours,0)>0));
 if leave_count>0 and private.paid_leave_daily_amount(settings)<=0 then warnings:=array_append(warnings,'有給'||leave_count::text||'日：有給単価が0円です。個別給与設定の有給額を確認してください。'); end if;
 end if;
 select coalesce(sum(coalesce(ae.night_hours,0)),0) into night_hours from public.attendance_entries ae
 where ae.company_id=cid and ae.worker_id=wid and ae.work_date between p_start and p_end and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
 and coalesce(ae.work_category,'day')='day' and coalesce(ae.night_hours,0)>0
 and not exists(select 1 from public.site_calculation_source_preferences pref where pref.company_id=cid and pref.site_id=ae.site_id and pref.output_type='payroll' and pref.source='trade_company');
 if night_hours>0 then warnings:=array_append(warnings,'通常勤務に夜間'||night_hours::text||'時間が登録されています。夜間時間だけの割増は現在の自動計算に含まれません。勤務区分と会社の夜間給与条件を確認してください。'); end if;
 if settings->>'pay_type'='monthly' then
 select string_agg(distinct case ae.work_category when 'night' then '夜勤' when 'holiday' then '休日勤務' when 'holiday_night' then '休日夜勤' else ae.work_category end,'・') into missing_categories
 from public.attendance_entries ae where ae.company_id=cid and ae.worker_id=wid and ae.work_date between p_start and p_end
 and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date and ae.work_category in ('night','holiday','holiday_night')
 and ((coalesce(ae.base_man_days,0)>0 and coalesce((settings->>(ae.work_category||'_daily'))::numeric,0)<=0)
 or (coalesce(ae.overtime_hours,0)>0 and coalesce((settings->>(ae.work_category||'_overtime'))::numeric,0)<=0)
 or (coalesce(ae.early_hours,0)>0 and coalesce((settings->>(ae.work_category||'_early'))::numeric,0)<=0))
 and not exists(select 1 from public.site_calculation_source_preferences pref where pref.company_id=cid and pref.site_id=ae.site_id and pref.output_type='payroll' and pref.source='trade_company');
 if missing_categories is not null then warnings:=array_append(warnings,'月給の'||missing_categories||'実績に未登録の単価があります。会社の追加支給条件と給与設定を確認してください。'); end if;
 end if;
 return warnings;
end $$;
revoke all on function private.payroll_condition_warnings(uuid,uuid,date,date) from public,anon,authenticated;


CREATE OR REPLACE FUNCTION private.ensure_monthly_payroll_drafts(
  p_day date default (current_timestamp at time zone 'Asia/Tokyo')::date
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
declare r record;
  current_day date:=(current_timestamp at time zone 'Asia/Tokyo')::date;
  month_end date:=(date_trunc('month',p_day)+interval '1 month - 1 day')::date;
begin
  -- Scheduler creates the current month only, never historical/future backfill.
  if p_day is null or date_trunc('month',p_day)<>date_trunc('month',current_day) then return; end if;
  for r in
    select s.company_id,s.worker_id
    from public.worker_payroll_settings s
    join public.workers w on w.id=s.worker_id and w.company_id=s.company_id
    join public.companies c on c.id=w.company_id
    where ((s.pay_type='monthly' and coalesce(s.monthly_salary_yen,0)>0)
      or exists(select 1 from public.paid_leave_requests pl
        where pl.company_id=s.company_id and pl.worker_id=s.worker_id and pl.status='approved'
          and pl.leave_date between date_trunc('month',p_day)::date and current_day))
      and w.status::text='active' and w.affiliation::text='employee'
      and (w.hire_date is null or w.hire_date<=month_end)
    order by s.company_id,s.worker_id
  loop
    perform private.refresh_automatic_payroll_internal(r.company_id,r.worker_id,p_day);
    perform private.sync_payroll_attendance_detail(r.company_id,r.worker_id,p_day);
  end loop;
end;
$$;
revoke all on function private.ensure_monthly_payroll_drafts(date)
from public,anon,authenticated;

