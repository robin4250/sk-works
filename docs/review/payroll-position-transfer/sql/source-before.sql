CREATE OR REPLACE FUNCTION private.sync_payroll_attendance_detail(cid uuid, wid uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  start_day date := date_trunc('month', day)::date;
  end_day date := (date_trunc('month', day) + interval '1 month - 1 day')::date;
  settings jsonb := '{}'::jsonb; checkout_common jsonb; allowance_settings jsonb;
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
  attendance_evidence jsonb := '[]'::jsonb;
begin
  select coalesce(to_jsonb(s),'{}'::jsonb)
  into settings
  from public.worker_payroll_settings s
  where s.company_id=cid and s.worker_id=wid;
  checkout_common:=payroll_unit_private.resolve_company_common(cid,wid,start_day,end_day);
  allowance_settings:=case when jsonb_typeof(checkout_common->'effective_settings')='object'
    then checkout_common->'effective_settings' else settings end;

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
    coalesce(sum(x.amount_yen),0)::integer,
    coalesce(jsonb_agg(jsonb_build_object('name',x.allowance_name,'section','earning',
      'unit','day','quantity',x.quantity,'rate_yen',x.rate_yen,'amount_yen',x.amount_yen)
      order by x.allowance_name) filter(where x.amount_yen<>0),'[]'::jsonb)
  into v_allowances,v_allowance_total,attendance_evidence
  from (
    select
      a.allowance_name,
      count(distinct ae.work_date) as quantity,
      case
        when nullif(trim(allowance_settings->>'allowance_name_1'),'')=a.allowance_name
          then coalesce((allowance_settings->>'allowance_1')::numeric,0)
        when nullif(trim(allowance_settings->>'allowance_name_2'),'')=a.allowance_name
          then coalesce((allowance_settings->>'allowance_2')::numeric,0)
        when nullif(trim(allowance_settings->>'allowance_name_3'),'')=a.allowance_name
          then coalesce((allowance_settings->>'allowance_3')::numeric,0)
        else 0 end as rate_yen,
      (
        count(distinct ae.work_date)
        * case
            when nullif(trim(allowance_settings->>'allowance_name_1'),'')=a.allowance_name
              then coalesce((allowance_settings->>'allowance_1')::numeric,0)
            when nullif(trim(allowance_settings->>'allowance_name_2'),'')=a.allowance_name
              then coalesce((allowance_settings->>'allowance_2')::numeric,0)
            when nullif(trim(allowance_settings->>'allowance_name_3'),'')=a.allowance_name
              then coalesce((allowance_settings->>'allowance_3')::numeric,0)
            else 0
          end
      )::integer as amount_yen
    from public.attendance_entries ae
    cross join lateral unnest(coalesce(ae.allowance_names,'{}'::text[])) a(allowance_name)
    where ae.company_id=cid
      and ae.worker_id=wid
      and ae.work_date between start_day and end_day
      and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
      and not company_checkout_allowance_private.covers_legacy(cid,wid,ae.work_date,
        case when nullif(trim(settings->>'allowance_name_1'),'')=a.allowance_name then 1
             when nullif(trim(settings->>'allowance_name_2'),'')=a.allowance_name then 2
             when nullif(trim(settings->>'allowance_name_3'),'')=a.allowance_name then 3 else 0 end)
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
      - v_allowance_total
      - coalesce((select (ps.detail->>'custom_earnings_total')::numeric from public.payroll_statements ps
        where ps.company_id=cid and ps.worker_id=wid and ps.period_start=start_day and ps.period_end=end_day
          and ps.automatic_calculation and ps.workflow_state='draft' limit 1),0),
    0
  );


  -- Display-only basis from precisely the same inputs as the existing sums.
  -- No row updates, totals, rounding rules or finalized-row guards are changed.
  attendance_evidence:=attendance_evidence||coalesce((
    select jsonb_agg(jsonb_build_object('name',q.name,'section','earning',
      'unit',q.unit,'category',q.category,'rate_yen',q.rate_yen,
      'quantity',q.quantity,'amount_yen',q.amount_yen) order by q.name,q.category)
    from (
      select k.name,k.unit,coalesce(ae.work_category,'day') category,
        coalesce((settings->>(coalesce(ae.work_category,'day')||k.rate_suffix))::numeric,0) rate_yen,
        sum(k.quantity) quantity,
        sum(round(k.quantity*coalesce((settings->>(coalesce(ae.work_category,'day')||k.rate_suffix))::numeric,0))) amount_yen
      from public.attendance_entries ae
      cross join lateral (values
        ('基本給','day','_daily',coalesce(ae.base_man_days,0)),
        ('残業手当','hour','_overtime',coalesce(ae.overtime_hours,0)),
        ('早出手当','hour','_early',coalesce(ae.early_hours,0))
      ) k(name,unit,rate_suffix,quantity)
      where ae.company_id=cid and ae.worker_id=wid
        and ae.work_date between start_day and end_day
        and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
        and not (coalesce(settings->>'pay_type','daily')='monthly' and coalesce(ae.work_category,'day')='day' and k.name='基本給')
        and not exists(select 1 from public.site_calculation_source_preferences pref
          where pref.company_id=ae.company_id and pref.site_id=ae.site_id
            and pref.output_type='payroll' and pref.source='trade_company')
      group by k.name,k.unit,k.rate_suffix,coalesce(ae.work_category,'day')
    ) q where q.amount_yen<>0
  ),'[]'::jsonb);
  if settings->>'pay_type'='monthly' then
    attendance_evidence:=attendance_evidence||jsonb_build_array(jsonb_build_object(
      'name','基本給','section','earning','unit','month','category','monthly',
      'rate_yen',round(coalesce((settings->>'monthly_salary_yen')::numeric,0)),
      'quantity',1,'amount_yen',round(coalesce((settings->>'monthly_salary_yen')::numeric,0))));
  end if;

  update public.payroll_statements ps
  set detail=
      (coalesce(ps.detail,'{}'::jsonb)-'その他支給')
      || jsonb_build_object(
        'attendance_unit_evidence',jsonb_build_object('contract_version',1,'blocked',false,
          'source','sync_payroll_attendance_detail','items',attendance_evidence),
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
$function$

