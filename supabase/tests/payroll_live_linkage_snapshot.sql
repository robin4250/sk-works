-- Read-only production function snapshot 2026-10-08 for disposable regression only.
-- Do not apply this test fixture to Supabase. New migrations override these functions.
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
    and ae.work_date between start_day and end_day;

  select coalesce(count(*),0)
  into v_paid_leave
  from public.paid_leave_requests pl
  where pl.company_id=cid
    and pl.worker_id=wid
    and pl.leave_date between start_day and end_day
    and pl.status='approved';

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