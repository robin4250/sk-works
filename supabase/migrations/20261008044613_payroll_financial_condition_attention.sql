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
end $$;
revoke all on function private.payroll_condition_warnings(uuid,uuid,date,date) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.refresh_generation_setting_issues(cid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  month_start date:=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date;
  active_keys text[]:='{}';
  r record;
  k text;
begin
  if cid is null then return; end if;

  for r in
    select distinct w.id,w.name
    from public.attendance_entries a
    join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
    left join public.worker_payroll_settings ps on ps.company_id=a.company_id and ps.worker_id=a.worker_id
    where a.company_id=cid and a.work_date>=month_start and ps.worker_id is null
    order by w.name
  loop
    k:='payroll:'||r.id::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(cid,k,'payroll','給与明細の設定未入力',r.name||'：個別給与設定が未入力です','payroll_settings',r.id);
  end loop;

  for r in
    select distinct s.id,s.name
    from public.attendance_entries a
    join public.sites s on s.id=a.site_id and s.company_id=a.company_id
    where a.company_id=cid and a.work_date>=month_start and s.customer_id is null
    order by s.name
  loop
    k:='invoice-customer:'||r.id::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(cid,k,'invoice','請求書の設定未入力',r.name||'：取引先が未入力です','admin_sites',r.id);
  end loop;

  for r in
    select distinct s.id,s.name
    from public.attendance_entries a
    join public.sites s on s.id=a.site_id and s.company_id=a.company_id
    left join public.site_financial_settings fs on fs.site_id=s.id and fs.company_id=s.company_id
    where a.company_id=cid and a.work_date>=month_start
      and (
       fs.site_id is null or
       ((case when coalesce(fs.billing_unit_price_yen,0)>0 then 1 else 0 end)
        +(case when coalesce(fs.billing_square_meter_unit_price_yen,0)>0 and coalesce(fs.billing_square_meter_quantity,0)>0 then 1 else 0 end)
        +(case when coalesce(fs.billing_contract_amount_yen,0)>0 then 1 else 0 end)
        +(case when coalesce(fs.billing_monthly_rate_yen,0)>0 then 1 else 0 end))<>1
      )
      and not exists(select 1 from public.site_calculation_source_preferences pref
        join public.trade_companies tc on tc.id=pref.trade_company_id and tc.company_id=pref.company_id
        join public.trade_company_contracts ct on ct.trade_company_id=tc.id and ct.company_id=tc.company_id
        where pref.company_id=cid and pref.site_id=s.id and pref.output_type='invoice'
          and pref.source='trade_company' and coalesce(ct.contract_method,'none')<>'none')
    order by s.name
  loop
    k:='invoice-site:'||r.id::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(cid,k,'invoice','請求書の設定未入力',r.name||'：請求方式が未入力です','admin_sites',r.id);
  end loop;

  if exists(select 1 from public.attendance_entries a where a.company_id=cid and a.work_date>=month_start)
     and exists(select 1 from public.companies c where c.id=cid and (
       nullif(trim(coalesce(c.bank_name,'')),'') is null
       or nullif(trim(coalesce(c.bank_branch,'')),'') is null
       or nullif(trim(coalesce(c.bank_account_number,'')),'') is null
       or nullif(trim(coalesce(c.bank_account_holder,'')),'') is null
     ))
  then
    k:='invoice-bank:'||cid::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(cid,k,'invoice','請求書の設定未入力','請求書設定：振込口座が未入力です','settings',cid);
  end if;

  for r in
    select distinct pc.id,pc.name
    from public.attendance_entries a
    join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
    join public.partner_companies pc on pc.id=w.partner_company_id and pc.company_id=w.company_id
    left join public.partner_payment_settings pps on pps.company_id=pc.company_id and pps.partner_company_id=pc.id
    where a.company_id=cid and a.work_date>=month_start and pps.partner_company_id is null
    order by pc.name
  loop
    k:='payment:'||r.id::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(cid,k,'payment_certificate','支払証明書の設定未入力',r.name||'：支払証明書設定が未入力です','payment_certificate_settings',r.id);
  end loop;

  -- Reuse the existing issue lifecycle and notification dedupe for actual draft periods.
  for r in
    with periods as (
      select ps.worker_id,ps.period_start,ps.period_end from public.payroll_statements ps
      where ps.company_id=cid and ps.workflow_state='draft' and ps.automatic_calculation
      union
      select pl.worker_id,date_trunc('month',pl.leave_date)::date,
        (date_trunc('month',pl.leave_date)+interval '1 month - 1 day')::date
      from public.paid_leave_requests pl where pl.company_id=cid and pl.status='approved'
        and pl.leave_date<=(now() at time zone 'Asia/Tokyo')::date
        and not exists(select 1 from public.payroll_statements ps where ps.company_id=cid
          and ps.worker_id=pl.worker_id and pl.leave_date between ps.period_start and ps.period_end)
    )
    select p.worker_id,w.name,p.period_start,p.period_end,
      private.payroll_condition_warnings(cid,p.worker_id,p.period_start,p.period_end) as messages
    from periods p join public.workers w on w.id=p.worker_id and w.company_id=cid
  loop
    if cardinality(r.messages)>0 then
      k:='payroll-condition:'||r.worker_id::text||':'||r.period_start::text;
      active_keys:=array_append(active_keys,k);
      perform private.upsert_generation_setting_issue(cid,k,'payroll','給与条件の確認が必要です',
        r.name||'（'||to_char(r.period_start,'YYYY年MM月')||'）：'||array_to_string(r.messages,E'\n'),'payroll_settings',r.worker_id);
    end if;
  end loop;

  update public.generation_setting_issues
  set resolved_at=now(),updated_at=now()
  where company_id=cid and resolved_at is null and not (issue_key=any(active_keys));
end;
$function$;

create or replace function private.payroll_document_metadata(p_statement_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
 'calculation_warnings',case when ps.workflow_state='draft' and ps.automatic_calculation then to_jsonb(private.payroll_condition_warnings(ps.company_id,ps.worker_id,ps.period_start,ps.period_end)) else '[]'::jsonb end,
 'pay_type',case
 when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('monthly','月給') then 'monthly'
 when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('hourly','時給') then 'hourly'
 when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('daily','日給') then 'daily'
 else coalesce(pay_settings.pay_type,'daily') end,
 'rate_formula',coalesce(nullif(ps.detail->'rate_formula','null'::jsonb),pay_settings.rate_formula,'{}'::jsonb),
 'hourly_rate_yen',coalesce(nullif(ps.detail->'hourly_rate_yen','null'::jsonb),to_jsonb(pay_settings.hourly_rate_yen),'0'::jsonb),
 '社員番号',coalesce(nullif(ps.detail->>'社員番号',''),w.employee_number,''),
 '所属',coalesce(nullif(ps.detail->>'所属',''),w.department,''),
 '職種',coalesce(nullif(ps.detail->>'職種',''),w.role,''),
 '入社日',coalesce(nullif(ps.detail->>'入社日',''),w.hire_date::text,''),
 'payment_date',private.payroll_payment_date(ps.period_end,ps.company_id,case when ps.workflow_state='draft' then '{}'::jsonb else ps.detail end),
 '支払日',c.payroll_payment_day,
 'payroll_confirmations',coalesce((select jsonb_agg(jsonb_build_object('user_id',pc.user_id,'name',coalesce(nullif(up.display_name,''),'SKOユーザー'),'position',pc.position,
 'confirmed_at',case when rv.confirmed_revision=ps.revision then rv.confirmed_at end) order by pc.position)
 from public.payroll_confirmers pc left join public.user_profiles up on up.user_id=pc.user_id left join public.payroll_statement_reviews rv on rv.statement_id=ps.id and rv.reviewer_id=pc.user_id
 where pc.company_id=ps.company_id),'[]'::jsonb))
 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id join public.companies c on c.id=ps.company_id left join public.worker_payroll_settings pay_settings on pay_settings.worker_id=ps.worker_id and pay_settings.company_id=ps.company_id where ps.id=p_statement_id
$$;

-- Paid-leave approvals also change the conditions reported by the existing issue pipeline.
drop trigger if exists paid_leave_refresh_generation_setting_issues on public.paid_leave_requests;
create trigger paid_leave_refresh_generation_setting_issues
 after insert or update or delete on public.paid_leave_requests
 for each row execute function private.refresh_generation_setting_issues_trigger();
