-- Read-only function source snapshot, disposable SQL fixture only.
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
$function$
;
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
$function$
;
CREATE OR REPLACE FUNCTION private.paid_leave_sync_payroll_detail()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
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
CREATE OR REPLACE FUNCTION private.report_refresh_payroll()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a record; begin
 if old.status is distinct from new.status then
   for a in select distinct company_id,worker_id,work_date from public.attendance_entries
     where source_report_id=new.id order by company_id,worker_id,work_date loop
     perform private.refresh_automatic_payroll(a.company_id,a.worker_id,a.work_date);
   end loop;
 end if;
 return null;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.save_daily_report_signature(p_report_id uuid, p_role text, p_signer_name text, p_signature_json jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.daily_reports%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  select dr.* into r from public.daily_reports dr where dr.id=p_report_id and exists (
    select 1 from public.company_members cm where cm.company_id=dr.company_id and cm.user_id=auth.uid()
  ) for update;
  if r.id is null then raise exception 'daily report not found'; end if;
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
end
$function$
;
CREATE OR REPLACE FUNCTION public.sign_daily_report(p_report_id uuid, p_signer_name text, p_signature_json jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_user_id uuid:=auth.uid();
  v_company_id uuid;
  v_site_id uuid;
  v_route_id uuid;
  v_date date;
  v_detail record;
  v_entry_id uuid;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select dr.company_id,dr.site_id,dr.route_assignment_id,dr.report_date
  into v_company_id,v_site_id,v_route_id,v_date
  from public.daily_reports dr
  join public.company_members cm
    on cm.company_id=dr.company_id and cm.user_id=v_user_id
  where dr.id=p_report_id
  for update;

  if v_company_id is null then raise exception 'daily report not found'; end if;
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
CREATE OR REPLACE FUNCTION private.select_site_calculation_source(p_site_id uuid, p_output_type text, p_trade_company_id uuid, p_source text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cid uuid;
  v_customer uuid;
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
CREATE OR REPLACE FUNCTION private.confirm_payroll_review_month(p_period_start date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.payroll_confirmation_company(); first_day date:=date_trunc('month',p_period_start)::date; n int; missing int; changed int;
begin
 if p_period_start is null then raise exception 'payroll month required'; end if;
 if not private.payroll_confirmer_eligible(cid,auth.uid(),first_day) then raise exception 'payroll visibility required'; end if;
 perform 1 from public.companies where id=cid for update;
 perform 1 from public.payroll_statements where company_id=cid and period_start=first_day order by id for update;
 select count(*),count(*) filter(where rv.checked_revision is distinct from ps.revision) into n,missing
 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id left join public.payroll_statement_reviews rv on rv.statement_id=ps.id and rv.reviewer_id=auth.uid()
 where ps.company_id=cid and ps.period_start=first_day and w.affiliation::text='employee';
 if n=0 then raise exception 'no payroll statements'; end if;
 if (current_timestamp at time zone 'Asia/Tokyo')::date<(select max(period_end) from public.payroll_statements where company_id=cid and period_start=first_day) then raise exception 'confirmation opens at period end'; end if;
 if missing>0 then raise exception 'check all employee statements before confirmation'; end if;
 with changed_rows as(update public.payroll_statement_reviews rv set confirmed_revision=ps.revision,confirmed_at=clock_timestamp(),updated_at=clock_timestamp()
 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id
 where rv.statement_id=ps.id and rv.reviewer_id=auth.uid() and ps.company_id=cid and ps.period_start=first_day and w.affiliation::text='employee' and rv.checked_revision=ps.revision and (rv.confirmed_revision is distinct from ps.revision or rv.confirmed_at is null)
 returning rv.statement_id,rv.confirmed_revision,rv.confirmed_at)
 insert into public.payroll_confirmation_history(company_id,statement_id,reviewer_id,revision,action,created_at)
 select cid,statement_id,auth.uid(),confirmed_revision,'confirmed',confirmed_at from changed_rows;
 get diagnostics changed=row_count; return changed;
end $function$
;
CREATE OR REPLACE FUNCTION public.cancel_payroll_review_month(p_period_start date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.payroll_confirmation_company();
begin
 perform 1 from public.companies where id=cid for update;
 with changed_rows as(update public.payroll_statement_reviews rv set confirmed_revision=null,confirmed_at=null,updated_at=clock_timestamp() from public.payroll_statements ps
 where rv.statement_id=ps.id and rv.reviewer_id=auth.uid() and ps.company_id=cid and ps.period_start=date_trunc('month',p_period_start)::date and rv.confirmed_at is not null returning rv.statement_id,ps.revision)
 insert into public.payroll_confirmation_history(company_id,statement_id,reviewer_id,revision,action) select cid,statement_id,auth.uid(),revision,'cancelled' from changed_rows;
end $function$
;
CREATE OR REPLACE FUNCTION public.set_payroll_confirmers(p_user_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid; n int; u uuid; pos int:=0;
begin
 if not private.account_access_allowed() then raise exception 'authentication required'; end if;
 select member.company_id into cid from public.company_members member where member.user_id=auth.uid() and member.role::text in ('owner','admin') limit 1;
 if cid is null then raise exception 'company administrator required'; end if;
 n:=coalesce(array_length(p_user_ids,1),0);
 if n not between 1 and 3 or (select count(distinct x) from unnest(p_user_ids)x)<>n then raise exception 'select 1 to 3 unique confirmers'; end if;
 perform 1 from public.companies where id=cid for update;
 foreach u in array p_user_ids loop
 if not exists(select 1 from public.company_members cm where cm.company_id=cid and cm.user_id=u and cm.role::text in ('owner','admin','manager','viewer')) then raise exception 'invalid company confirmer'; end if;
 if not private.payroll_confirmer_eligible(cid,u,null) then raise exception 'サブ管理者を確認者にするには、全社員の給与閲覧権限が必要です。'; end if;
 end loop;
 delete from public.payroll_confirmers where company_id=cid;
 foreach u in array p_user_ids loop pos:=pos+1; insert into public.payroll_confirmers values(cid,pos,u); end loop;
end $function$
;
CREATE OR REPLACE FUNCTION public.save_daily_report_signature(p_report_id uuid, p_role text, p_signer_name text, p_signature_json jsonb)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.save_daily_report_signature(p_report_id,p_role,p_signer_name,p_signature_json);
$function$
;
CREATE OR REPLACE FUNCTION public.save_trade_company_contract(p_trade_company_id uuid, p_contract_method text, p_daily_rate_yen integer DEFAULT 0, p_monthly_rate_yen integer DEFAULT 0, p_square_meter_unit_price_yen integer DEFAULT 0, p_square_meter_quantity numeric DEFAULT 0, p_contract_amount_yen integer DEFAULT 0)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ select private.save_trade_company_contract(
  p_trade_company_id,p_contract_method,p_daily_rate_yen,p_monthly_rate_yen,
  p_square_meter_unit_price_yen,p_square_meter_quantity,p_contract_amount_yen
) $function$
;
CREATE OR REPLACE FUNCTION public.select_site_calculation_source(p_site_id uuid, p_output_type text, p_trade_company_id uuid, p_source text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ select private.select_site_calculation_source(
  p_site_id,p_output_type,p_trade_company_id,p_source
) $function$
;
revoke all on function private.report_refresh_payroll() from public,anon,authenticated;
revoke all on function private.save_daily_report_signature(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function private.save_daily_report_signature(uuid,text,text,jsonb) to authenticated;
revoke all on function private.save_trade_company_contract(uuid,text,integer,integer,integer,numeric,integer) from public,anon,authenticated;
revoke all on function public.save_daily_report_signature(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.save_daily_report_signature(uuid,text,text,jsonb) to authenticated;
revoke all on function public.save_trade_company_contract(uuid,text,integer,integer,integer,numeric,integer) from public,anon,authenticated;
grant execute on function public.save_trade_company_contract(uuid,text,integer,integer,integer,numeric,integer) to authenticated;
revoke all on function public.sign_daily_report(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.sign_daily_report(uuid,text,jsonb) to authenticated;
revoke all on function private.select_site_calculation_source(uuid,text,uuid,text) from public,anon,authenticated;
revoke all on function public.select_site_calculation_source(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.select_site_calculation_source(uuid,text,uuid,text) to authenticated;
CREATE OR REPLACE FUNCTION private.clear_daily_report_signatures_on_draft()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.status = 'draft' and (
    new.work_description is distinct from old.work_description or
    new.site_id is distinct from old.site_id or new.report_date is distinct from old.report_date or
    new.signature_json is null and old.signature_json is not null
  ) then
    new.representative_signature_json := null;
    new.representative_signer_name := null;
    new.supervisor_signature_json := null;
    new.supervisor_signer_name := null;
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.clear_daily_report_signatures_on_workers()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.daily_reports set representative_signature_json=null, representative_signer_name=null,
    supervisor_signature_json=null, supervisor_signer_name=null
  where id=coalesce(new.report_id, old.report_id) and status='draft';
  return coalesce(new,old);
end;
$function$
;
CREATE OR REPLACE FUNCTION private.guard_daily_report_shift_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if row(NEW.company_id,NEW.report_date,NEW.site_id,NEW.route_assignment_id)
     is distinct from row(OLD.company_id,OLD.report_date,OLD.site_id,OLD.route_assignment_id)
     and exists (
       select 1 from public.attendance_verifications evidence
       where evidence.daily_report_id=OLD.id
         and (evidence.work_date is not null or evidence.source_clock_in_id is not null
           or exists (select 1 from public.attendance_verifications child
                      where child.source_clock_in_id=evidence.id))
     ) then
    raise exception '勤務日・現場・ルートの変更は勤怠管理から修正してください';
  end if;
  return NEW;
end $function$
;
CREATE OR REPLACE FUNCTION private.reject_direct_attendance_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$begin
 if current_user in ('authenticated','anon') then raise exception '日報の削除操作を使用してください。';end if;
 return old;
end;$function$
;

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
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;

  select m.company_id into v_company
  from public.company_members m
  where m.user_id=v_user
  limit 1;
  if v_company is null then raise exception '会社への所属が必要です'; end if;

  select d.status into v_status
  from public.daily_reports d
  where d.id=p_report_id and d.company_id=v_company
  limit 1;
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
CREATE OR REPLACE FUNCTION public.save_daily_report_vehicle_usage(p_report_id uuid, p_worker_id uuid, p_vehicle_id uuid, p_route_assignment_id uuid, p_odometer_km numeric)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.save_daily_report_vehicle_usage(
    p_report_id,p_worker_id,p_vehicle_id,p_route_assignment_id,p_odometer_km
  )
$function$
;
revoke all on function public.save_daily_report_vehicle_usage(uuid,uuid,uuid,uuid,numeric) from public,anon;
grant execute on function public.save_daily_report_vehicle_usage(uuid,uuid,uuid,uuid,numeric) to authenticated;
