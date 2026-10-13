-- Keep payment certificate detail fallback aligned with the shared total multipliers.
create or replace function public.payment_certificate_detail_rows(p_certificate_id uuid)
returns table(
  site_name text,
  work_content text,
  quantity_label text,
  unit_price_yen integer,
  amount_yen integer
)
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_uid uuid:=auth.uid();
  v_company_id uuid;
  v_partner_id uuid;
  v_start date;
  v_end date;
  settings public.partner_payment_settings%rowtype;
  hours_per_day numeric:=8;
  overtime_mul numeric:=1.25;
  early_mul numeric:=1.25;
  night_mul numeric:=1.5;
  night_ot_mul numeric:=1.5;
  holiday_mul numeric:=1.35;
  holiday_ot_mul numeric:=1.35;
  holiday_night_mul numeric:=1.6;
  holiday_night_ot_mul numeric:=1.6;
  r_daily integer:=0;
  r_ot integer:=0;
  r_early integer:=0;
  r_night integer:=0;
  r_night_ot integer:=0;
  r_holiday integer:=0;
  r_holiday_ot integer:=0;
  r_holiday_night integer:=0;
  r_holiday_night_ot integer:=0;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select pc.company_id,pc.partner_company_id,pc.period_start,pc.period_end
    into v_company_id,v_partner_id,v_start,v_end
  from public.payment_certificates pc where pc.id=p_certificate_id;
  if v_company_id is null then raise exception 'payment certificate not found'; end if;

  if not exists(
    select 1 from public.company_members cm
    where cm.company_id=v_company_id and cm.user_id=v_uid
      and cm.role::text in ('owner','admin','manager')
  ) then raise exception 'payment certificate permission required'; end if;

  select * into settings from public.partner_payment_settings
  where company_id=v_company_id and partner_company_id=v_partner_id;

  hours_per_day:=greatest(coalesce((settings.rate_formula->>'hours_per_day')::numeric,8),0.01);
  overtime_mul:=coalesce((settings.rate_formula->>'overtime_multiplier')::numeric,1.25);
  early_mul:=coalesce((settings.rate_formula->>'early_multiplier')::numeric,1.25);
  night_mul:=coalesce((settings.rate_formula->>'night_multiplier')::numeric,1.5);
  night_ot_mul:=coalesce((settings.rate_formula->>'night_overtime_multiplier')::numeric,1.5);
  holiday_mul:=coalesce((settings.rate_formula->>'holiday_multiplier')::numeric,1.35);
  holiday_ot_mul:=coalesce((settings.rate_formula->>'holiday_overtime_multiplier')::numeric,1.35);
  holiday_night_mul:=coalesce((settings.rate_formula->>'holiday_night_multiplier')::numeric,1.6);
  holiday_night_ot_mul:=coalesce((settings.rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.6);

  r_daily:=coalesce(settings.daily_rate_yen,0);
  r_ot:=case when coalesce(settings.overtime_hour_rate_yen,0)>0
    then settings.overtime_hour_rate_yen else round(r_daily/hours_per_day*overtime_mul) end;
  r_early:=case when coalesce(settings.early_hour_rate_yen,0)>0
    then settings.early_hour_rate_yen else round(r_daily/hours_per_day*early_mul) end;
  r_night:=case when coalesce(settings.night_day_rate_yen,0)>0
    then settings.night_day_rate_yen else round(r_daily*night_mul) end;
  r_night_ot:=case when coalesce(settings.night_overtime_hour_rate_yen,0)>0
    then settings.night_overtime_hour_rate_yen else round(r_daily/hours_per_day*night_ot_mul) end;
  r_holiday:=case when coalesce(settings.holiday_day_rate_yen,0)>0
    then settings.holiday_day_rate_yen else round(r_daily*holiday_mul) end;
  r_holiday_ot:=case when coalesce(settings.holiday_overtime_hour_rate_yen,0)>0
    then settings.holiday_overtime_hour_rate_yen else round(r_daily/hours_per_day*holiday_ot_mul) end;
  r_holiday_night:=case when coalesce(settings.holiday_night_day_rate_yen,0)>0
    then settings.holiday_night_day_rate_yen else round(r_daily*holiday_night_mul) end;
  r_holiday_night_ot:=case when coalesce(settings.holiday_night_overtime_hour_rate_yen,0)>0
    then settings.holiday_night_overtime_hour_rate_yen
    else round(r_daily/hours_per_day*holiday_night_ot_mul) end;

  return query
  with source as (
    select
      coalesce(nullif(s.formal_name,''),s.name,'現場未設定') as site_name,
      coalesce(a.work_category,'day') as work_category,
      sum(coalesce(a.base_man_days,0)) as man_days,
      sum(coalesce(a.overtime_hours,0)) as overtime_hours,
      sum(coalesce(a.early_hours,0)) as early_hours
    from public.attendance_entries a
    join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
    left join public.sites s on s.id=a.site_id and s.company_id=a.company_id
    where a.company_id=v_company_id
      and w.partner_company_id=v_partner_id
      and a.work_date between v_start and v_end
    group by
      coalesce(nullif(s.formal_name,''),s.name,'現場未設定'),
      coalesce(a.work_category,'day')
  ),
  base_lines as (
    select site_name,
      case work_category
        when 'night' then '夜勤'
        when 'holiday' then '休日出勤'
        when 'holiday_night' then '休日夜勤'
        else '通常作業'
      end as work_content,
      trim(to_char(man_days,'FM999999990.##'))||'人' as quantity_label,
      case work_category
        when 'night' then r_night
        when 'holiday' then r_holiday
        when 'holiday_night' then r_holiday_night
        else r_daily
      end as unit_price_yen,
      round(man_days * case work_category
        when 'night' then r_night
        when 'holiday' then r_holiday
        when 'holiday_night' then r_holiday_night
        else r_daily
      end)::integer as amount_yen,
      1 as sort_order
    from source where man_days<>0
    union all
    select site_name,
      case work_category
        when 'night' then '夜勤残業'
        when 'holiday' then '休日残業'
        when 'holiday_night' then '休日夜勤残業'
        else '残業'
      end,
      trim(to_char(overtime_hours,'FM999999990.##'))||'H',
      case work_category
        when 'night' then r_night_ot
        when 'holiday' then r_holiday_ot
        when 'holiday_night' then r_holiday_night_ot
        else r_ot
      end,
      round(overtime_hours * case work_category
        when 'night' then r_night_ot
        when 'holiday' then r_holiday_ot
        when 'holiday_night' then r_holiday_night_ot
        else r_ot
      end)::integer,
      2
    from source where overtime_hours<>0
    union all
    select site_name,'早出',
      trim(to_char(early_hours,'FM999999990.##'))||'H',
      case work_category
        when 'night' then r_night_ot
        when 'holiday' then r_holiday_ot
        when 'holiday_night' then r_holiday_night_ot
        else r_early
      end,
      round(early_hours * case work_category
        when 'night' then r_night_ot
        when 'holiday' then r_holiday_ot
        when 'holiday_night' then r_holiday_night_ot
        else r_early
      end)::integer,
      3
    from source where early_hours<>0
  ),
  allowance_lines as (
    select
      coalesce(nullif(s.formal_name,''),s.name,'現場未設定') as site_name,
      '（'||cfg.name||'）'::text as work_content,
      count(*)::text||'回' as quantity_label,
      cfg.amount_yen::integer as unit_price_yen,
      (count(*)*cfg.amount_yen)::integer as amount_yen,
      4 as sort_order
    from public.attendance_entries a
    join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
    left join public.sites s on s.id=a.site_id and s.company_id=a.company_id
    cross join lateral unnest(coalesce(a.allowance_names,'{}'::text[])) n(name)
    join lateral (
      select
        x->>'name' as name,
        greatest(coalesce((x->>'amount_yen')::integer,0),0) as amount_yen
      from jsonb_array_elements(coalesce(settings.allowances,'[]'::jsonb)) x
      where x->>'name'=n.name
    ) cfg on true
    where a.company_id=v_company_id
      and w.partner_company_id=v_partner_id
      and a.work_date between v_start and v_end
      and cfg.amount_yen>0
    group by coalesce(nullif(s.formal_name,''),s.name,'現場未設定'),cfg.name,cfg.amount_yen
  ),
  pre_totals as (
    select coalesce(sum(amount_yen),0)::integer as subtotal
    from (
      select amount_yen from base_lines
      union all
      select amount_yen from allowance_lines
    ) q
  ),
  summary_lines as (
    select '〃'::text as site_name,'福利厚生費'::text as work_content,
      trim(to_char(settings.welfare_rate,'FM999999990.##'))||'%' as quantity_label,
      0::integer as unit_price_yen,
      round(p.subtotal*coalesce(settings.welfare_rate,0)/100)::integer as amount_yen,
      90 as sort_order
    from pre_totals p where coalesce(settings.welfare_rate,0)>0
    union all
    select '〃','消費税',
      trim(to_char(settings.tax_rate,'FM999999990.##'))||'%',
      0,
      round((p.subtotal + round(p.subtotal*coalesce(settings.welfare_rate,0)/100))
        *coalesce(settings.tax_rate,10)/100)::integer,
      91
    from pre_totals p where coalesce(settings.tax_rate,0)>0
  ),
  lines as (
    select * from base_lines
    union all select * from allowance_lines
    union all select * from summary_lines
  )
  select l.site_name,l.work_content,l.quantity_label,l.unit_price_yen,l.amount_yen
  from lines l
  order by l.site_name,l.sort_order,l.work_content;
end
$$;
