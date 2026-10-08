-- Forward-only overlap prevention. Approved history and actual review timestamps are never rewritten.
CREATE OR REPLACE FUNCTION public.decide_paid_leave_request(p_batch_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_requested_by uuid;
  v_worker_id uuid;
  v_status text;
  v_granted numeric := 0;
  v_used numeric := 0;
  v_batch_count numeric := 0;
begin
  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision';
  end if;

  select r.company_id, r.requested_by, r.worker_id
  into v_company_id, v_requested_by, v_worker_id
  from public.paid_leave_requests r
  where r.batch_id = p_batch_id
    and r.status = 'pending'
  limit 1
  for update;

  if v_company_id is null then
    raise exception 'pending paid leave request not found';
  end if;

  if not exists (
    select 1
    from public.company_members cm
    where cm.company_id = v_company_id
      and cm.user_id = v_actor
      and cm.role::text in ('owner','admin','manager')
  ) then
    raise exception 'management permission required';
  end if;

  if p_decision = 'approve' then
    -- Approval and attendance writers can serialize on the same worker row.
    perform 1 from public.workers w where w.id=v_worker_id and w.company_id=v_company_id for update;
    perform 1 from public.paid_leave_requests r where r.batch_id=p_batch_id
      and r.company_id=v_company_id and r.worker_id=v_worker_id and r.status='pending'
      order by r.leave_date,r.id for update;
    if exists (
      select 1 from public.paid_leave_requests r join public.attendance_entries ae
        on ae.company_id=r.company_id and ae.worker_id=r.worker_id and ae.work_date=r.leave_date
      where r.batch_id=p_batch_id and r.company_id=v_company_id
        and r.worker_id=v_worker_id and r.status='pending'
    ) then
      raise exception 'attendance exists for requested paid leave, use attendance correction first';
    end if;
    select coalesce(wps.paid_leave_granted_days, 0)
    into v_granted
    from public.worker_payroll_settings wps
    where wps.worker_id = v_worker_id and wps.company_id=v_company_id
    limit 1;
    v_granted := coalesce(v_granted, 0);

    select count(*)
    into v_used
    from public.paid_leave_requests r
    where r.worker_id = v_worker_id and r.company_id=v_company_id
      and r.status = 'approved';

    select count(*)
    into v_batch_count
    from public.paid_leave_requests r
    where r.batch_id = p_batch_id and r.company_id=v_company_id and r.worker_id=v_worker_id
      and r.status = 'pending';

    if v_used + v_batch_count > v_granted then
      raise exception 'paid leave balance exceeded';
    end if;

    v_status := 'approved';
  else
    v_status := 'rejected';
  end if;

  update public.paid_leave_requests
  set status = v_status,
      reviewed_by = v_actor,
      reviewed_at = now(),
      review_note = nullif(trim(coalesce(p_note,'')), ''),
      updated_at = now()
  where batch_id = p_batch_id and company_id=v_company_id and worker_id=v_worker_id
    and status = 'pending';

  perform private.enqueue_notification(
    v_company_id,
    v_requested_by,
    case when v_status = 'approved' then 'approval' else 'warning' end,
    case when v_status = 'approved'
      then '有給申請が承認されました'
      else '有給申請が却下されました'
    end,
    case when v_status = 'approved'
      then '申請した有給が承認されました。出勤表に反映されます。'
      else '有給申請が却下されました。内容を確認してください。'
    end,
    'paid_leave_request',
    p_batch_id
  );

  return v_status;
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

  select coalesce(
    jsonb_object_agg(trim(item->>'name'), -greatest(coalesce((item->>'amount_yen')::integer,0),0))
      filter (where nullif(trim(item->>'name'),'') is not null and coalesce((item->>'amount_yen')::integer,0) <> 0),
    '{}'::jsonb
  )
  into v_custom_deduction_detail
  from jsonb_array_elements(coalesce(settings->'custom_deductions','[]'::jsonb)) item;

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

  v_other_earnings := greatest(
    v_gross
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
      coalesce(ps.detail,'{}'::jsonb)
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
      where pl.company_id=cid and pl.worker_id=wid and pl.leave_date between start_day and end_day),'')||
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

  -- A registered positive monthly salary is payable independently of attendance.
  -- Daily/hourly empty-month behavior is unchanged; no paid-leave amount is invented.
  if count_rows=0 and not (coalesce(settings->>'pay_type','daily')='monthly'
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
