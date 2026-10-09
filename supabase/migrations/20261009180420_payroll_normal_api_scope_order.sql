-- Source-only bounded normal payroll mutation scope ordering.
DO $$ BEGIN
 if not exists(select 1 from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attname='worker_id' where i.indrelid='public.worker_payroll_settings'::regclass and i.indisunique and i.indisvalid and i.indpred is null and i.indexprs is null and i.indnkeyatts=1 and i.indkey[0]=a.attnum) then raise exception 'settings worker identity prerequisite differs';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.professional_portal(text,jsonb)') and md5(prosrc)='dbc65b8cfc90825affac7ac237e484e9' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'professional payroll writer prerequisite differs';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.settings_refresh_payroll()') and md5(prosrc)='e54f70cde281b21c0947b29faba0cde8' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'settings refresh prerequisite differs';end if;
 if exists(select 1 from pg_trigger where tgrelid='public.worker_payroll_settings'::regclass and not tgisinternal and tgname='payroll_scope_before_settings') then raise exception 'settings scope trigger already exists';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('payroll_scope_private.lock_scopes(jsonb,boolean)') and md5(prosrc)='1bce36e2e59eeb8e0144c5743b8ea800' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'scope lock prerequisite differs';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.cancel_daily_report(jsonb)') and md5(prosrc)='9b556d831e1a7f12331d77eb039120c9' and prosecdef is true and proconfig=ARRAY['search_path=""']) then raise exception 'normal payroll prerequisite differs: private.cancel_daily_report(jsonb)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.cancel_daily_report(jsonb)') and md5(prosrc)='b0dce6a7eecea9e76d62c0c8c47d5304' and prosecdef is false and proconfig=ARRAY['search_path=""']) then raise exception 'normal payroll prerequisite differs: public.cancel_daily_report(jsonb)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.decide_attendance_correction_request(uuid,text,text)') and md5(prosrc)='87b46c1df058ad8b455bcd843cf7f851' and prosecdef is true and proconfig=ARRAY['search_path=public, private, pg_temp']) then raise exception 'normal payroll prerequisite differs: public.decide_attendance_correction_request(uuid,text,text)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.decide_paid_leave_request(uuid,text,text)') and md5(prosrc)='5bc75f0feb5afa3ac10fedeefdc08bfa' and prosecdef is true and proconfig=ARRAY['search_path=public, private, pg_temp']) then raise exception 'normal payroll prerequisite differs: public.decide_paid_leave_request(uuid,text,text)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.force_manage_attendance(text,jsonb)') and md5(prosrc)='077b4a1373689071c84e0a14f0a8d824' and prosecdef is true and proconfig=ARRAY['search_path=public, private, pg_temp']) then raise exception 'normal payroll prerequisite differs: public.force_manage_attendance(text,jsonb)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.submit_paid_leave_request(date[],text)') and md5(prosrc)='fd056bb58c14e5f188f3451a7ae27172' and prosecdef is true and proconfig=ARRAY['search_path=public, private, pg_temp']) then raise exception 'normal payroll prerequisite differs: public.submit_paid_leave_request(date[],text)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.submit_retrospective_paid_leave_request(date[],text)') and md5(prosrc)='a685b11eddcabec336e43269979a43eb' and prosecdef is true and proconfig=ARRAY['search_path=public, private, pg_temp']) then raise exception 'normal payroll prerequisite differs: public.submit_retrospective_paid_leave_request(date[],text)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)') and md5(prosrc)='b22883565c0913ffb4d7695ca89e8da7' and prosecdef is true and proconfig=ARRAY['search_path=public, private, pg_temp']) then raise exception 'normal payroll prerequisite differs: public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'; end if;
END $$;

-- The existing internal lock helper remains private and retains its grants.
create or replace function payroll_scope_private.pending_leave_capture(p_batch uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('rows',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),
 'scopes',coalesce(jsonb_agg(jsonb_build_object('cid',r.company_id,'wid',r.worker_id,'day',r.leave_date) order by r.company_id,r.worker_id,r.leave_date,r.id),'[]'))
 from public.paid_leave_requests r where r.batch_id=p_batch and r.status='pending'
$$;
revoke all on function payroll_scope_private.pending_leave_capture(uuid) from public,anon,authenticated;
create or replace function payroll_scope_private.correction_capture(p_request uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 with req as(select * from public.attendance_correction_requests where id=p_request),
 items as(select i.* from public.attendance_correction_items i join req on i.request_id=req.id and i.company_id=req.company_id),
 entries as(select ae.* from public.attendance_entries ae join items i on ae.id=i.attendance_entry_id and ae.company_id=i.company_id),
 reports as(select distinct source_report_id id from entries where source_report_id is not null),
 scopes as(
 select company_id cid,worker_id wid,work_date as scope_day from entries
 union select i.company_id,(i.proposed_snapshot->>'workerId')::uuid,replace(i.proposed_snapshot->>'date','/','-')::date from items i join req on true where req.request_kind='past_attendance' or i.attendance_entry_id is null
 union select (s->>'cid')::uuid,(s->>'wid')::uuid,(s->>'day')::date from reports r cross join lateral jsonb_array_elements(payroll_scope_private.report_sources(r.id)->'scopes') s)
 select jsonb_build_object('request',(select to_jsonb(req) from req),
 'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.id) from items i),'[]'),
 'entries',coalesce((select jsonb_agg(to_jsonb(e) order by e.id) from entries e),'[]'),
 'reports',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'source',payroll_scope_private.report_sources(r.id)) order by r.id) from reports r),'[]'),
 'scopes',coalesce((select jsonb_agg(jsonb_build_object('cid',cid,'wid',wid,'day',scope_day) order by cid,wid,scope_day) from scopes),'[]'))
$$;
revoke all on function payroll_scope_private.correction_capture(uuid) from public,anon,authenticated;

create or replace function payroll_scope_private.force_capture(p_company uuid,p_items jsonb) returns jsonb
language sql stable security definer set search_path='' as $$
 with targets as(select distinct p_company cid,(v->>'worker_id')::uuid wid,(v->>'date')::date as scope_day from jsonb_array_elements(p_items) v),
 reports as(select distinct dr.id from public.daily_reports dr join public.daily_report_workers rw on rw.report_id=dr.id join targets t on dr.company_id=t.cid and dr.report_date=t.scope_day and rw.worker_id=t.wid
 union select dr.id from public.daily_reports dr cross join jsonb_array_elements(p_items) v where dr.company_id=p_company and dr.report_date=(v->>'date')::date and dr.site_id=nullif(v->>'site_id','')::uuid and coalesce(nullif(v->>'mode',''),'work')='work'),
 scopes as(select * from targets union select (s->>'cid')::uuid,(s->>'wid')::uuid,(s->>'day')::date from reports r cross join lateral jsonb_array_elements(payroll_scope_private.report_sources(r.id)->'scopes') s)
 select jsonb_build_object('reports',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'source',payroll_scope_private.report_sources(r.id)) order by r.id) from reports r),'[]'),
 'entries',coalesce((select jsonb_agg(to_jsonb(a) order by a.id) from public.attendance_entries a join targets t on a.company_id=t.cid and a.worker_id=t.wid and a.work_date=t.scope_day),'[]'),
 'leave',coalesce((select jsonb_agg(to_jsonb(a) order by a.id) from public.paid_leave_requests a join targets t on a.company_id=t.cid and a.worker_id=t.wid and a.leave_date=t.scope_day),'[]'),
 'scopes',coalesce((select jsonb_agg(jsonb_build_object('cid',cid,'wid',wid,'day',scope_day) order by cid,wid,scope_day) from scopes),'[]'))
$$;
revoke all on function payroll_scope_private.force_capture(uuid,jsonb) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION private.cancel_daily_report(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare scope_before jsonb;c uuid;rid uuid:=(p_data->>'report_id')::uuid;wid uuid;wids uuid[];sid uuid;day date;
 v jsonb;r jsonb;e jsonb;rw jsonb;snap jsonb;fingerprint text;reason text:=trim(coalesce(p_data->>'reason',''));blocked text;customer uuid;outid uuid;wn text;sn text;
begin
 select company_id into c from public.company_members where user_id=auth.uid() and role::text in ('owner','admin') limit 1;
 if c is null then raise exception '管理者だけが出勤を取り消せます。';end if;
 if not exists(select 1 from public.daily_reports where id=rid and company_id=c) then raise exception '日報が見つかりません。';end if;
 scope_before:=payroll_scope_private.report_sources(rid);
 if exists(select 1 from jsonb_array_elements(scope_before->'scopes') captured_scope where (captured_scope->>'cid')::uuid<>c) then raise exception 'payroll company scope mismatch';end if;
 perform payroll_scope_private.lock_scopes(scope_before->'scopes');
 select site_id,report_date into sid,day from public.daily_reports where id=rid and company_id=c for update;
 if payroll_scope_private.report_sources(rid) is distinct from scope_before then raise exception 'daily report payroll scope changed' using errcode='40001';end if;
 if sid is null then raise exception '日報が見つかりません。';end if;
 select name,customer_id into sn,customer from public.sites where id=sid and company_id=c;
 select coalesce(array_agg(worker_id),'{}') into wids from public.daily_report_workers where report_id=rid;
 perform 1 from public.attendance_entries where company_id=c and source_report_id=rid for update;
 perform 1 from public.attendance_verifications where id=any(private.report_clock_ids(c,wids,sid,day)) for update;
 select coalesce(jsonb_agg(to_jsonb(a) order by a.id),'[]') into v from public.attendance_verifications a where id=any(private.report_clock_ids(c,wids,sid,day));
 select coalesce(jsonb_agg(to_jsonb(a) order by a.id),'[]') into e from public.attendance_entries a where company_id=c and source_report_id=rid;
 select jsonb_build_array(to_jsonb(d)) into r from public.daily_reports d where id=rid;
 select coalesce(jsonb_agg(to_jsonb(w) order by w.worker_id),'[]') into rw from public.daily_report_workers w where w.report_id=rid;
 snap:=jsonb_build_object('verifications',v,'entries',e,'reports',r,'report_workers',rw);fingerprint:=md5(snap::text);
 if exists(select 1 from public.attendance_entries where company_id=c and worker_id=any(wids) and site_id=sid and work_date=day and source_report_id is distinct from rid) then blocked:='日報と未連携の出勤記録があります。対応関係の確認が必要です。';end if;
 if exists(select 1 from public.attendance_entries where company_id=c and source_report_id=rid and (work_date<>day or site_id<>sid or not(worker_id=any(wids)))) then blocked:='日報の修正が未確定です。再署名して出勤表との対応を確認してください。';end if;
 if exists(select 1 from public.attendance_verifications a where a.company_id=c and a.worker_id=any(wids) and a.site_id=sid and a.event_type='clock_out' and (a.confirmed_at at time zone 'Asia/Tokyo')::date=day and not exists(select 1 from public.attendance_verifications b where b.company_id=c and b.worker_id=a.worker_id and b.event_type='clock_in' and b.confirmed_at<=a.confirmed_at and b.confirmed_at>=a.confirmed_at-interval '36 hours')) then blocked:='退勤に対応する出勤が見つかりません。打刻の対応確認が必要です。';end if;
 perform 1 from public.invoices i where i.company_id=c and i.customer_id=customer and day between i.billing_period_start and i.billing_period_end for update;
 perform 1 from public.payroll_statements p where p.company_id=c and p.worker_id=any(wids) and day between p.period_start and p.period_end for update;
 if exists(select 1 from public.payroll_statements p where p.company_id=c and p.worker_id=any(wids) and day between p.period_start and p.period_end and (p.workflow_state<>'draft' or not p.automatic_calculation)) then blocked:='確定済みまたは手動編集の給与明細があります。先に給与明細を確認してください。';end if;
 if exists(select 1 from public.invoices i where i.company_id=c and i.customer_id=customer and day between i.billing_period_start and i.billing_period_end and (i.status<>'draft' or i.finalized_at is not null or not i.automatic_calculation)) then blocked:='確定済みまたは手動編集の請求書があります。先に請求書を確認してください。';end if;
 if coalesce(p_data->>'action','preview')='preview' then return jsonb_build_object('fingerprint',fingerprint,'worker_count',cardinality(wids),'report_date',day,'site_name',sn,'clock_count',jsonb_array_length(v),'attendance_count',jsonb_array_length(e),'report_count',jsonb_array_length(r),'blocked',blocked);end if;
 if p_data->>'action'<>'cancel' or blocked is not null then raise exception '%',coalesce(blocked,'操作を確認してください。');end if;
 if p_data->>'fingerprint' is distinct from fingerprint then raise exception 'データが更新されました。内容をもう一度確認してください。';end if;
 if length(reason) not between 1 and 500 then raise exception '取消理由を1〜500文字で入力してください。';end if;
 insert into private.daily_report_cancellations(company_id,actor_id,report_id,site_id,work_date,reason,snapshot) values(c,auth.uid(),rid,sid,day,reason,snap) returning id into outid;
 -- Delete only the records included in the reviewed snapshot. Concurrent new clock-ins remain intact.
 delete from public.attendance_entries where id in(select (x->>'id')::uuid from jsonb_array_elements(e)x);
 delete from public.daily_report_workers where report_id in(select (x->>'id')::uuid from jsonb_array_elements(r)x);
 delete from public.daily_reports where id in(select (x->>'id')::uuid from jsonb_array_elements(r)x);
 delete from public.attendance_verifications where id in(select (x->>'id')::uuid from jsonb_array_elements(v)x);
 return jsonb_build_object('id',outid,'cancelled',true);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.decide_attendance_correction_request(p_request_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  scope_before jsonb;
  v_actor uuid := auth.uid();
  v_request public.attendance_correction_requests%rowtype;
  v_assignee_count integer;
  v_item record;
  v_site_id uuid;
  v_worker_id uuid;
  v_source_report_id uuid;
  v_work_date date;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if p_decision not in ('approve','reject') then raise exception 'invalid decision'; end if;
  select * into v_request from public.attendance_correction_requests where id=p_request_id;
  if not found or v_request.status<>'submitted' then raise exception 'submitted attendance request not found';end if;
  if not exists(select 1 from public.company_approval_assignees where company_id=v_request.company_id and user_id=v_actor) then raise exception 'approval assignee permission required';end if;
  scope_before:=payroll_scope_private.correction_capture(p_request_id);
  if exists(select 1 from jsonb_array_elements(scope_before->'scopes') v where (v->>'cid')::uuid<>v_request.company_id) then raise exception 'payroll company scope mismatch';end if;
  perform payroll_scope_private.lock_scopes(scope_before->'scopes');
  select * into v_request from public.attendance_correction_requests
  where id=p_request_id for update;
  if not found or v_request.status <> 'submitted' then
    raise exception 'submitted attendance request not found';
  end if;
  if not exists (
    select 1 from public.company_approval_assignees caa
    where caa.company_id=v_request.company_id and caa.user_id=v_actor
  ) then raise exception 'approval assignee permission required'; end if;
  select count(*) into v_assignee_count
  from public.company_approval_assignees where company_id=v_request.company_id;
  if v_request.requested_by=v_actor and v_assignee_count > 1 then
    raise exception 'requester cannot approve own request';
  end if;

  perform 1 from public.daily_reports where id in(select (v->>'id')::uuid from jsonb_array_elements(scope_before->'reports') v) order by id for update;
  if payroll_scope_private.correction_capture(p_request_id) is distinct from scope_before then raise exception 'attendance correction scope changed' using errcode='40001';end if;
  if p_decision='reject' then
    update public.attendance_correction_requests
    set status='rejected',reviewed_by=v_actor,reviewed_at=now(),
        review_note=nullif(trim(coalesce(p_note,'')),''),updated_at=now()
    where id=p_request_id;
    perform private.enqueue_notification(
      v_request.company_id,v_request.requested_by,'warning',
      case when v_request.request_kind='past_attendance'
        then '過去のまとめて出勤申請が却下されました'
        else '過去勤怠の修正申請が却下されました' end,
      case when v_request.request_kind='past_attendance'
        then '過去のまとめて出勤申請が却下されました。内容を確認してください。'
        else 'まとめて修正申請が却下されました。内容を確認してください。' end,
      'attendance_correction_request',p_request_id
    );
    return 'rejected';
  end if;

  for v_item in
    select * from public.attendance_correction_items
    where request_id=p_request_id and company_id=v_request.company_id
    order by created_at
  loop
    if v_request.request_kind='past_attendance'
       or v_item.attendance_entry_id is null then
      v_worker_id := (v_item.proposed_snapshot->>'workerId')::uuid;
      v_site_id := (v_item.proposed_snapshot->>'siteId')::uuid;
      v_work_date := replace(v_item.proposed_snapshot->>'date','/','-')::date;
      insert into public.attendance_entries(
        company_id,work_date,worker_id,site_id,work_category,
        base_man_days,overtime_hours,early_hours,night_hours,
        allowance_amount,allowance_names,notes,created_by,updated_by
      ) values (
        v_request.company_id,
        v_work_date,
        v_worker_id,v_site_id,
        coalesce(nullif(v_item.proposed_snapshot->>'workCategory',''),'day'),
        coalesce((v_item.proposed_snapshot->>'manDays')::numeric,1),
        coalesce((v_item.proposed_snapshot->>'overtimeHours')::numeric,0),
        coalesce((v_item.proposed_snapshot->>'earlyHours')::numeric,0),
        coalesce((v_item.proposed_snapshot->>'nightHours')::numeric,0),
        coalesce((v_item.proposed_snapshot->>'allowanceYen')::integer,0),
        array(
          select jsonb_array_elements_text(
            coalesce(v_item.proposed_snapshot->'allowanceNames','[]'::jsonb)
          )
        ),
        nullif(trim(coalesce(v_item.proposed_snapshot->>'notes','')),''),
        v_request.requested_by,v_actor
      );

      update public.paid_leave_requests
      set status='cancelled',
          reviewed_by=v_actor,
          reviewed_at=now(),
          review_note='勤務修正承認により有給を取消',
          updated_at=now()
      where company_id=v_request.company_id
        and worker_id=v_worker_id
        and leave_date=v_work_date
        and status in ('pending','approved');
    else
      select ae.source_report_id,ae.worker_id,ae.work_date
      into v_source_report_id,v_worker_id,v_work_date
      from public.attendance_entries ae
      where ae.id=v_item.attendance_entry_id
        and ae.company_id=v_request.company_id
      for update;

      select s.id into v_site_id
      from public.sites s
      where s.company_id=v_request.company_id
        and s.name=trim(coalesce(v_item.proposed_snapshot->>'siteName',''))
      limit 2;
      if v_site_id is null then raise exception 'site not found for correction item'; end if;

      update public.attendance_entries
      set site_id=v_site_id,
          work_category=coalesce(nullif(v_item.proposed_snapshot->>'workCategory',''),work_category,'day'),
          base_man_days=coalesce((v_item.proposed_snapshot->>'manDays')::numeric,base_man_days),
          overtime_hours=coalesce((v_item.proposed_snapshot->>'overtimeHours')::numeric,overtime_hours),
          early_hours=coalesce((v_item.proposed_snapshot->>'earlyHours')::numeric,early_hours),
          night_hours=coalesce((v_item.proposed_snapshot->>'nightHours')::numeric,night_hours),
          allowance_amount=coalesce((v_item.proposed_snapshot->>'allowanceYen')::integer,allowance_amount),
          allowance_names=case
            when v_item.proposed_snapshot ? 'allowanceNames' then array(
              select jsonb_array_elements_text(
                coalesce(v_item.proposed_snapshot->'allowanceNames','[]'::jsonb)
              )
            )
            else allowance_names
          end,
          notes=nullif(trim(coalesce(v_item.proposed_snapshot->>'notes','')),''),
          updated_by=v_actor,updated_at=now()
      where id=v_item.attendance_entry_id and company_id=v_request.company_id;

      update public.paid_leave_requests
      set status='cancelled',
          reviewed_by=v_actor,
          reviewed_at=now(),
          review_note='勤務修正承認により有給を取消',
          updated_at=now()
      where company_id=v_request.company_id
        and worker_id=v_worker_id
        and leave_date=v_work_date
        and status in ('pending','approved');

      if v_source_report_id is not null and v_worker_id is not null then
        update public.daily_report_workers
        set overtime_hours=coalesce((v_item.proposed_snapshot->>'overtimeHours')::numeric,overtime_hours),
            early_hours=coalesce((v_item.proposed_snapshot->>'earlyHours')::numeric,early_hours),
            night_hours=coalesce((v_item.proposed_snapshot->>'nightHours')::numeric,night_hours),
            allowance_amount=coalesce((v_item.proposed_snapshot->>'allowanceYen')::integer,allowance_amount),
            allowance_label=case
              when v_item.proposed_snapshot ? 'allowanceNames' then array_to_string(
                array(
                  select jsonb_array_elements_text(
                    coalesce(v_item.proposed_snapshot->'allowanceNames','[]'::jsonb)
                  )
                ),
                '・'
              )
              else allowance_label
            end
        where report_id=v_source_report_id and worker_id=v_worker_id;
      end if;
    end if;
  end loop;

  update public.attendance_correction_requests
  set status='approved',reviewed_by=v_actor,reviewed_at=now(),
      review_note=nullif(trim(coalesce(p_note,'')),''),updated_at=now()
  where id=p_request_id;
  perform private.enqueue_notification(
    v_request.company_id,v_request.requested_by,'approval',
    case when v_request.request_kind='past_attendance'
      then '過去のまとめて出勤が反映されました'
      else '過去勤怠の修正が反映されました' end,
    case when v_request.request_kind='past_attendance'
      then '過去のまとめて出勤申請が承認され、出勤表へ反映されました。'
      else 'まとめて修正申請が承認され、勤怠と関連日報へ反映されました。' end,
    'attendance_correction_request',p_request_id
  );
  return 'approved';
end;
$function$
;
CREATE OR REPLACE FUNCTION public.decide_paid_leave_request(p_batch_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_requested_by uuid;
  v_worker_id uuid;
  v_status text;
  v_granted numeric := 0;
  v_used numeric := 0;
  v_batch_count numeric := 0;
  scope_before jsonb;
begin
  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision';
  end if;

  select r.company_id into v_company_id from public.paid_leave_requests r where r.batch_id=p_batch_id and r.status='pending' limit 1;
  if v_company_id is null then raise exception 'pending paid leave request not found'; end if;
  if not exists(select 1 from public.company_members cm where cm.company_id=v_company_id and cm.user_id=v_actor and cm.role::text in ('owner','admin','manager')) then raise exception 'management permission required'; end if;
  scope_before:=payroll_scope_private.pending_leave_capture(p_batch_id);
  if exists(select 1 from jsonb_array_elements(scope_before->'scopes') v where (v->>'cid')::uuid<>v_company_id) then raise exception 'payroll company scope mismatch';end if;
  perform payroll_scope_private.lock_scopes(scope_before->'scopes');
  select r.company_id, r.requested_by, r.worker_id
  into v_company_id, v_requested_by, v_worker_id
  from public.paid_leave_requests r
  where r.batch_id = p_batch_id
    and r.status = 'pending'
  limit 1
  for update;

  if payroll_scope_private.pending_leave_capture(p_batch_id) is distinct from scope_before then raise exception 'paid leave scope changed' using errcode='40001'; end if;
  if v_company_id is null then
    raise exception 'pending paid leave request not found';
  end if;

  if not exists (
    select 1
    from public.company_members cm
    where cm.company_id = v_company_id
      and cm.user_id = v_actor
      and cm.role::text in ('owner','admin','manager')
  ) then
    raise exception 'management permission required';
  end if;

  if p_decision = 'approve' then
    -- Approval and attendance writers can serialize on the same worker row.
    perform 1 from public.workers w where w.id=v_worker_id and w.company_id=v_company_id for update;
    perform 1 from public.paid_leave_requests r where r.batch_id=p_batch_id
      and r.company_id=v_company_id and r.worker_id=v_worker_id and r.status='pending'
      order by r.leave_date,r.id for update;
    if exists (
      select 1 from public.paid_leave_requests r join public.attendance_entries ae
        on ae.company_id=r.company_id and ae.worker_id=r.worker_id and ae.work_date=r.leave_date
      where r.batch_id=p_batch_id and r.company_id=v_company_id
        and r.worker_id=v_worker_id and r.status='pending'
    ) then
      raise exception 'attendance exists for requested paid leave, use attendance correction first';
    end if;
    select coalesce(wps.paid_leave_granted_days, 0)
    into v_granted
    from public.worker_payroll_settings wps
    where wps.worker_id = v_worker_id and wps.company_id=v_company_id
    limit 1;
    v_granted := coalesce(v_granted, 0);

    select count(*)
    into v_used
    from public.paid_leave_requests r
    where r.worker_id = v_worker_id and r.company_id=v_company_id
      and r.status = 'approved';

    select count(*)
    into v_batch_count
    from public.paid_leave_requests r
    where r.batch_id = p_batch_id and r.company_id=v_company_id and r.worker_id=v_worker_id
      and r.status = 'pending';

    if v_used + v_batch_count > v_granted then
      raise exception 'paid leave balance exceeded';
    end if;

    v_status := 'approved';
  else
    v_status := 'rejected';
  end if;

  update public.paid_leave_requests
  set status = v_status,
      reviewed_by = v_actor,
      reviewed_at = now(),
      review_note = nullif(trim(coalesce(p_note,'')), ''),
      updated_at = now()
  where batch_id = p_batch_id and company_id=v_company_id and worker_id=v_worker_id
    and status = 'pending';

  perform private.enqueue_notification(
    v_company_id,
    v_requested_by,
    case when v_status = 'approved' then 'approval' else 'warning' end,
    case when v_status = 'approved'
      then '有給申請が承認されました'
      else '有給申請が却下されました'
    end,
    case when v_status = 'approved'
      then '申請した有給が承認されました。出勤表に反映されます。'
      else '有給申請が却下されました。内容を確認してください。'
    end,
    'paid_leave_request',
    p_batch_id
  );

  return v_status;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.force_manage_attendance(p_action text, p_items jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  scope_before jsonb;
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_role text;
  v_item jsonb;
  v_worker_id uuid;
  v_site_id uuid;
  v_date date;
  v_mode text;
  v_report_id uuid;
  v_count integer := 0;
  v_clock_in timestamptz;
  v_clock_out timestamptz;
  v_report record;
  v_entry_ids uuid[];
  v_work_description text;
begin
  if v_actor is null then
    raise exception 'authentication required';
  end if;

  select cm.company_id, cm.role::text
  into v_company_id, v_role
  from public.company_members cm
  where cm.user_id = v_actor
  limit 1;

  if v_company_id is null
     or v_role not in ('owner','admin','manager')
     or not coalesce(
       (public.current_feature_permissions()->>'can_manage_attendance')::boolean,
       false
     ) then
    raise exception 'attendance management permission required';
  end if;

  if p_action not in ('upsert','delete') then
    raise exception 'invalid attendance management action';
  end if;

  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) < 1
     or jsonb_array_length(p_items) > 500 then
    raise exception 'attendance management items must contain 1 to 500 rows';
  end if;

  if exists(select 1 from jsonb_array_elements(p_items) v where not exists(select 1 from public.workers w where w.id=(v->>'worker_id')::uuid and w.company_id=v_company_id and w.status='active')) then raise exception 'worker does not belong to company';end if;
  scope_before:=payroll_scope_private.force_capture(v_company_id,p_items);
  perform payroll_scope_private.lock_scopes(scope_before->'scopes');
  perform 1 from public.daily_reports where id in(select (v->>'id')::uuid from jsonb_array_elements(scope_before->'reports') v) order by id for update;
  if payroll_scope_private.force_capture(v_company_id,p_items) is distinct from scope_before then raise exception 'attendance management scope changed' using errcode='40001';end if;
  for v_item in
    select value from jsonb_array_elements(p_items)
  loop
    v_worker_id := nullif(v_item->>'worker_id','')::uuid;
    v_date := nullif(v_item->>'date','')::date;
    v_mode := coalesce(nullif(v_item->>'mode',''),'work');
    v_site_id := nullif(v_item->>'site_id','')::uuid;
    v_work_description := trim(coalesce(v_item->>'work_description',''));

    if v_worker_id is null or v_date is null then
      raise exception 'worker and date are required';
    end if;

    if not exists (
      select 1 from public.workers w
      where w.id = v_worker_id
        and w.company_id = v_company_id
        and w.status = 'active'
    ) then
      raise exception 'worker does not belong to company';
    end if;

    if v_mode not in ('work','paid_leave','off') then
      raise exception 'invalid attendance mode';
    end if;

    if v_mode = 'work' then
      if v_site_id is null or not exists (
        select 1 from public.sites s
        where s.id = v_site_id and s.company_id = v_company_id
      ) then
        raise exception 'site does not belong to company';
      end if;
    end if;

    -- Keep correction audit snapshots, but detach FK so forced deletion can proceed.
    select array_agg(ae.id)
    into v_entry_ids
    from public.attendance_entries ae
    where ae.company_id = v_company_id
      and ae.worker_id = v_worker_id
      and ae.work_date = v_date;

    if v_entry_ids is not null then
      update public.attendance_correction_items
      set attendance_entry_id = null
      where attendance_entry_id = any(v_entry_ids);
    end if;

    -- Remove the worker from all daily reports on the target date.
    for v_report in
      select dr.id
      from public.daily_reports dr
      join public.daily_report_workers drw on drw.report_id = dr.id
      where dr.company_id = v_company_id
        and dr.report_date = v_date
        and drw.worker_id = v_worker_id
        and dr.id in(select (v->>'id')::uuid from jsonb_array_elements(scope_before->'reports') v)
      order by dr.id
      for update of dr
    loop
      delete from public.daily_report_workers
      where report_id = v_report.id
        and worker_id = v_worker_id;

      update public.attendance_entries
      set source_report_id = null
      where source_report_id = v_report.id
        and worker_id = v_worker_id;

      -- Delete the target worker's complete linked shift before report removal;
      -- detaching would lose the next-day end timestamp's work-date ownership.
      delete from public.attendance_verifications
      where company_id = v_company_id and worker_id = v_worker_id
        and (daily_report_id = v_report.id or work_date = v_date);

      if not exists (
        select 1 from public.daily_report_workers
        where report_id = v_report.id
      ) then
        update public.attendance_entries
        set source_report_id = null
        where source_report_id = v_report.id;

        delete from public.daily_reports
        where id = v_report.id;
      else
        update public.daily_reports
        set status = 'draft',
            signer_name = null,
            signature_json = null,
            signed_at = null,
            representative_signature_json = null,
            representative_signer_name = null,
            supervisor_signature_json = null,
            supervisor_signer_name = null,
            updated_by = v_actor,
            updated_at = now()
        where id = v_report.id;
      end if;
    end loop;

    delete from public.attendance_verifications
    where company_id = v_company_id
      and worker_id = v_worker_id
      and (
        exists (
          select 1 from public.daily_reports dr
          where dr.id = attendance_verifications.daily_report_id
            and dr.company_id = v_company_id and dr.report_date = v_date
        )
        or (
          daily_report_id is null
          and coalesce(work_date,(confirmed_at at time zone 'Asia/Tokyo')::date)=v_date
        )
      );

    delete from public.attendance_entries
    where company_id = v_company_id
      and worker_id = v_worker_id
      and work_date = v_date;

    update public.paid_leave_requests
    set status = 'cancelled',
        reviewed_by = v_actor,
        reviewed_at = now(),
        review_note = '勤怠管理から強制更新',
        updated_at = now()
    where company_id = v_company_id
      and worker_id = v_worker_id
      and leave_date = v_date
      and status in ('pending','approved');

    if p_action = 'delete' or v_mode = 'off' then
      v_count := v_count + 1;
      continue;
    end if;

    if v_mode = 'paid_leave' then
      insert into public.paid_leave_requests(
        batch_id,
        company_id,
        worker_id,
        requested_by,
        leave_date,
        reason,
        status,
        reviewed_by,
        reviewed_at,
        review_note
      ) values (
        gen_random_uuid(),
        v_company_id,
        v_worker_id,
        v_actor,
        v_date,
        nullif(trim(coalesce(v_item->>'notes','')),''),
        'approved',
        v_actor,
        now(),
        '勤怠管理から直接登録'
      );
      v_count := v_count + 1;
      continue;
    end if;

    select dr.id
    into v_report_id
    from public.daily_reports dr
    where dr.company_id = v_company_id
      and dr.report_date = v_date
      and dr.site_id = v_site_id
    limit 1;
    if v_report_id is not null then
      if not exists(select 1 from jsonb_array_elements(scope_before->'reports') v where (v->>'id')::uuid=v_report_id) then raise exception 'attendance report target changed' using errcode='40001';end if;
      perform 1 from public.daily_reports where id=v_report_id for update;
    end if;

    if v_report_id is null then
      insert into public.daily_reports(
        company_id,
        site_id,
        report_date,
        work_description,
        status,
        created_by,
        updated_by
      ) values (
        v_company_id,
        v_site_id,
        v_date,
        nullif(v_work_description,''),
        'draft',
        v_actor,
        v_actor
      )
      returning id into v_report_id;
    else
      update public.daily_reports
      set work_description = case
            when v_work_description = '' then work_description
            else v_work_description
          end,
          status = 'draft',
          signer_name = null,
          signature_json = null,
          signed_at = null,
          representative_signature_json = null,
          representative_signer_name = null,
          supervisor_signature_json = null,
          supervisor_signer_name = null,
          updated_by = v_actor,
          updated_at = now()
      where id = v_report_id;
    end if;

    insert into public.daily_report_workers(
      report_id,
      worker_id,
      overtime_hours,
      early_hours,
      night_hours,
      allowance_amount,
      allowance_label,
      work_category
    ) values (
      v_report_id,
      v_worker_id,
      greatest(coalesce((v_item->>'overtime_hours')::numeric,0),0),
      greatest(coalesce((v_item->>'early_hours')::numeric,0),0),
      greatest(coalesce((v_item->>'night_hours')::numeric,0),0),
      0,
      nullif(array_to_string(
        array(
          select jsonb_array_elements_text(
            coalesce(v_item->'allowance_names','[]'::jsonb)
          )
        ),
        '・'
      ),''),
      'day'
    )
    on conflict (report_id, worker_id)
    do update set
      overtime_hours = excluded.overtime_hours,
      early_hours = excluded.early_hours,
      night_hours = excluded.night_hours,
      allowance_amount = excluded.allowance_amount,
      allowance_label = excluded.allowance_label,
      work_category = excluded.work_category;

    insert into public.attendance_entries(
      company_id,
      work_date,
      worker_id,
      site_id,
      base_man_days,
      overtime_hours,
      early_hours,
      night_hours,
      allowance_amount,
      allowance_names,
      notes,
      created_by,
      updated_by,
      work_category,
      source_report_id
    ) values (
      v_company_id,
      v_date,
      v_worker_id,
      v_site_id,
      greatest(coalesce((v_item->>'man_days')::numeric,1),0),
      greatest(coalesce((v_item->>'overtime_hours')::numeric,0),0),
      greatest(coalesce((v_item->>'early_hours')::numeric,0),0),
      greatest(coalesce((v_item->>'night_hours')::numeric,0),0),
      0,
      array(
        select jsonb_array_elements_text(
          coalesce(v_item->'allowance_names','[]'::jsonb)
        )
      ),
      nullif(trim(coalesce(v_item->>'notes','')),''),
      v_actor,
      v_actor,
      'day',
      v_report_id
    );

    v_clock_in := null;
    v_clock_out := null;
    if nullif(v_item->>'clock_in','') is not null then
      v_clock_in := (v_date::text || ' ' || (v_item->>'clock_in'))::timestamp
        at time zone 'Asia/Tokyo';
    end if;
    if nullif(v_item->>'clock_out','') is not null then
      v_clock_out := (v_date::text || ' ' || (v_item->>'clock_out'))::timestamp
        at time zone 'Asia/Tokyo';
    end if;

    -- Times are entered against one work date. An earlier end time is next day.
    -- Equal times and an end time without a start retain their existing meaning.
    if v_clock_in is not null and v_clock_out is not null
       and v_clock_out < v_clock_in then
      v_clock_out := v_clock_out + interval '1 day';
    end if;

    if v_clock_in is not null then
      insert into public.attendance_verifications(
        company_id,
        worker_id,
        site_id,
        event_type,
        verification_mode,
        confirmed_at,
        proximity_status,
        note,
        created_by,
        daily_report_id
      ) values (
        v_company_id,
        v_worker_id,
        v_site_id,
        'clock_in',
        'manual',
        v_clock_in,
        'not_checked',
        '勤怠管理から直接登録',
        v_actor,
        v_report_id
      );
    end if;

    if v_clock_out is not null then
      insert into public.attendance_verifications(
        company_id,
        worker_id,
        site_id,
        event_type,
        verification_mode,
        confirmed_at,
        proximity_status,
        note,
        created_by,
        daily_report_id
      ) values (
        v_company_id,
        v_worker_id,
        v_site_id,
        'clock_out',
        'manual',
        v_clock_out,
        'not_checked',
        '勤怠管理から直接登録',
        v_actor,
        v_report_id
      );
    end if;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.submit_paid_leave_request(p_dates date[], p_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_worker_id uuid;
  v_company_id uuid;
  v_batch_id uuid := gen_random_uuid();
  v_date date;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_granted numeric := 0;
  v_used numeric := 0;
  v_pending numeric := 0;
  v_requested_count integer;
  v_recipient record;
begin
  if v_actor is null then
    raise exception 'authentication required';
  end if;

  if p_dates is null or cardinality(p_dates) < 1 then
    raise exception 'at least one leave date is required';
  end if;
  if cardinality(p_dates) > 31 then
    raise exception 'too many leave dates';
  end if;

  select w.id, w.company_id
  into v_worker_id, v_company_id
  from public.workers w
  join public.company_members cm
    on cm.company_id = w.company_id
   and cm.user_id = v_actor
  where w.user_id = v_actor
    and w.status = 'active'
  limit 1;

  if v_worker_id is null then
    raise exception 'worker profile not found';
  end if;

  perform payroll_scope_private.lock_scopes(coalesce((select jsonb_agg(jsonb_build_object('cid',v_company_id,'wid',v_worker_id,'day',requested_day)) from unnest(p_dates) as requested_day),'[]'));
  select coalesce(wps.paid_leave_granted_days, 0)
  into v_granted
  from public.worker_payroll_settings wps
  where wps.worker_id = v_worker_id
  limit 1;
  v_granted := coalesce(v_granted, 0);

  select coalesce(count(*), 0)
  into v_used
  from public.paid_leave_requests r
  where r.worker_id = v_worker_id
    and r.status = 'approved';

  select coalesce(count(*), 0)
  into v_pending
  from public.paid_leave_requests r
  where r.worker_id = v_worker_id
    and r.status = 'pending';

  select count(distinct d)
  into v_requested_count
  from unnest(p_dates) as d;

  if v_requested_count < 1 then
    raise exception 'at least one leave date is required';
  end if;

  if v_used + v_pending + v_requested_count > v_granted then
    raise exception 'paid leave balance exceeded';
  end if;

  for v_date in select distinct d from unnest(p_dates) as d order by d
  loop
    if v_date <= v_today then
      raise exception 'paid leave request must use a future date';
    end if;

    if exists (
      select 1
      from public.paid_leave_requests r
      where r.company_id = v_company_id
        and r.worker_id = v_worker_id
        and r.leave_date = v_date
        and r.status in ('pending','approved')
    ) then
      raise exception 'paid leave already requested for %', v_date;
    end if;

    insert into public.paid_leave_requests(
      batch_id, company_id, worker_id, requested_by, leave_date, reason
    ) values (
      v_batch_id, v_company_id, v_worker_id, v_actor, v_date,
      nullif(trim(coalesce(p_reason,'')), '')
    );
  end loop;

  for v_recipient in
    select cm.user_id
    from public.company_members cm
    where cm.company_id = v_company_id
      and cm.role::text in ('owner','admin','manager')
  loop
    perform private.enqueue_notification(
      v_company_id,
      v_recipient.user_id,
      'approval',
      '有給申請があります',
      '有給申請が届きました。承認待ちから確認してください。',
      'paid_leave_request',
      v_batch_id
    );
  end loop;

  return v_batch_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.submit_retrospective_paid_leave_request(p_dates date[], p_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_worker_id uuid;
  v_company_id uuid;
  v_batch_id uuid := gen_random_uuid();
  v_date date;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_granted numeric := 0;
  v_used numeric := 0;
  v_pending numeric := 0;
  v_requested_count integer;
  v_recipient record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if p_dates is null or cardinality(p_dates) < 1 then
    raise exception 'at least one leave date is required';
  end if;
  if cardinality(p_dates) > 31 then raise exception 'too many leave dates'; end if;

  select w.id,w.company_id into v_worker_id,v_company_id
  from public.workers w
  join public.company_members cm
    on cm.company_id=w.company_id and cm.user_id=v_actor
  where w.user_id=v_actor and w.status='active'
  limit 1;
  if v_worker_id is null then raise exception 'worker profile not found'; end if;

  perform payroll_scope_private.lock_scopes(coalesce((select jsonb_agg(jsonb_build_object('cid',v_company_id,'wid',v_worker_id,'day',requested_day)) from unnest(p_dates) as requested_day),'[]'));
  select coalesce(wps.paid_leave_granted_days,0) into v_granted
  from public.worker_payroll_settings wps
  where wps.worker_id=v_worker_id limit 1;
  v_granted := coalesce(v_granted,0);

  select count(*) into v_used
  from public.paid_leave_requests r
  where r.worker_id=v_worker_id and r.status='approved';
  select count(*) into v_pending
  from public.paid_leave_requests r
  where r.worker_id=v_worker_id and r.status='pending';
  select count(distinct d) into v_requested_count
  from unnest(p_dates) as d;

  if v_used + v_pending + v_requested_count > v_granted then
    raise exception 'paid leave balance exceeded';
  end if;

  for v_date in select distinct d from unnest(p_dates) as d order by d
  loop
    if v_date > v_today then
      raise exception 'future paid leave must use normal paid leave request';
    end if;
    if exists (
      select 1 from public.attendance_entries ae
      where ae.worker_id=v_worker_id and ae.work_date=v_date
    ) then
      raise exception 'attendance exists for %, use attendance correction first', v_date;
    end if;
    if exists (
      select 1 from public.paid_leave_requests r
      where r.company_id=v_company_id
        and r.worker_id=v_worker_id
        and r.leave_date=v_date
        and r.status in ('pending','approved')
    ) then
      raise exception 'paid leave already requested for %', v_date;
    end if;

    insert into public.paid_leave_requests(
      batch_id,company_id,worker_id,requested_by,leave_date,reason
    ) values (
      v_batch_id,v_company_id,v_worker_id,v_actor,v_date,
      nullif(trim(coalesce(p_reason,'')),'')
    );
  end loop;

  for v_recipient in
    select cm.user_id from public.company_members cm
    where cm.company_id=v_company_id
      and cm.role::text in ('owner','admin','manager')
  loop
    perform private.enqueue_notification(
      v_company_id,v_recipient.user_id,'approval',
      '有給への勤務修正申請があります',
      '休みから有給への勤務修正申請が届きました。承認待ちから確認してください。',
      'paid_leave_request',v_batch_id
    );
  end loop;

  return v_batch_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.save_daily_report_destination_draft(p_report_id uuid, p_site_id uuid, p_route_assignment_id uuid, p_report_date date, p_work_description text, p_workers jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  scope_before jsonb; scope_new jsonb; captured_report uuid;
  v_user_id uuid:=auth.uid();
  v_company_id uuid;
  v_report_id uuid:=p_report_id;
  v_report_status text;
  v_edit_request_id uuid;
  v_worker jsonb;
  v_worker_id uuid;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_user_id
  limit 1;
  if v_company_id is null then raise exception 'company membership not found'; end if;

  if ((p_site_id is null) = (p_route_assignment_id is null)) then
    raise exception 'select exactly one workplace destination';
  end if;

  if p_site_id is not null and not exists(
    select 1 from public.sites s
    where s.id=p_site_id and s.company_id=v_company_id
  ) then
    raise exception 'site does not belong to company';
  end if;

  if p_route_assignment_id is not null and not exists(
    select 1 from public.route_assignments r
    where r.id=p_route_assignment_id
      and r.company_id=v_company_id
      and r.is_active=true
  ) then
    raise exception 'route does not belong to company';
  end if;

  if v_report_id is not null then
    captured_report:=v_report_id;
    if not exists(select 1 from public.daily_reports where id=captured_report and company_id=v_company_id) then raise exception 'daily report not found';end if;
  else
    select dr.id into captured_report from public.daily_reports dr where dr.company_id=v_company_id and dr.report_date=p_report_date and dr.site_id is not distinct from p_site_id and dr.route_assignment_id is not distinct from p_route_assignment_id limit 1;
  end if;
  scope_before:=payroll_scope_private.report_sources(captured_report);
  scope_new:=coalesce((select jsonb_agg(jsonb_build_object('cid',v_company_id,'wid',(v->>'worker_id')::uuid,'day',p_report_date)) from jsonb_array_elements(coalesce(p_workers,'[]')) v),'[]');
  if exists(select 1 from jsonb_array_elements(coalesce(scope_before->'scopes','[]')) v where (v->>'cid')::uuid<>v_company_id) then raise exception 'daily report company scope mismatch';end if;
  perform payroll_scope_private.lock_scopes(coalesce(scope_before->'scopes','[]')||scope_new);
  if captured_report is not null then
    perform 1 from public.daily_reports where id=captured_report and company_id=v_company_id for update;
    if payroll_scope_private.report_sources(captured_report) is distinct from scope_before then raise exception 'daily report payroll scope changed' using errcode='40001';end if;
  elsif exists(select 1 from public.daily_reports dr where dr.company_id=v_company_id and dr.report_date=p_report_date and dr.site_id is not distinct from p_site_id and dr.route_assignment_id is not distinct from p_route_assignment_id) then
    raise exception 'daily report target changed' using errcode='40001';
  end if;
  if v_report_id is not null then
    select dr.status into v_report_status
    from public.daily_reports dr
    where dr.id=v_report_id and dr.company_id=v_company_id
    for update;
    if not found then raise exception 'daily report not found'; end if;

    if v_report_status='signed' then
      select req.id into v_edit_request_id
      from public.daily_report_edit_requests req
      where req.report_id=v_report_id
        and req.requested_by=v_user_id
        and req.status='approved'
      order by req.created_at desc
      limit 1
      for update;
      if v_edit_request_id is null then
        raise exception 'signed report requires approved edit request';
      end if;
      update public.daily_report_edit_requests
      set status='used',resolved_at=coalesce(resolved_at,now())
      where id=v_edit_request_id;
    end if;

    update public.daily_reports
    set site_id=p_site_id,
        route_assignment_id=p_route_assignment_id,
        report_date=p_report_date,
        work_description=p_work_description,
        status='draft',
        signer_name=null,
        signature_json=null,
        signed_at=null,
        representative_signature_json=null,
        representative_signer_name=null,
        supervisor_signature_json=null,
        supervisor_signer_name=null,
        updated_by=v_user_id,
        updated_at=now()
    where id=v_report_id;
  else
    select dr.id,dr.status
    into v_report_id,v_report_status
    from public.daily_reports dr
    where dr.company_id=v_company_id
      and dr.report_date=p_report_date
      and dr.site_id is not distinct from p_site_id
      and dr.route_assignment_id is not distinct from p_route_assignment_id
    limit 1
    for update;

    if v_report_id is distinct from captured_report then raise exception 'daily report target changed' using errcode='40001';end if;
    if v_report_id is not null then
      if v_report_status='signed' then
        raise exception 'signed report requires edit approval';
      end if;
      update public.daily_reports
      set work_description=p_work_description,
          updated_by=v_user_id,
          updated_at=now()
      where id=v_report_id;
    else
      insert into public.daily_reports(
        company_id,site_id,route_assignment_id,report_date,
        work_description,status,created_by,updated_by
      )
      values(
        v_company_id,p_site_id,p_route_assignment_id,p_report_date,
        p_work_description,'draft',v_user_id,v_user_id
      )
      returning id into v_report_id;
    end if;
  end if;

  delete from public.daily_report_workers where report_id=v_report_id;

  for v_worker in
    select value from jsonb_array_elements(coalesce(p_workers,'[]'::jsonb))
  loop
    v_worker_id:=(v_worker->>'worker_id')::uuid;

    if nullif(v_worker->>'work_category','') is not null
       and v_worker->>'work_category' not in ('day','night','holiday','holiday_night')
    then
      raise exception 'invalid work category';
    end if;

    if (
      select count(distinct trim(v))
      from unnest(string_to_array(coalesce(v_worker->>'allowance_label',''),E'\n')) v
      where trim(v)<>''
    ) > 3 then
      raise exception 'maximum three daily allowances';
    end if;

    if not exists(
      select 1 from public.workers w
      where w.id=v_worker_id and w.company_id=v_company_id
    ) then
      raise exception 'worker does not belong to company';
    end if;

    insert into public.daily_report_workers(
      report_id,worker_id,overtime_hours,early_hours,night_hours,
      allowance_amount,allowance_label,work_category
    )
    values(
      v_report_id,v_worker_id,
      greatest(coalesce((v_worker->>'overtime_hours')::numeric,0),0),
      greatest(coalesce((v_worker->>'early_hours')::numeric,0),0),
      greatest(coalesce((v_worker->>'night_hours')::numeric,0),0),
      greatest(coalesce((v_worker->>'allowance_amount')::integer,0),0),
      nullif(trim(coalesce(v_worker->>'allowance_label','')),''),
      nullif(v_worker->>'work_category','')
    );
  end loop;

  return v_report_id;
end;
$function$
;

-- Single-row settings adoption retains existing RLS and DML grants.

create function payroll_scope_private.settings_scopes(p_new jsonb,p_old jsonb) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('cid',cid,'wid',wid,'day',scope_day) order by cid,wid,scope_day),'[]') from (
  select (p_new->>'company_id')::uuid cid,(p_new->>'worker_id')::uuid wid,date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')::date as scope_day
  union select (p_old->>'company_id')::uuid,(p_old->>'worker_id')::uuid,date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')::date where p_old is not null
  union select (p_new->>'company_id')::uuid,(p_new->>'worker_id')::uuid,date_trunc('month',a.work_date)::date from public.attendance_entries a where a.company_id=(p_new->>'company_id')::uuid and a.worker_id=(p_new->>'worker_id')::uuid
  union select (p_new->>'company_id')::uuid,(p_new->>'worker_id')::uuid,p.period_start from public.payroll_statements p where p.company_id=(p_new->>'company_id')::uuid and p.worker_id=(p_new->>'worker_id')::uuid
  union select (p_new->>'company_id')::uuid,(p_new->>'worker_id')::uuid,date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')::date where (p_new->>'pay_type')='monthly' and coalesce((p_new->>'monthly_salary_yen')::numeric,0)>0 and exists(select 1 from public.workers w where w.id=(p_new->>'worker_id')::uuid and w.company_id=(p_new->>'company_id')::uuid and w.status::text='active' and w.affiliation::text='employee')
  union select (p_old->>'company_id')::uuid,(p_old->>'worker_id')::uuid,date_trunc('month',a.work_date)::date from public.attendance_entries a where p_old is not null and a.company_id=(p_old->>'company_id')::uuid and a.worker_id=(p_old->>'worker_id')::uuid
  union select (p_old->>'company_id')::uuid,(p_old->>'worker_id')::uuid,p.period_start from public.payroll_statements p where p_old is not null and p.company_id=(p_old->>'company_id')::uuid and p.worker_id=(p_old->>'worker_id')::uuid
 ) t;
$$;
revoke all on function payroll_scope_private.settings_scopes(jsonb,jsonb) from public,anon,authenticated;
create function payroll_scope_private.settings_before_scope() returns trigger
language plpgsql security definer set search_path='' as $$
declare scopes jsonb; existing_setting boolean:=true;
begin
 -- Preserve the existing raw RLS and delegated SECURITY DEFINER portal authorization.
 -- Align INSERT ON CONFLICT with UPDATE: an existing settings row is locked first.
 if tg_op='INSERT' then
  perform 1 from public.worker_payroll_settings where worker_id=new.worker_id for update;
  existing_setting:=found;
 end if;
 scopes:=payroll_scope_private.settings_scopes(to_jsonb(new),case when tg_op='UPDATE' then to_jsonb(old) else null end);
 perform payroll_scope_private.lock_scopes(scopes);
 if payroll_scope_private.settings_scopes(to_jsonb(new),case when tg_op='UPDATE' then to_jsonb(old) else null end) is distinct from scopes then raise exception 'payroll settings scope changed' using errcode='40001';end if;
 if tg_op='INSERT' and not existing_setting and exists(select 1 from public.worker_payroll_settings where worker_id=new.worker_id) then raise exception 'payroll settings target changed' using errcode='40001';end if;
 return new;
end$$;
revoke all on function payroll_scope_private.settings_before_scope() from public,anon,authenticated;
create trigger payroll_scope_before_settings before insert or update on public.worker_payroll_settings for each row execute function payroll_scope_private.settings_before_scope();
