-- Code-only read-only function snapshot, 2026-10-09. Never apply to production.
-- No company/person data, credentials, or connection settings.
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
end $function$;

CREATE OR REPLACE FUNCTION private.apply_monthly_salary_to_statement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.worker_payroll_settings%rowtype; regular_day_base integer:=0;
begin
  if not new.automatic_calculation or new.workflow_state<>'draft' then return new; end if;
  select * into s from public.worker_payroll_settings where company_id=new.company_id and worker_id=new.worker_id;
  if s.pay_type<>'monthly' then return new; end if;
  select coalesce(round(sum(coalesce(ae.base_man_days,0)*coalesce(s.day_daily,0))),0)::integer
  into regular_day_base from public.attendance_entries ae
  where ae.company_id=new.company_id and ae.worker_id=new.worker_id
    and ae.work_date between new.period_start and new.period_end
    and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    and coalesce(ae.work_category,'day')='day';
  new.gross_pay:=greatest(coalesce(new.gross_pay,0)-regular_day_base+round(coalesce(s.monthly_salary_yen,0))::integer,0);
  new.net_pay:=greatest(new.gross_pay-coalesce(new.deductions,0),0);
  new.detail:=coalesce(new.detail,'{}'::jsonb)||jsonb_build_object(
    '給与方式','月給','月固定給',round(coalesce(s.monthly_salary_yen,0))::integer,
    '計算用1日基本ベース',round(coalesce(s.calculation_daily_base_yen,0))::integer);
  return new;
end $function$;

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
$function$;

CREATE OR REPLACE FUNCTION private.attendance_refresh_payroll()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if tg_op<>'INSERT' then perform private.refresh_automatic_payroll(old.company_id,old.worker_id,old.work_date); end if;
 if tg_op<>'DELETE' then perform private.refresh_automatic_payroll(new.company_id,new.worker_id,new.work_date); end if;
 return null;
end;
$function$;

CREATE OR REPLACE FUNCTION private.attendance_sync_payroll_detail()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op <> 'INSERT' then
    perform private.sync_payroll_attendance_detail(old.company_id,old.worker_id,old.work_date);
  end if;
  if tg_op <> 'DELETE' then
    perform private.sync_payroll_attendance_detail(new.company_id,new.worker_id,new.work_date);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION private.ensure_monthly_payroll_drafts(p_day date DEFAULT ((CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Tokyo'::text))::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    where s.pay_type='monthly' and coalesce(s.monthly_salary_yen,0)>0
      and w.status::text='active' and w.affiliation::text='employee'
      and (w.hire_date is null or w.hire_date<=month_end)
    order by s.company_id,s.worker_id
  loop
    perform private.refresh_automatic_payroll_internal(r.company_id,r.worker_id,p_day);
    perform private.sync_payroll_attendance_detail(r.company_id,r.worker_id,p_day);
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION private.paid_leave_sync_payroll_detail()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op <> 'INSERT' then
    perform private.sync_payroll_attendance_detail(old.company_id,old.worker_id,old.leave_date);
  end if;
  if tg_op <> 'DELETE' then
    perform private.sync_payroll_attendance_detail(new.company_id,new.worker_id,new.leave_date);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION private.payroll_condition_warnings(cid uuid, wid uuid, p_start date, p_end date)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare settings jsonb; warnings text[]:='{}'; leave_count int; night_hours numeric; missing_categories text;
begin
 select to_jsonb(s) into settings from public.worker_payroll_settings s where s.company_id=cid and s.worker_id=wid;
 if settings is null then return warnings; end if;
 if coalesce(settings->>'pay_type','daily') in ('daily','hourly') then
 select count(*) into leave_count from public.paid_leave_requests pl where pl.company_id=cid and pl.worker_id=wid and pl.status='approved'
 and pl.leave_date between p_start and p_end and pl.leave_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
 and not exists(select 1 from public.attendance_entries ae where ae.company_id=pl.company_id and ae.worker_id=pl.worker_id and ae.work_date=pl.leave_date
 and (coalesce(ae.base_man_days,0)>0 or coalesce(ae.overtime_hours,0)>0 or coalesce(ae.early_hours,0)>0 or coalesce(ae.night_hours,0)>0));
 if leave_count>0 then warnings:=array_append(warnings,'有給'||leave_count::text||'日：日給・時給の有給支給額は現在の自動計算に含まれていません。会社の有給給与条件と支給額を確認してください。'); end if;
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
end $function$;

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

CREATE OR REPLACE FUNCTION private.settings_refresh_payroll()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m date;
begin
  for m in
    select distinct month_start from (
      select date_trunc('month',work_date)::date as month_start
      from public.attendance_entries
      where company_id=new.company_id and worker_id=new.worker_id
      union
      select period_start from public.payroll_statements
      where company_id=new.company_id and worker_id=new.worker_id
      union
      select date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date
      where new.pay_type='monthly' and coalesce(new.monthly_salary_yen,0)>0
        and exists(select 1 from public.workers w where w.id=new.worker_id
          and w.company_id=new.company_id and w.status::text='active'
          and w.affiliation::text='employee')
    ) months order by month_start
  loop
    perform private.refresh_automatic_payroll(new.company_id,new.worker_id,m);
    perform private.sync_payroll_attendance_detail(new.company_id,new.worker_id,m);
  end loop;
  return null;
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
