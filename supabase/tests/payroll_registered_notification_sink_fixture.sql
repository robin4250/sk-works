-- Actual metadata sink definitions, disposable local fixture only.
drop function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid);
drop table public.app_notifications;
create table public.app_notifications(id uuid not null default gen_random_uuid(),company_id uuid not null,recipient_user_id uuid not null,kind text not null default 'info'::text,title text not null,body text,action_key text,action_id uuid,read_at timestamp with time zone,created_at timestamp with time zone not null default now());
create table public.generation_setting_issues(id uuid not null default gen_random_uuid(),company_id uuid not null,issue_key text not null,issue_type text not null,title text not null,body text not null,action_key text,action_id uuid,resolved_at timestamp with time zone,created_at timestamp with time zone not null default now(),updated_at timestamp with time zone not null default now());
alter table public.generation_setting_issues add unique(company_id,issue_key);
CREATE OR REPLACE FUNCTION private.enqueue_notification(p_company_id uuid, p_recipient_user_id uuid, p_kind text, p_title text, p_body text DEFAULT NULL::text, p_action_key text DEFAULT NULL::text, p_action_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_id uuid;
begin
  insert into public.app_notifications(
    company_id,
    recipient_user_id,
    kind,
    title,
    body,
    action_key,
    action_id
  )
  values(
    p_company_id,
    p_recipient_user_id,
    coalesce(nullif(trim(p_kind), ''), 'info'),
    p_title,
    p_body,
    p_action_key,
    p_action_id
  )
  returning id into v_id;

  return v_id;
end;
$function$
;
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
 if leave_count>0 and private.paid_leave_daily_amount(settings)<=0 then warnings:=array_append(warnings,'有給'||leave_count::text||'日：有給単価が0円です。個別給与設定の有給額を確認してください。'); end if;
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
end $function$
;
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
$function$
;
CREATE OR REPLACE FUNCTION private.upsert_generation_setting_issue(cid uuid, p_issue_key text, p_issue_type text, p_title text, p_body text, p_action_key text DEFAULT NULL::text, p_action_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  existing_resolved timestamptz;
  existed boolean:=false;
  member record;
begin
  select true,resolved_at into existed,existing_resolved
  from public.generation_setting_issues
  where company_id=cid and issue_key=p_issue_key;

  insert into public.generation_setting_issues(
    company_id,issue_key,issue_type,title,body,action_key,action_id,resolved_at,updated_at
  )
  values(cid,p_issue_key,p_issue_type,p_title,p_body,p_action_key,p_action_id,null,now())
  on conflict(company_id,issue_key) do update
    set issue_type=excluded.issue_type,
        title=excluded.title,
        body=excluded.body,
        action_key=excluded.action_key,
        action_id=excluded.action_id,
        resolved_at=null,
        updated_at=now();

  if not existed or existing_resolved is not null then
    for member in
      select cm.user_id
      from public.company_members cm
      where cm.company_id=cid and cm.role::text in ('owner','admin','manager')
    loop
      perform private.enqueue_notification(
        cid,member.user_id,'warning',p_title,p_body,p_action_key,p_action_id
      );
    end loop;
  end if;
end;
$function$
;
