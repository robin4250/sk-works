-- Correct shared combined multipliers and payment-certificate automatic rates.

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
  holiday_night_ot text:=trim(to_char(coalesce((f->>'holiday_night_overtime_multiplier')::numeric,1.5),'FM999990.###'));
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
 holiday_night_ot_mul numeric:=1.5;
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
 holiday_night_ot_mul:=coalesce((settings.rate_formula->>'holiday_night_overtime_multiplier')::numeric,1.5);

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
  holiday_night_ot numeric:=coalesce((f->>'holiday_night_overtime_multiplier')::numeric,1.5);
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

