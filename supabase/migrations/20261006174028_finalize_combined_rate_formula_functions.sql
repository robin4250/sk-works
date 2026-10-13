-- Final shared rate formulas: combined multipliers are totals, not stacked multipliers.

CREATE OR REPLACE FUNCTION private.rate_formula_label(p_formula jsonb, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  f jsonb:=coalesce(p_formula,'{}'::jsonb);
  h text:=trim(to_char(coalesce((f->>'hours_per_day')::numeric,8),'FM999990.###'));
  ot text:=trim(to_char(coalesce((f->>'overtime_multiplier')::numeric,1.25),'FM999990.###'));
  early text:=trim(to_char(coalesce((f->>'early_multiplier')::numeric,1.25),'FM999990.###'));
  night text:=trim(to_char(coalesce((f->>'night_multiplier')::numeric,1.5),'FM999990.###'));
  night_ot text:=trim(to_char(coalesce((f->>'night_overtime_multiplier')::numeric,1.5),'FM999990.###'));
  holiday text:=trim(to_char(coalesce((f->>'holiday_multiplier')::numeric,1.35),'FM999990.###'));
  holiday_ot text:=trim(to_char(coalesce((f->>'holiday_overtime_multiplier')::numeric,1.35),'FM999990.###'));
  holiday_night text:=trim(to_char(coalesce((f->>'holiday_night_multiplier')::numeric,1.6),'FM999990.###'));
  holiday_night_ot text:=trim(to_char(coalesce((f->>'holiday_night_overtime_multiplier')::numeric,1.6),'FM999990.###'));
  base text:=case when f->>'base_mode'='hourly' then '時給' else '1日単価' end;
  hourly_prefix text:=case when f->>'base_mode'='hourly' then base else base||'÷'||h end;
  daily_prefix text:=case when f->>'base_mode'='hourly' then base||'×'||h else base end;
begin
  return case p_kind
    when 'daily' then daily_prefix
    when 'overtime' then hourly_prefix||'×'||ot
    when 'early' then hourly_prefix||'×'||early
    when 'night' then daily_prefix||'×'||night
    when 'night_overtime' then hourly_prefix||'×'||night_ot
    when 'holiday' then daily_prefix||'×'||holiday
    when 'holiday_overtime' then hourly_prefix||'×'||holiday_ot
    when 'holiday_night' then daily_prefix||'×'||holiday_night
    when 'holiday_night_overtime' then hourly_prefix||'×'||holiday_night_ot
    else base
  end;
end
$function$;

CREATE OR REPLACE FUNCTION private.refresh_automatic_payment_certificate(cid uuid, partner uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 first_day date:=date_trunc('month',day)::date;
 last_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
 existing public.payment_certificates%rowtype;
 settings public.partner_payment_settings%rowtype;
 attendance_count int:=0;
 gross numeric:=0;
 subtotal numeric:=0;
 welfare numeric:=0;
 tax numeric:=0;
 partner_name text;
 snapshot_value jsonb;
 s record;
 allowance_cfg record;
 allowance_qty numeric;
 allowance_rate numeric;
 hours_per_day numeric:=8;
 overtime_mul numeric:=1.25;
 early_mul numeric:=1.25;
 night_mul numeric:=1.5;
 night_ot_mul numeric:=1.5;
 holiday_mul numeric:=1.35;
 holiday_ot_mul numeric:=1.35;
 holiday_night_mul numeric:=1.6;
 holiday_night_ot_mul numeric:=1.6;
 r_daily numeric:=0;
 r_ot numeric:=0;
 r_early numeric:=0;
 r_night numeric:=0;
 r_night_ot numeric:=0;
 r_holiday numeric:=0;
 r_holiday_ot numeric:=0;
 r_holiday_night numeric:=0;
 r_holiday_night_ot numeric:=0;
begin
 if auth.uid() is null or partner is null then return; end if;
 perform pg_advisory_xact_lock(hashtextextended(
   'payment-certificate:'||cid::text||partner::text||first_day::text,0
 ));

 select * into existing
 from public.payment_certificates
 where company_id=cid and partner_company_id=partner
   and period_start=first_day and period_end=last_day
 for update;
 if found and (existing.status<>'draft' or not existing.automatic_calculation) then return; end if;

 select * into settings
 from public.partner_payment_settings
 where company_id=cid and partner_company_id=partner;

 select pc.name into partner_name
 from public.partner_companies pc
 where pc.id=partner and pc.company_id=cid;

 select count(*) into attendance_count
 from public.attendance_entries a
 join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
 where a.company_id=cid
   and w.partner_company_id=partner
   and a.work_date between first_day and last_day;

 if attendance_count=0 then
   if existing.id is not null and existing.status='draft'
      and existing.automatic_calculation then
     delete from public.payment_certificates where id=existing.id;
   end if;
   return;
 end if;

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

 select coalesce(sum(
   coalesce(a.base_man_days,0) *
     case coalesce(a.work_category,'day')
       when 'night' then r_night
       when 'holiday' then r_holiday
       when 'holiday_night' then r_holiday_night
       else r_daily
     end
   + coalesce(a.overtime_hours,0) *
     case coalesce(a.work_category,'day')
       when 'night' then r_night_ot
       when 'holiday' then r_holiday_ot
       when 'holiday_night' then r_holiday_night_ot
       else r_ot
     end
   + coalesce(a.early_hours,0) *
     case coalesce(a.work_category,'day')
       when 'night' then r_night_ot
       when 'holiday' then r_holiday_ot
       when 'holiday_night' then r_holiday_night_ot
       else r_early
     end
 ),0)
 into subtotal
 from public.attendance_entries a
 join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
 where a.company_id=cid
   and w.partner_company_id=partner
   and a.work_date between first_day and last_day;

 for allowance_cfg in
   select
     nullif(trim(x->>'name'),'') as name,
     greatest(coalesce((x->>'amount_yen')::numeric,0),0) as amount_yen
   from jsonb_array_elements(coalesce(settings.allowances,'[]'::jsonb)) x
 loop
   if allowance_cfg.name is null or allowance_cfg.amount_yen<=0 then continue; end if;
   select count(*)::numeric into allowance_qty
   from public.attendance_entries a
   join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
   cross join lateral unnest(coalesce(a.allowance_names,'{}'::text[])) n(name)
   where a.company_id=cid
     and w.partner_company_id=partner
     and a.work_date between first_day and last_day
     and n.name=allowance_cfg.name;
   subtotal:=subtotal+allowance_qty*allowance_cfg.amount_yen;
 end loop;

 welfare:=round(subtotal*coalesce(settings.welfare_rate,0)/100);
 tax:=round((subtotal+welfare)*coalesce(settings.tax_rate,10)/100);
 gross:=subtotal+welfare+tax;

 snapshot_value:=jsonb_build_object(
   'partner_company_name',coalesce(partner_name,''),
   'period_start',first_day,'period_end',last_day,
   'attendance_count',attendance_count,
   'settings_missing',settings.partner_company_id is null,
   'rate_formula',coalesce(settings.rate_formula,'{}'::jsonb),
   'welfare_rate',coalesce(settings.welfare_rate,0),
   'tax_rate',coalesce(settings.tax_rate,10)
 );

 if existing.id is null then
   insert into public.payment_certificates(
     company_id,partner_company_id,period_start,period_end,status,
     gross_amount,deductions,net_amount,snapshot,
     automatic_calculation,calculation_blocked
   )
   values(
     cid,partner,first_day,last_day,'draft',
     gross::int,0,gross::int,snapshot_value,true,false
   );
 elsif existing.gross_amount is distinct from gross::int
    or existing.net_amount is distinct from gross::int
    or existing.snapshot is distinct from snapshot_value
    or existing.calculation_blocked then
   update public.payment_certificates
   set gross_amount=gross::int,deductions=0,net_amount=gross::int,
       snapshot=snapshot_value,calculation_blocked=false,
       revision=revision+1,updated_at=now()
   where id=existing.id;
 end if;
end
$function$;

CREATE OR REPLACE FUNCTION private.resolve_rate_formula(p_base_rate numeric, p_formula jsonb, p_overrides jsonb, p_kind text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  f jsonb:=coalesce(p_formula,'{}'::jsonb);
  o jsonb:=coalesce(p_overrides,'{}'::jsonb);
  hours numeric:=greatest(coalesce((f->>'hours_per_day')::numeric,8),0.01);
  base_mode text:=coalesce(nullif(f->>'base_mode',''),'daily');
  hourly numeric;
  daily numeric;
  direct numeric:=coalesce((o->>p_kind)::numeric,0);
  ot numeric:=coalesce((f->>'overtime_multiplier')::numeric,1.25);
  early numeric:=coalesce((f->>'early_multiplier')::numeric,1.25);
  night numeric:=coalesce((f->>'night_multiplier')::numeric,1.5);
  night_ot numeric:=coalesce((f->>'night_overtime_multiplier')::numeric,1.5);
  holiday numeric:=coalesce((f->>'holiday_multiplier')::numeric,1.35);
  holiday_ot numeric:=coalesce((f->>'holiday_overtime_multiplier')::numeric,1.35);
  holiday_night numeric:=coalesce((f->>'holiday_night_multiplier')::numeric,1.6);
  holiday_night_ot numeric:=coalesce((f->>'holiday_night_overtime_multiplier')::numeric,1.6);
begin
  if direct>0 then return round(direct); end if;
  if base_mode='hourly' then
    hourly:=coalesce(nullif((f->>'hourly_rate_yen')::numeric,0),p_base_rate/hours,0);
    daily:=hourly*hours;
  else
    daily:=coalesce(p_base_rate,0);
    hourly:=daily/hours;
  end if;
  return round(case p_kind
    when 'daily' then daily
    when 'overtime' then hourly*ot
    when 'early' then hourly*early
    when 'night' then daily*night
    when 'night_overtime' then hourly*night_ot
    when 'holiday' then daily*holiday
    when 'holiday_overtime' then hourly*holiday_ot
    when 'holiday_night' then daily*holiday_night
    when 'holiday_night_overtime' then hourly*holiday_night_ot
    else 0
  end);
end
$function$;

CREATE OR REPLACE FUNCTION public.payment_certificate_detail_rows(p_certificate_id uuid)
 RETURNS TABLE(site_name text, work_content text, quantity_label text, unit_price_yen integer, amount_yen integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  night_ot_mul numeric:=1.25;
  holiday_mul numeric:=1.35;
  holiday_ot_mul numeric:=1.25;
  holiday_night_mul numeric:=1.6;
  holiday_night_ot_mul numeric:=1.25;
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
  night_ot_mul:=coalesce((settings.rate_formula->>'night_overtime_multiplier')::numeric,1.25);
  holiday_mul:=coalesce((settings.rate_formula->>'holiday_multiplier')::numeric,1.35);
  holiday_ot_mul:=coalesce((settings.rate_formula->>'holiday_overtime_multiplier')::numeric,1.25);
  holiday_night_mul:=coalesce((settings.rate_formula->>'holiday_night_multiplier')::numeric,1.6);
  holiday_night_ot_mul:=coalesce((settings.rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.25);

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
$function$;

