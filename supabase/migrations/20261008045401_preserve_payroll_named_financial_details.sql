-- Repair draft presentation only; retain existing gross/deductions/net calculations.
-- Finalized/manual statements stay untouched. No stored rows are rewritten.

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
    + round(coalesce((settings->>'resident_tax_monthly')::numeric,0))::integer
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

CREATE OR REPLACE FUNCTION private.apply_monthly_salary_detail()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.worker_payroll_settings%rowtype; category_base jsonb;
begin
  if not new.automatic_calculation or new.workflow_state<>'draft' then return new; end if;
  select * into s from public.worker_payroll_settings
  where company_id=new.company_id and worker_id=new.worker_id;
  if s.pay_type='monthly' then
    select coalesce(jsonb_object_agg(x.label,x.amount_yen),'{}'::jsonb)
    into category_base from (
      select case ae.work_category when 'night' then '夜勤基本給'
        when 'holiday' then '休日基本給' when 'holiday_night' then '休日夜勤基本給' end label,
        sum(round(coalesce(ae.base_man_days,0)*coalesce((to_jsonb(s)->>(ae.work_category||'_daily'))::numeric,0)))::integer amount_yen
      from public.attendance_entries ae
      where ae.company_id=new.company_id and ae.worker_id=new.worker_id
        and ae.work_date between new.period_start and new.period_end
        and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
        and ae.work_category in ('night','holiday','holiday_night')
        and not exists(select 1 from public.site_calculation_source_preferences pref
          where pref.company_id=ae.company_id and pref.site_id=ae.site_id
            and pref.output_type='payroll' and pref.source='trade_company')
      group by ae.work_category
    ) x;
    new.detail:=(coalesce(new.detail,'{}'::jsonb)-'夜勤基本給'-'休日基本給'-'休日夜勤基本給')
      ||category_base||jsonb_build_object(
      '基本給',round(coalesce(s.monthly_salary_yen,0))::integer,
      '給与方式','月給',
      '月固定給',round(coalesce(s.monthly_salary_yen,0))::integer,
      '計算用1日基本ベース',round(coalesce(s.calculation_daily_base_yen,0))::integer
    );
  end if;
  return new;
end $function$
;

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
