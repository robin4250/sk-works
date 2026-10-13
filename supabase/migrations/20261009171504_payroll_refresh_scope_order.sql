-- Staged known-RPC payroll scope ordering. No production application.
DO $$ BEGIN
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.save_daily_report_vehicle_usage(uuid,uuid,uuid,uuid,numeric)') and md5(prosrc)='152560f3e376eda1c0ae22e23bba34cb' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'payroll scope prerequisite differs: private vehicle'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.attendance_refresh_payroll()') and md5(prosrc)='dd6a3fc3cabc8b5b4985f0e7389c76b8' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'payroll scope prerequisite differs: private.attendance_refresh_payroll()'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.attendance_sync_payroll_detail()') and md5(prosrc)='a4286c027860e960735934e4c2089cc6' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'payroll scope prerequisite differs: private.attendance_sync_payroll_detail()'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.paid_leave_sync_payroll_detail()') and md5(prosrc)='a48ffd3129d8f7f0e268cb61b7f2f92b' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'payroll scope prerequisite differs: private.paid_leave_sync_payroll_detail()'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.save_daily_report_signature(uuid,text,text,jsonb)') and md5(prosrc)='33f136b95542d8eaeb51167ec18cc4da' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'payroll scope prerequisite differs: private.save_daily_report_signature(uuid,text,text,jsonb)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.sign_daily_report(uuid,text,jsonb)') and md5(prosrc)='29d2c4ca53dba74aa30d8cecfd956320' and prosecdef and proconfig=ARRAY['search_path=public, private, pg_temp']) then raise exception 'payroll scope prerequisite differs: public.sign_daily_report(uuid,text,jsonb)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.select_site_calculation_source(uuid,text,uuid,text)') and md5(prosrc)='c85a5bb5110a92dbb677f0bd23897d35' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'payroll scope prerequisite differs: private.select_site_calculation_source(uuid,text,uuid,text)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.save_trade_company_contract(uuid,text,integer,integer,integer,numeric,integer)') and md5(prosrc)='34ed317dae0998de6c494e101490ce56' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'payroll scope prerequisite differs: private.save_trade_company_contract(uuid,text,integer,integer,integer,numeric,integer)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('payroll_final_private.finalize(uuid,integer,boolean)') and md5(prosrc)='43ef67bcc04054b80e9430543916782f' and prosecdef and proconfig=array['search_path=""']) then raise exception 'payroll scope snapshot/review prerequisite differs: payroll_final_private.finalize(uuid,integer,boolean)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.my_payroll_statement_rows_with_adjustments()') and md5(prosrc)='8a373e997be15c979ede5c2a65abadfa' and prosecdef and proconfig=array['search_path=""']) then raise exception 'payroll scope snapshot/review prerequisite differs: public.my_payroll_statement_rows_with_adjustments()'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.payroll_review_workspace(date)') and md5(prosrc)='57a80a479876e01b11c34950ae0415f7' and prosecdef and proconfig=array['search_path=""']) then raise exception 'payroll scope snapshot/review prerequisite differs: private.payroll_review_workspace(date)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.confirm_payroll_review_month(date)') and md5(prosrc)='2fced3b1ad554a422dc9071a8adfce33' and prosecdef and proconfig=array['search_path=""']) then raise exception 'payroll scope snapshot/review prerequisite differs: private.confirm_payroll_review_month(date)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.cancel_payroll_review_month(date)') and md5(prosrc)='451ae462e69d9f30db21006ec16fa98c' and prosecdef and proconfig=array['search_path=""']) then raise exception 'payroll scope snapshot/review prerequisite differs: public.cancel_payroll_review_month(date)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.set_payroll_confirmers(uuid[])') and md5(prosrc)='ee3a7e22ae6bf2c07f12b858c7621638' and prosecdef and proconfig=array['search_path=""']) then raise exception 'payroll scope snapshot/review prerequisite differs: public.set_payroll_confirmers(uuid[])'; end if;
END $$;
create schema payroll_scope_private;
revoke all on schema payroll_scope_private from public,anon,authenticated;
-- Trusted callers supply typed database-derived tuples; this is not a client endpoint.
create function payroll_scope_private.lock_scopes(p_scopes jsonb,p_allow_missing_parents boolean default false) returns void
language plpgsql security definer set search_path='' as $$
declare r record;
begin
 for r in select distinct x.cid from jsonb_to_recordset(p_scopes) x(cid uuid,wid uuid,day date) where x.cid is not null and x.wid is not null and x.day is not null order by x.cid loop
  perform 1 from public.companies where id=r.cid for key share;
  if not found and not p_allow_missing_parents then raise exception 'payroll scope company unavailable' using errcode='40001'; end if;
 end loop;
 for r in select distinct x.cid,x.wid from jsonb_to_recordset(p_scopes) x(cid uuid,wid uuid,day date) where x.cid is not null and x.wid is not null and x.day is not null order by x.cid,x.wid loop
  perform 1 from public.workers where company_id=r.cid and id=r.wid for update;
  if not found and not p_allow_missing_parents then raise exception 'payroll scope worker unavailable' using errcode='40001'; end if;
 end loop;
 for r in select distinct x.cid,x.wid,date_trunc('month',x.day)::date scope_month from jsonb_to_recordset(p_scopes) x(cid uuid,wid uuid,day date) where x.cid is not null and x.wid is not null and x.day is not null order by x.cid,x.wid,scope_month loop
  perform pg_advisory_xact_lock(hashtextextended(r.cid::text||r.wid::text||r.scope_month::text,0));
 end loop;
end $$;
revoke all on function payroll_scope_private.lock_scopes(jsonb,boolean) from public,anon,authenticated;

create function payroll_scope_private.report_sources(p_report_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('header',jsonb_build_object('cid',dr.company_id,'site',dr.site_id,'route',dr.route_assignment_id,'day',dr.report_date),
 'attendance',coalesce((select jsonb_agg(jsonb_build_object('id',ae.id,'cid',ae.company_id,'wid',ae.worker_id,'day',ae.work_date) order by ae.id) from public.attendance_entries ae where ae.source_report_id=dr.id),'[]'),
 'workers',coalesce((select jsonb_agg(rw.worker_id order by rw.worker_id) from public.daily_report_workers rw where rw.report_id=dr.id),'[]'),
 'scopes',coalesce((select jsonb_agg(jsonb_build_object('cid',cid,'wid',wid,'day',work_day) order by cid,wid,work_day) from (
  select ae.company_id cid,ae.worker_id wid,ae.work_date work_day from public.attendance_entries ae where ae.source_report_id=dr.id
  union select dr.company_id,rw.worker_id,dr.report_date from public.daily_report_workers rw where rw.report_id=dr.id
 ) scopes),'[]')) from public.daily_reports dr where dr.id=p_report_id
$$;
revoke all on function payroll_scope_private.report_sources(uuid) from public,anon,authenticated;

-- Explicit reviewed definition; original authorization and business writes retained.
CREATE OR REPLACE FUNCTION private.attendance_refresh_payroll()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform payroll_scope_private.lock_scopes((case when tg_op<>'INSERT' then jsonb_build_array(jsonb_build_object('cid',old.company_id,'wid',old.worker_id,'day',old.work_date)) else '[]'::jsonb end)||(case when tg_op<>'DELETE' then jsonb_build_array(jsonb_build_object('cid',new.company_id,'wid',new.worker_id,'day',new.work_date)) else '[]'::jsonb end),true);
 if tg_op<>'INSERT' then perform private.refresh_automatic_payroll(old.company_id,old.worker_id,old.work_date); end if;
 if tg_op<>'DELETE' then perform private.refresh_automatic_payroll(new.company_id,new.worker_id,new.work_date); end if;
 return null;
end;
$function$
;
-- Explicit reviewed definition; original authorization and business writes retained.
CREATE OR REPLACE FUNCTION private.attendance_sync_payroll_detail()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform payroll_scope_private.lock_scopes((case when tg_op<>'INSERT' then jsonb_build_array(jsonb_build_object('cid',old.company_id,'wid',old.worker_id,'day',old.work_date)) else '[]'::jsonb end)||(case when tg_op<>'DELETE' then jsonb_build_array(jsonb_build_object('cid',new.company_id,'wid',new.worker_id,'day',new.work_date)) else '[]'::jsonb end),true);
  if tg_op <> 'INSERT' then
    perform private.sync_payroll_attendance_detail(old.company_id,old.worker_id,old.work_date);
  end if;
  if tg_op <> 'DELETE' then
    perform private.sync_payroll_attendance_detail(new.company_id,new.worker_id,new.work_date);
  end if;
  return null;
end;
$function$
;
-- Explicit reviewed definition; original authorization and business writes retained.
CREATE OR REPLACE FUNCTION private.paid_leave_sync_payroll_detail()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform payroll_scope_private.lock_scopes((case when tg_op<>'INSERT' then jsonb_build_array(jsonb_build_object('cid',old.company_id,'wid',old.worker_id,'day',old.leave_date)) else '[]'::jsonb end)||(case when tg_op<>'DELETE' then jsonb_build_array(jsonb_build_object('cid',new.company_id,'wid',new.worker_id,'day',new.leave_date)) else '[]'::jsonb end),true);
 if tg_op<>'INSERT' then
   perform private.refresh_automatic_payroll_internal(old.company_id,old.worker_id,old.leave_date);
   perform private.sync_payroll_attendance_detail(old.company_id,old.worker_id,old.leave_date);
 end if;
 if tg_op<>'DELETE' then
   perform private.refresh_automatic_payroll_internal(new.company_id,new.worker_id,new.leave_date);
   perform private.sync_payroll_attendance_detail(new.company_id,new.worker_id,new.leave_date);
 end if;
 return null;
end $function$
;
-- Explicit reviewed definition; original authorization and business writes retained.
CREATE OR REPLACE FUNCTION private.save_daily_report_signature(p_report_id uuid, p_role text, p_signer_name text, p_signature_json jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare scope_before jsonb; r public.daily_reports%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not exists(select 1 from public.daily_reports dr join public.company_members cm on cm.company_id=dr.company_id and cm.user_id=auth.uid() where dr.id=p_report_id) then raise exception 'daily report not found'; end if;
  scope_before:=payroll_scope_private.report_sources(p_report_id);
  perform payroll_scope_private.lock_scopes(scope_before->'scopes');
  select dr.* into r from public.daily_reports dr where dr.id=p_report_id and exists (
    select 1 from public.company_members cm where cm.company_id=dr.company_id and cm.user_id=auth.uid()
  ) for update;
  if r.id is null then raise exception 'daily report not found'; end if;
  perform 1 from public.daily_report_workers where report_id=p_report_id order by worker_id for share;
  if payroll_scope_private.report_sources(p_report_id) is distinct from scope_before then raise exception 'daily report payroll scope changed' using errcode='40001'; end if;

  if r.status <> 'draft' then raise exception 'signed report requires approved edit request'; end if;
  if p_role not in ('representative','supervisor') or p_role is null then raise exception 'invalid signature role'; end if;
  if nullif(trim(p_signer_name),'') is null then raise exception 'signer name is required'; end if;
  if jsonb_typeof(p_signature_json->'strokes') is distinct from 'array' then raise exception 'signature strokes required'; end if;
  if not exists (select 1 from jsonb_array_elements(p_signature_json->'strokes') stroke where jsonb_typeof(stroke)='array' and jsonb_array_length(stroke)>0) then raise exception 'signature strokes required'; end if;
  if p_role='representative' then
    update public.daily_reports set representative_signature_json=p_signature_json, representative_signer_name=trim(p_signer_name), updated_by=auth.uid(),updated_at=now() where id=p_report_id;
  else
    update public.daily_reports set supervisor_signature_json=p_signature_json, supervisor_signer_name=trim(p_signer_name),updated_by=auth.uid(),updated_at=now() where id=p_report_id;
  end if;
  select * into r from public.daily_reports where id=p_report_id;
  if r.representative_signature_json is not null and r.supervisor_signature_json is not null then
    -- Retain the existing finalization/attendance workflow, with two distinct signatures in the legacy envelope.
    perform public.sign_daily_report(p_report_id,r.supervisor_signer_name,jsonb_build_object('version',3,
      'representative',r.representative_signature_json,'supervisor',r.supervisor_signature_json));
  end if;
end;
$function$
;
-- Explicit reviewed definition; original authorization and business writes retained.
CREATE OR REPLACE FUNCTION public.sign_daily_report(p_report_id uuid, p_signer_name text, p_signature_json jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare scope_before jsonb;
  v_user_id uuid:=auth.uid();
  v_company_id uuid;
  v_site_id uuid;
  v_route_id uuid;
  v_date date;
  v_detail record;
  v_entry_id uuid;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  if not exists(select 1 from public.daily_reports dr join public.company_members cm on cm.company_id=dr.company_id and cm.user_id=auth.uid() where dr.id=p_report_id) then raise exception 'daily report not found'; end if;
  scope_before:=payroll_scope_private.report_sources(p_report_id);
  perform payroll_scope_private.lock_scopes(scope_before->'scopes');
  select dr.company_id,dr.site_id,dr.route_assignment_id,dr.report_date
  into v_company_id,v_site_id,v_route_id,v_date
  from public.daily_reports dr
  join public.company_members cm
    on cm.company_id=dr.company_id and cm.user_id=v_user_id
  where dr.id=p_report_id
  for update;

  if v_company_id is null then raise exception 'daily report not found'; end if;
  perform 1 from public.daily_report_workers where report_id=p_report_id order by worker_id for share;
  if payroll_scope_private.report_sources(p_report_id) is distinct from scope_before then raise exception 'daily report payroll scope changed' using errcode='40001'; end if;

  if nullif(trim(coalesce(p_signer_name,'')),'') is null then
    raise exception 'signer name is required';
  end if;
  if p_signature_json is null or p_signature_json='[]'::jsonb then
    raise exception 'signature is required';
  end if;

  update public.daily_reports
  set status='signed',
      signer_name=trim(p_signer_name),
      signature_json=p_signature_json,
      signed_at=now(),
      updated_by=v_user_id,
      updated_at=now()
  where id=p_report_id;

  delete from public.attendance_entries ae
  where ae.source_report_id=p_report_id
    and (
      ae.site_id is distinct from v_site_id
      or ae.route_assignment_id is distinct from v_route_id
      or ae.work_date<>v_date
      or not exists(
        select 1 from public.daily_report_workers rw
        where rw.report_id=p_report_id and rw.worker_id=ae.worker_id
      )
    );

  for v_detail in
    select * from public.daily_report_workers
    where report_id=p_report_id
  loop
    select ae.id into v_entry_id
    from public.attendance_entries ae
    where ae.company_id=v_company_id
      and ae.worker_id=v_detail.worker_id
      and ae.site_id is not distinct from v_site_id
      and ae.route_assignment_id is not distinct from v_route_id
      and ae.work_date=v_date
      and ae.source_report_id=p_report_id
    order by ae.created_at
    limit 1;

    if v_entry_id is null then
      if exists(
        select 1 from public.attendance_entries ae
        where ae.company_id=v_company_id
          and ae.worker_id=v_detail.worker_id
          and ae.site_id is not distinct from v_site_id
          and ae.route_assignment_id is not distinct from v_route_id
          and ae.work_date=v_date
          and ae.source_report_id is distinct from p_report_id
      ) then
        raise exception '同じ日・勤務先の別の出勤記録があります。管理者が確認してください。';
      end if;

      insert into public.attendance_entries(
        company_id,work_date,worker_id,site_id,route_assignment_id,
        base_man_days,overtime_hours,early_hours,night_hours,
        allowance_amount,notes,work_category,allowance_names,
        source_report_id,created_by,updated_by
      )
      values(
        v_company_id,v_date,v_detail.worker_id,v_site_id,v_route_id,
        1,v_detail.overtime_hours,v_detail.early_hours,v_detail.night_hours,
        v_detail.allowance_amount,v_detail.allowance_label,v_detail.work_category,
        array(
          select distinct trim(v)
          from unnest(string_to_array(coalesce(v_detail.allowance_label,''),E'\n')) v
          where trim(v)<>''
        ),
        p_report_id,v_user_id,v_user_id
      );
    else
      update public.attendance_entries
      set base_man_days=1,
          overtime_hours=v_detail.overtime_hours,
          early_hours=v_detail.early_hours,
          night_hours=v_detail.night_hours,
          allowance_amount=v_detail.allowance_amount,
          notes=v_detail.allowance_label,
          work_category=v_detail.work_category,
          allowance_names=array(
            select distinct trim(v)
            from unnest(string_to_array(coalesce(v_detail.allowance_label,''),E'\n')) v
            where trim(v)<>''
          ),
          source_report_id=p_report_id,
          updated_by=v_user_id,
          updated_at=now()
      where id=v_entry_id and source_report_id=p_report_id;
    end if;

    v_entry_id:=null;
  end loop;
end;
$function$
;
-- Explicit reviewed definition; original authorization and business writes retained.
CREATE OR REPLACE FUNCTION private.select_site_calculation_source(p_site_id uuid, p_output_type text, p_trade_company_id uuid, p_source text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cid uuid;
  v_customer uuid;
  scope_before jsonb;
  v_day date;
  r record;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  if p_output_type not in ('invoice','payment_certificate','payroll') then
    raise exception '計算対象を確認してください。';
  end if;
  if p_source not in ('site','trade_company') then
    raise exception '計算元を選択してください。';
  end if;
  if not exists(select 1 from public.sites s where s.id=p_site_id and s.company_id=cid) then
    raise exception '現場が見つかりません。';
  end if;
  -- Every saved association must belong to this tenant, including a site choice.
  if not exists(select 1 from public.trade_companies tc
      where tc.id=p_trade_company_id and tc.company_id=cid) then
    raise exception '取引会社が見つかりません。';
  end if;
  if not exists(
    select 1 from public.trade_companies tc
    join public.sites s on s.id=p_site_id and s.company_id=tc.company_id
    where tc.id=p_trade_company_id and tc.company_id=cid
      and case when p_output_type='invoice' then
        tc.trade_role in ('customer','both') and tc.customer_id is not null
        and s.customer_id=tc.customer_id
        and exists(select 1 from public.customers c
          where c.id=tc.customer_id and c.company_id=cid)
      else
        tc.trade_role in ('subcontractor','both') and tc.partner_company_id is not null
        -- Subcontractor settings may be selected before the first attendance.
        -- There is no registered site-to-partner mapping; validate the actual
        -- tenant-owned partner master rather than inventing an attendance prerequisite.
        and exists(select 1 from public.partner_companies pc
          where pc.id=tc.partner_company_id and pc.company_id=cid)
      end
  ) then
    raise exception 'この現場・帳票に登録された取引会社を選択してください。';
  end if;

  if p_output_type='payroll' then
   scope_before:=coalesce((select jsonb_agg(jsonb_build_object('cid',ae.company_id,'wid',ae.worker_id,'day',ae.work_date) order by ae.company_id,ae.worker_id,ae.work_date,ae.id) from public.attendance_entries ae where ae.company_id=cid and ae.site_id=p_site_id),'[]'::jsonb);
   perform payroll_scope_private.lock_scopes(scope_before);
   if scope_before is distinct from coalesce((select jsonb_agg(jsonb_build_object('cid',ae.company_id,'wid',ae.worker_id,'day',ae.work_date) order by ae.company_id,ae.worker_id,ae.work_date,ae.id) from public.attendance_entries ae where ae.company_id=cid and ae.site_id=p_site_id),'[]'::jsonb) then raise exception 'payroll source scope changed' using errcode='40001'; end if;
  end if;
  insert into public.site_calculation_source_preferences(
    company_id,site_id,output_type,trade_company_id,source,selected_by,selected_at
  )
  values(cid,p_site_id,p_output_type,p_trade_company_id,p_source,auth.uid(),now())
  on conflict(company_id,site_id,output_type) do update
  set trade_company_id=excluded.trade_company_id,
      source=excluded.source,
      selected_by=auth.uid(),
      selected_at=now();

  select s.customer_id into v_customer
  from public.sites s
  where s.id=p_site_id and s.company_id=cid;

  if p_output_type='payroll' then
    for r in select distinct (v->>'wid')::uuid worker_id,(v->>'day')::date work_date from jsonb_array_elements(scope_before) v order by worker_id,work_date loop
      perform private.refresh_automatic_payroll(cid,r.worker_id,r.work_date);
    end loop;
    return;
  end if;

  for r in
    select distinct ae.work_date
    from public.attendance_entries ae
    where ae.company_id=cid and ae.site_id=p_site_id
  loop
    v_day:=r.work_date;
    if p_output_type='invoice' then
      perform private.refresh_automatic_invoice(cid,v_customer,v_day);
    elsif p_output_type='payment_certificate' then
      for r in
        select distinct w.partner_company_id as partner_id
        from public.attendance_entries ae
        join public.workers w on w.id=ae.worker_id and w.company_id=ae.company_id
        where ae.company_id=cid and ae.site_id=p_site_id
          and w.partner_company_id is not null
          and date_trunc('month',ae.work_date)=date_trunc('month',v_day)
      loop
        perform private.refresh_automatic_payment_certificate(cid,r.partner_id,v_day);
      end loop;
    elsif p_output_type='payroll' then
      for r in
        select distinct ae.worker_id
        from public.attendance_entries ae
        where ae.company_id=cid and ae.site_id=p_site_id
          and date_trunc('month',ae.work_date)=date_trunc('month',v_day)
      loop
        perform private.refresh_automatic_payroll(cid,r.worker_id,v_day);
      end loop;
    end if;
  end loop;
end
$function$
;
-- Explicit reviewed definition; original authorization and business writes retained.
CREATE OR REPLACE FUNCTION private.save_trade_company_contract(p_trade_company_id uuid, p_contract_method text, p_daily_rate_yen integer DEFAULT 0, p_monthly_rate_yen integer DEFAULT 0, p_square_meter_unit_price_yen integer DEFAULT 0, p_square_meter_quantity numeric DEFAULT 0, p_contract_amount_yen integer DEFAULT 0)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cid uuid;
  tc public.trade_companies%rowtype;
  r record;
  v_customer uuid;
  scope_before jsonb;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;

  select * into tc
  from public.trade_companies
  where id=p_trade_company_id and company_id=cid;
  if tc.id is null then raise exception '取引会社が見つかりません。'; end if;

  if p_contract_method not in ('none','daily','monthly','square_meter','contract') then
    raise exception '契約方式を確認してください。';
  end if;
  if p_contract_method='square_meter'
     and (coalesce(p_square_meter_unit_price_yen,0)<=0
       or coalesce(p_square_meter_quantity,0)<=0) then
    raise exception '平米単価と平米数を入力してください。';
  end if;

  scope_before:=coalesce((select jsonb_agg(jsonb_build_object('cid',ae.company_id,'wid',ae.worker_id,'day',ae.work_date) order by ae.company_id,ae.worker_id,ae.work_date,ae.id,scsp.site_id) from public.site_calculation_source_preferences scsp join public.attendance_entries ae on ae.company_id=scsp.company_id and ae.site_id=scsp.site_id where scsp.company_id=cid and scsp.trade_company_id=p_trade_company_id and scsp.source='trade_company' and scsp.output_type='payroll'),'[]'::jsonb);
  perform payroll_scope_private.lock_scopes(scope_before);
  if scope_before is distinct from coalesce((select jsonb_agg(jsonb_build_object('cid',ae.company_id,'wid',ae.worker_id,'day',ae.work_date) order by ae.company_id,ae.worker_id,ae.work_date,ae.id,scsp.site_id) from public.site_calculation_source_preferences scsp join public.attendance_entries ae on ae.company_id=scsp.company_id and ae.site_id=scsp.site_id where scsp.company_id=cid and scsp.trade_company_id=p_trade_company_id and scsp.source='trade_company' and scsp.output_type='payroll'),'[]'::jsonb) then raise exception 'payroll source scope changed' using errcode='40001'; end if;
  insert into public.trade_company_contracts(
    company_id,trade_company_id,contract_method,daily_rate_yen,monthly_rate_yen,
    square_meter_unit_price_yen,square_meter_quantity,contract_amount_yen,
    updated_by,updated_at
  )
  values(
    cid,p_trade_company_id,p_contract_method,
    greatest(coalesce(p_daily_rate_yen,0),0),
    greatest(coalesce(p_monthly_rate_yen,0),0),
    greatest(coalesce(p_square_meter_unit_price_yen,0),0),
    greatest(coalesce(p_square_meter_quantity,0),0),
    greatest(coalesce(p_contract_amount_yen,0),0),
    auth.uid(),now()
  )
  on conflict(company_id,trade_company_id) do update
  set contract_method=excluded.contract_method,
      daily_rate_yen=excluded.daily_rate_yen,
      monthly_rate_yen=excluded.monthly_rate_yen,
      square_meter_unit_price_yen=excluded.square_meter_unit_price_yen,
      square_meter_quantity=excluded.square_meter_quantity,
      contract_amount_yen=excluded.contract_amount_yen,
      updated_by=auth.uid(),
      updated_at=now();

  if tc.partner_company_id is not null then
    insert into public.partner_payment_settings(
      company_id,partner_company_id,daily_rate_yen,updated_at
    )
    values(
      cid,tc.partner_company_id,
      case when p_contract_method='daily'
        then greatest(coalesce(p_daily_rate_yen,0),0)
        else 0 end,
      now()
    )
    on conflict(company_id,partner_company_id) do update
    set daily_rate_yen=excluded.daily_rate_yen,
        updated_at=now();
  end if;

  for r in
    select distinct
      scsp.site_id,
      scsp.output_type,
      ae.work_date,
      ae.worker_id
    from public.site_calculation_source_preferences scsp
    join public.attendance_entries ae
      on ae.company_id=scsp.company_id
      and ae.site_id=scsp.site_id
    where scsp.company_id=cid
      and scsp.trade_company_id=p_trade_company_id
      and scsp.source='trade_company'
      and scsp.output_type<>'payroll'
  loop
    if r.output_type='invoice' then
      select s.customer_id into v_customer
      from public.sites s
      where s.id=r.site_id and s.company_id=cid;
      perform private.refresh_automatic_invoice(cid,v_customer,r.work_date);
    elsif r.output_type='payment_certificate'
          and tc.partner_company_id is not null then
      perform private.refresh_automatic_payment_certificate(
        cid,tc.partner_company_id,r.work_date
      );
    elsif r.output_type='payroll' then
      perform private.refresh_automatic_payroll(cid,r.worker_id,r.work_date);
    end if;
  end loop;
  for r in select distinct (v->>'wid')::uuid worker_id,(v->>'day')::date work_date from jsonb_array_elements(scope_before) v order by worker_id,work_date loop
    perform private.refresh_automatic_payroll(cid,r.worker_id,r.work_date);
  end loop;
end
$function$
;

-- Snapshot company SHARE serializes review UPDATE, while allowing child FK KEY SHARE.
create or replace function payroll_final_private.finalize(p_statement_id uuid,p_expected_revision integer,p_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare initial public.payroll_statements%rowtype; ps public.payroll_statements%rowtype;
 saved payroll_final_private.documents%rowtype; settings jsonb; adjustments jsonb; adjustment_detail jsonb;
 additions bigint; removals bigint; doc jsonb; value jsonb; stamp timestamptz:=clock_timestamp();
 company_name text; worker_name text; bank jsonb;
begin
 if auth.uid() is null or not coalesce(private.account_access_allowed(),false) then raise exception 'payroll access denied'; end if;
 if p_confirmed is not true then raise exception 'explicit finalization confirmation required'; end if;
 select * into initial from public.payroll_statements where id=p_statement_id;
 if not found or not coalesce(private.payroll_settings_allowed(initial.company_id,initial.worker_id,'edit'),false) then raise exception 'payroll access denied'; end if;
 perform 1 from public.companies where id=initial.company_id for share;
 if not found then raise exception 'payroll access denied'; end if;
 perform 1 from public.workers where id=initial.worker_id and company_id=initial.company_id for share;
 if not found then raise exception 'payroll access denied'; end if;
 if initial.period_start is null or initial.period_end is null or initial.period_start<>date_trunc('month',initial.period_start)::date or initial.period_end<>(initial.period_start+interval '1 month - 1 day')::date then raise exception 'only canonical monthly payroll periods can be finalized'; end if;
 perform pg_advisory_xact_lock(hashtextextended(initial.company_id::text||initial.worker_id::text||initial.period_start::text,0));
 select * into ps from public.payroll_statements where id=p_statement_id for update;
 if not found or (ps.company_id,ps.worker_id,ps.period_start,ps.period_end) is distinct from (initial.company_id,initial.worker_id,initial.period_start,initial.period_end) then raise exception 'payroll scope changed'; end if;
 select * into saved from payroll_final_private.documents where statement_id=ps.id;
 if found then
  if ps.workflow_state<>'finalized' or saved.revision is distinct from p_expected_revision then raise exception 'payroll revision conflict'; end if;
  return jsonb_build_object('finalized',true,'revision',saved.revision,'snapshot',jsonb_set(saved.value,'{detail,bank_account}','{}'::jsonb));
 end if;
 if not ps.automatic_calculation or ps.workflow_state<>'draft' then raise exception 'only automatic draft can be finalized; legacy finalization is not backfilled'; end if;
 if p_expected_revision is null or ps.revision is distinct from p_expected_revision then raise exception 'payroll revision conflict'; end if;
 perform private.refresh_automatic_payroll_internal(ps.company_id,ps.worker_id,ps.period_start);
 perform private.sync_payroll_attendance_detail(ps.company_id,ps.worker_id,ps.period_start);
 select * into ps from public.payroll_statements where id=p_statement_id;
 if ps.revision is distinct from p_expected_revision then return jsonb_build_object('finalized',false,'reason','recalculation_changed','revision',ps.revision); end if;
 if ps.calculation_blocked then raise exception 'payroll calculation blocked'; end if;
 if not coalesce(private.payroll_confirmed_all(ps.id),false) or exists(
  select 1 from public.payroll_confirmers c left join public.payroll_statement_reviews r on r.statement_id=ps.id and r.reviewer_id=c.user_id
  where c.company_id=ps.company_id and (r.checked_revision is distinct from ps.revision or r.confirmed_revision is distinct from ps.revision or r.confirmed_at is null)
 ) then raise exception 'all current revision reviews required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'label',a.label_snapshot,'direction',a.direction,'amount_yen',a.amount_yen,'effective_date',a.effective_date) order by a.effective_date,a.id),'[]'),
 coalesce(sum(a.amount_yen) filter(where a.direction='addition'),0),coalesce(sum(a.amount_yen) filter(where a.direction='deduction'),0)
 into adjustments,additions,removals from public.payroll_adjustments a where a.company_id=ps.company_id and a.worker_id=ps.worker_id and a.effective_date between ps.period_start and ps.period_end and a.cancelled_at is null;
 select coalesce(jsonb_object_agg(label,total),'{}') into adjustment_detail from (
  select a.label_snapshot label,sum(case when a.direction='addition' then a.amount_yen else -a.amount_yen end)::integer total from public.payroll_adjustments a
  where a.company_id=ps.company_id and a.worker_id=ps.worker_id and a.effective_date between ps.period_start and ps.period_end and a.cancelled_at is null group by a.label_snapshot
 ) grouped;
 select c.name,w.name into company_name,worker_name from public.companies c join public.workers w on w.company_id=c.id where c.id=ps.company_id and w.id=ps.worker_id;
 select coalesce(to_jsonb(s)-array['company_id','worker_id','created_by','updated_by','created_at','updated_at'],'{}') into settings from public.worker_payroll_settings s where s.company_id=ps.company_id and s.worker_id=ps.worker_id;
 select jsonb_build_object('bank_name',b.bank_name,'branch_name',b.branch_name,'account_type',b.account_type,'account_number',b.account_number,'account_holder',b.account_holder) into bank from public.worker_private_bank_accounts b where b.company_id=ps.company_id and b.worker_id=ps.worker_id order by b.updated_at desc nulls last limit 1;
 doc:=private.payroll_document_metadata(ps.id);
 value:=jsonb_build_object('schema_version',1,'calculator_version','resident-tax-20261009161427','statement_id',ps.id,'revision',ps.revision,
 'period_start',ps.period_start,'period_end',ps.period_end,'issued_at',ps.issued_at,'company_name',company_name,'worker_name',worker_name,
 'base_result',jsonb_build_object('gross_pay',ps.gross_pay,'deductions',ps.deductions,'net_pay',ps.net_pay),
 'result',jsonb_build_object('gross_pay',(ps.gross_pay+additions)::integer,'deductions',(ps.deductions+removals)::integer,'net_pay',(ps.gross_pay+additions-ps.deductions-removals)::integer),
 'conditions',jsonb_build_object('settings',coalesce(settings,'{}'),'resident_tax',resident_tax_private.resolve(ps.company_id,ps.worker_id,ps.period_start),'family_allowance_mode','legacy_fixed','company_rate_registry_adopted',false,'income_tax_table_registry_adopted',false),
 'adjustments',adjustments,'document_metadata',doc,'detail',coalesce(ps.detail,'{}')||adjustment_detail||jsonb_build_object('bank_account',coalesce(bank,'{}'),'workflow_state','finalized','revision',ps.revision,'review_confirmed',true,'reviewed_at',(select max(r.confirmed_at) from public.payroll_statement_reviews r join public.payroll_confirmers pc on pc.company_id=ps.company_id and pc.user_id=r.reviewer_id where r.statement_id=ps.id and r.confirmed_revision=ps.revision))||doc,
 'finalized_by',auth.uid(),'finalized_at',stamp);
 insert into payroll_final_private.documents values(ps.id,ps.company_id,ps.worker_id,ps.period_start,ps.period_end,ps.revision,value,auth.uid(),stamp);
 update public.payroll_statements set workflow_state='finalized',finalized_by=auth.uid(),finalized_at=stamp where id=ps.id;
 insert into payroll_final_private.history(statement_id,company_id,worker_id,revision,actor_id,changed_at,value) values(ps.id,ps.company_id,ps.worker_id,ps.revision,auth.uid(),stamp,value);
 return jsonb_build_object('finalized',true,'revision',ps.revision,'snapshot',jsonb_set(value,'{detail,bank_account}','{}'::jsonb));
end $$;
create or replace function public.my_payroll_statement_rows_with_adjustments()
returns table(id uuid,period_start date,period_end date,gross_pay integer,deductions integer,net_pay integer,detail jsonb,issued_at timestamptz,company_name text,worker_name text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not coalesce(private.account_access_allowed(),false) then raise exception 'authentication required'; end if;
 return query
 select r.id,r.period_start,r.period_end,r.gross_pay,r.deductions,r.net_pay,r.detail||jsonb_build_object('workflow_state','draft','revision',ps.revision),r.issued_at,r.company_name,r.worker_name
 from payroll_final_private.live_my_rows() r join public.payroll_statements ps on ps.id=r.id
 union all
 select ps.id,coalesce((f.value->>'period_start')::date,ps.period_start),coalesce((f.value->>'period_end')::date,ps.period_end),
 coalesce((f.value#>>'{result,gross_pay}')::integer,ps.gross_pay),
 coalesce((f.value#>>'{result,deductions}')::integer,ps.deductions),
 coalesce((f.value#>>'{result,net_pay}')::integer,ps.net_pay),
 coalesce(f.value->'detail',ps.detail,'{}')||jsonb_build_object('workflow_state',case when f.statement_id is not null then 'finalized' else ps.workflow_state end,'revision',coalesce(f.revision,ps.revision),'review_confirmed',case when f.statement_id is not null then 'true'::jsonb else ps.detail->'review_confirmed' end),case when f.statement_id is not null then (f.value->>'issued_at')::timestamptz else ps.issued_at end,
 coalesce(f.value->>'company_name',ps.detail->>'company_name',''),
 coalesce(f.value->>'worker_name',ps.detail->>'worker_name','')
 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id
 join public.companies c on c.id=ps.company_id
 left join payroll_final_private.documents f on f.statement_id=ps.id
 where ps.workflow_state<>'draft' and w.user_id=auth.uid()
 order by period_end desc;
end $$;
create or replace function private.payroll_review_workspace(p_period_start date default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare workspace jsonb;items jsonb;cid uuid;role_text text;
begin
 workspace:=private.payroll_live_review_workspace(p_period_start);
 select cm.company_id,cm.role::text into cid,role_text from public.company_members cm where cm.user_id=auth.uid() limit 1;
 select coalesce(jsonb_agg(item order by worker_sort,id),'[]') into items from (
  select r.value item,r.value->>'worker_name' worker_sort,(r.value->>'id')::uuid id
  from jsonb_array_elements(workspace->'statements') r(value)
  union all
  select jsonb_build_object('id',ps.id,'worker_id',ps.worker_id,
   'worker_name',coalesce(f.value->>'worker_name',ps.detail->>'worker_name',''),
   'company_name',coalesce(f.value->>'company_name',ps.detail->>'company_name',''),
   'period_start',coalesce((f.value->>'period_start')::date,ps.period_start),'period_end',coalesce((f.value->>'period_end')::date,ps.period_end),'issued_at',case when f.statement_id is not null then (f.value->>'issued_at')::timestamptz else ps.issued_at end,
   'gross_pay',coalesce((f.value#>>'{result,gross_pay}')::integer,ps.gross_pay),
   'deductions',coalesce((f.value#>>'{result,deductions}')::integer,ps.deductions),
   'net_pay',coalesce((f.value#>>'{result,net_pay}')::integer,ps.net_pay),
   'detail',jsonb_set(coalesce(f.value->'detail',ps.detail,'{}'),'{bank_account}','{}'::jsonb),
   'revision',coalesce(f.revision,ps.revision),'workflow_state',case when f.statement_id is not null then 'finalized' else ps.workflow_state end,
   'review_checked',exists(select 1 from jsonb_array_elements(coalesce(f.value#>'{document_metadata,payroll_confirmations}','[]')) e where e->>'user_id'=auth.uid()::text and e->>'confirmed_at' is not null),
   'review_confirmed',case when f.statement_id is not null then true else coalesce(ps.detail->'review_confirmed'='true'::jsonb,false) end,
   'reviewer_confirmed',exists(select 1 from jsonb_array_elements(coalesce(f.value#>'{document_metadata,payroll_confirmations}','[]')) e where e->>'user_id'=auth.uid()::text and e->>'confirmed_at' is not null)),
   w.name,ps.id
  from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id
  join public.companies c on c.id=ps.company_id
  left join public.payroll_manager_worker_visibility v on v.company_id=ps.company_id and v.worker_id=ps.worker_id
  left join payroll_final_private.documents f on f.statement_id=ps.id
  where ps.company_id=cid and coalesce((f.value->>'period_start')::date,ps.period_start)=(workspace->>'period_start')::date
   and ps.workflow_state<>'draft' and w.affiliation::text='employee'
   and (role_text in ('owner','admin','viewer') or (role_text='manager' and coalesce(v.visible_to_manager,false)))
 ) rows;
 return workspace||jsonb_build_object('statements',items);
end $$;

-- Vehicle child mutation now follows the same scope/parent order as signatures.
CREATE OR REPLACE FUNCTION private.save_daily_report_vehicle_usage(p_report_id uuid, p_worker_id uuid, p_vehicle_id uuid, p_route_assignment_id uuid, p_odometer_km numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_status text;
  v_current numeric;
  scope_before jsonb;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;

  select m.company_id into v_company
  from public.company_members m
  where m.user_id=v_user
  limit 1;
  if v_company is null then raise exception '会社への所属が必要です'; end if;

  if not exists(select 1 from public.daily_reports where id=p_report_id and company_id=v_company) then raise exception '日報を確認できません'; end if;
  scope_before:=payroll_scope_private.report_sources(p_report_id);
  perform payroll_scope_private.lock_scopes(scope_before->'scopes');
  select d.status into v_status
  from public.daily_reports d
  where d.id=p_report_id and d.company_id=v_company
  for update;
  if payroll_scope_private.report_sources(p_report_id) is distinct from scope_before then raise exception 'daily report payroll scope changed' using errcode='40001'; end if;
  if v_status is null then raise exception '日報を確認できません'; end if;
  if v_status<>'draft' then raise exception '確定済み日報は直接変更できません'; end if;

  if not exists(
    select 1 from public.daily_report_workers w
    where w.report_id=p_report_id and w.worker_id=p_worker_id
  ) then
    raise exception '日報の社員情報を確認できません';
  end if;

  if p_vehicle_id is not null and not exists(
    select 1 from public.vehicles v
    where v.id=p_vehicle_id and v.company_id=v_company and v.is_active=true
  ) then
    raise exception '車両を確認できません';
  end if;

  if p_route_assignment_id is not null and not exists(
    select 1 from public.route_assignments r
    where r.id=p_route_assignment_id
      and r.company_id=v_company
      and r.is_active=true
  ) then
    raise exception 'ルートを確認できません';
  end if;

  if p_odometer_km is not null and p_odometer_km<0 then
    raise exception '走行距離を確認してください';
  end if;

  if p_vehicle_id is not null and p_odometer_km is not null then
    select v.odometer_km into v_current
    from public.vehicles v
    where v.id=p_vehicle_id and v.company_id=v_company
    for update;

    if p_odometer_km<v_current then
      raise exception '現在の走行距離より小さい数値は登録できません';
    end if;

    update public.vehicles
    set odometer_km=p_odometer_km,
        updated_by=v_user,
        updated_at=now()
    where id=p_vehicle_id and company_id=v_company;
  end if;

  update public.daily_report_workers
  set vehicle_id=p_vehicle_id,
      route_assignment_id=p_route_assignment_id,
      odometer_km=p_odometer_km
  where report_id=p_report_id and worker_id=p_worker_id;
end
$function$
;
