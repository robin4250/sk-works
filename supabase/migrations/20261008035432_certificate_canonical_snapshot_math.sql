-- Canonical rounded rows and immutable document snapshots; no historical amount updates.
CREATE OR REPLACE FUNCTION private.certificate_calculation_rows(v_company_id uuid, v_partner_id uuid, v_start date, v_end date)
 RETURNS TABLE(site_name text, work_content text, quantity_label text, unit_price_yen integer, amount_yen integer)
 LANGUAGE plpgsql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
declare
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
  r_night_early integer:=0;
  r_holiday_early integer:=0;
  r_holiday_night_early integer:=0;
begin
  select * into settings from public.partner_payment_settings
  where company_id=v_company_id and partner_company_id=v_partner_id;

  r_daily:=private.resolve_rate_formula(coalesce(settings.daily_rate_yen,0),settings.rate_formula,'{}'::jsonb,'daily')::integer;
  r_ot:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('overtime',coalesce(settings.overtime_hour_rate_yen,0)),
    'overtime'
  )::integer;
  r_early:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('early',coalesce(settings.early_hour_rate_yen,0)),
    'early'
  )::integer;
  r_night:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('night',coalesce(settings.night_day_rate_yen,0)),
    'night'
  )::integer;
  r_night_ot:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('night_overtime',coalesce(settings.night_overtime_hour_rate_yen,0)),
    'night_overtime'
  )::integer;
  r_holiday:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('holiday',coalesce(settings.holiday_day_rate_yen,0)),
    'holiday'
  )::integer;
  r_holiday_ot:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('holiday_overtime',coalesce(settings.holiday_overtime_hour_rate_yen,0)),
    'holiday_overtime'
  )::integer;
  r_holiday_night:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('holiday_night',coalesce(settings.holiday_night_day_rate_yen,0)),
    'holiday_night'
  )::integer;
  r_holiday_night_ot:=private.resolve_rate_formula(
    r_daily,settings.rate_formula,
    jsonb_build_object('holiday_night_overtime',coalesce(settings.holiday_night_overtime_hour_rate_yen,0)),
    'holiday_night_overtime'
  )::integer;

  -- Early work uses the independently registered early multiplier in every category.
  -- A positive direct early rate overrides every category consistently.
  hours_per_day:=greatest(coalesce((settings.rate_formula->>'hours_per_day')::numeric,8),0.01);
  early_mul:=coalesce((settings.rate_formula->>'early_multiplier')::numeric,1.25);
  r_night_early:=case when coalesce(settings.early_hour_rate_yen,0)>0
    then settings.early_hour_rate_yen else round(r_night/hours_per_day*early_mul)::integer end;
  r_holiday_early:=case when coalesce(settings.early_hour_rate_yen,0)>0
    then settings.early_hour_rate_yen else round(r_holiday/hours_per_day*early_mul)::integer end;
  r_holiday_night_early:=case when coalesce(settings.early_hour_rate_yen,0)>0
    then settings.early_hour_rate_yen else round(r_holiday_night/hours_per_day*early_mul)::integer end;

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
    select src.site_name,
      case src.work_category
        when 'night' then '夜勤'
        when 'holiday' then '休日出勤'
        when 'holiday_night' then '休日夜勤'
        else '通常作業'
      end as work_content,
      trim_scale(src.man_days)::text||'人' as quantity_label,
      case src.work_category
        when 'night' then r_night
        when 'holiday' then r_holiday
        when 'holiday_night' then r_holiday_night
        else r_daily
      end as unit_price_yen,
      round(src.man_days * case src.work_category
        when 'night' then r_night
        when 'holiday' then r_holiday
        when 'holiday_night' then r_holiday_night
        else r_daily
      end)::integer as amount_yen,
      1 as sort_order
    from source src where man_days<>0
    union all
    select src.site_name,
      case src.work_category
        when 'night' then '夜勤残業'
        when 'holiday' then '休日残業'
        when 'holiday_night' then '休日夜勤残業'
        else '残業'
      end,
      trim_scale(src.overtime_hours)::text||'H',
      case src.work_category
        when 'night' then r_night_ot
        when 'holiday' then r_holiday_ot
        when 'holiday_night' then r_holiday_night_ot
        else r_ot
      end,
      round(src.overtime_hours * case src.work_category
        when 'night' then r_night_ot
        when 'holiday' then r_holiday_ot
        when 'holiday_night' then r_holiday_night_ot
        else r_ot
      end)::integer,
      2
    from source src where overtime_hours<>0
    union all
    select src.site_name,'早出',
      trim_scale(src.early_hours)::text||'H',
      case src.work_category
        when 'night' then r_night_early
        when 'holiday' then r_holiday_early
        when 'holiday_night' then r_holiday_night_early
        else r_early
      end,
      round(src.early_hours * case src.work_category
        when 'night' then r_night_early
        when 'holiday' then r_holiday_early
        when 'holiday_night' then r_holiday_night_early
        else r_early
      end)::integer,
      3
    from source src where early_hours<>0
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
    select coalesce(sum(q.amount_yen),0)::integer as subtotal
    from (
      select bl.amount_yen from base_lines bl
      union all
      select al.amount_yen from allowance_lines al
    ) q
  ),
  summary_lines as (
    select '〃'::text as site_name,'福利厚生費'::text as work_content,
      trim_scale(settings.welfare_rate)::text||'%' as quantity_label,
      0::integer as unit_price_yen,
      round(p.subtotal*coalesce(settings.welfare_rate,0)/100)::integer as amount_yen,
      90 as sort_order
    from pre_totals p where coalesce(settings.welfare_rate,0)>0
    union all
    select '〃','消費税',
      trim_scale(settings.tax_rate)::text||'%',
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
 calculation_rows jsonb;
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

 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb),coalesce(sum(r.amount_yen),0)
 into calculation_rows,gross
 from private.certificate_calculation_rows(cid,partner,first_day,last_day) r;

 snapshot_value:=jsonb_build_object(
   'partner_company_name',coalesce(partner_name,''),
   'period_start',first_day,'period_end',last_day,
   'attendance_count',attendance_count,
   'settings_missing',settings.partner_company_id is null,
   'rate_formula',coalesce(settings.rate_formula,'{}'::jsonb),
   'welfare_rate',coalesce(settings.welfare_rate,0),
   'tax_rate',coalesce(settings.tax_rate,10),
   'calculation_rows',calculation_rows,
   'calculation_version',2
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


CREATE OR REPLACE FUNCTION public.payment_certificate_detail_rows(p_certificate_id uuid)
RETURNS TABLE(site_name text,work_content text,quantity_label text,unit_price_yen integer,amount_yen integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
declare c public.payment_certificates%rowtype;
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 select pc.* into c from public.payment_certificates pc where pc.id=p_certificate_id;
 if c.id is null then raise exception 'payment certificate not found'; end if;
 if not exists(select 1 from public.company_members cm where cm.company_id=c.company_id
   and cm.user_id=auth.uid() and cm.role::text in ('owner','admin','manager'))
 then raise exception 'payment certificate permission required'; end if;
 if jsonb_typeof(c.snapshot->'calculation_rows')='array' then
   return query select r.site_name,r.work_content,r.quantity_label,r.unit_price_yen,r.amount_yen
   from jsonb_to_recordset(c.snapshot->'calculation_rows')
   as r(site_name text,work_content text,quantity_label text,unit_price_yen integer,amount_yen integer);
 elsif c.status<>'draft' or not c.automatic_calculation then
   -- Historical documents lack frozen rows. Preserve their recorded amount;
   -- never reconstruct historical detail from today's rates or attendance.
   return query select '工事代金（保存済み）'::text,''::text,''::text,0,c.gross_amount;
 else
   return query select r.site_name,r.work_content,r.quantity_label,r.unit_price_yen,r.amount_yen
   from private.certificate_calculation_rows(c.company_id,c.partner_company_id,c.period_start,c.period_end) r;
 end if;
end
$function$;
revoke all on function private.certificate_calculation_rows(uuid,uuid,date,date) from public,anon,authenticated;
revoke all on function public.payment_certificate_detail_rows(uuid) from public,anon;
grant execute on function public.payment_certificate_detail_rows(uuid) to authenticated;
