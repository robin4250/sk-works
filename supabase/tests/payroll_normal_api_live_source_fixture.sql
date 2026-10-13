CREATE OR REPLACE FUNCTION private.cancel_daily_report(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c uuid;rid uuid:=(p_data->>'report_id')::uuid;wid uuid;wids uuid[];sid uuid;day date;
 v jsonb;r jsonb;e jsonb;rw jsonb;snap jsonb;fingerprint text;reason text:=trim(coalesce(p_data->>'reason',''));blocked text;customer uuid;outid uuid;wn text;sn text;
begin
 select company_id into c from public.company_members where user_id=auth.uid() and role::text in ('owner','admin') limit 1;
 if c is null then raise exception '管理者だけが出勤を取り消せます。';end if;
 select site_id,report_date into sid,day from public.daily_reports where id=rid and company_id=c for update;
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
CREATE OR REPLACE FUNCTION public.cancel_daily_report(p_data jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.cancel_daily_report(p_data);$function$
;
CREATE OR REPLACE FUNCTION public.decide_attendance_correction_request(p_request_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
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
begin
  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision';
  end if;

  select r.company_id, r.requested_by, r.worker_id
  into v_company_id, v_requested_by, v_worker_id
  from public.paid_leave_requests r
  where r.batch_id = p_batch_id
    and r.status = 'pending'
  limit 1
  for update;

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
    limit 1
    for update;

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
CREATE OR REPLACE FUNCTION private.professional_portal(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); cid uuid; inv private.professional_invites%rowtype; tok text; result jsonb; wid uuid; start_date date; data jsonb;
begin
 if uid is null then raise exception 'ログインが必要です'; end if;
 if p_action in ('create','list','review','update_access') then
  select company_id into cid from public.company_members where user_id=uid and role::text in ('owner','admin') limit 1;
  if cid is null then raise exception '管理者のみ操作できます'; end if;
  if p_action='create' then
   tok:=encode(extensions.gen_random_bytes(32),'hex');
   insert into private.professional_invites(company_id,name,phone,profession,payroll_access,invoice_access,attendance_view,token_hash,created_by)
   values(cid,trim(p_data->>'name'),trim(p_data->>'phone'),p_data->>'profession',p_data->>'payroll_access',p_data->>'invoice_access',coalesce((p_data->>'can_view_attendance')::boolean,false),extensions.digest(tok,'sha256'),uid) returning * into inv;
   result:=jsonb_build_object('id',inv.id,'expires_at',inv.expires_at,'qr',jsonb_build_object('type','sko_professional_invite','version',1,'token',tok)::text);
  elsif p_action='list' then
   return coalesce((select jsonb_agg(to_jsonb(i)-'token_hash' order by i.created_at desc) from private.professional_invites i where company_id=cid),'[]'::jsonb);
  elsif p_action='update_access' then
   if p_data->>'payroll_access' is null or p_data->>'payroll_access' not in ('none','view','edit')
      or p_data->>'invoice_access' is null or p_data->>'invoice_access' not in ('none','view','edit')
      or jsonb_typeof(p_data->'can_view_attendance') is distinct from 'boolean' then raise exception '利用権限を確認してください'; end if;
   select * into inv from private.professional_invites where id=(p_data->>'id')::uuid and company_id=cid for update;
   if not found or inv.status='revoked' then raise exception '対象の登録状態を確認してください'; end if;
   update private.professional_invites set payroll_access=p_data->>'payroll_access',invoice_access=p_data->>'invoice_access',attendance_view=(p_data->>'can_view_attendance')::boolean where id=inv.id;
   result:='{}'::jsonb;
  else
   select * into inv from private.professional_invites where id=(p_data->>'id')::uuid and company_id=cid for update;
   if not found then raise exception '対象が見つかりません'; end if;
   if p_data->>'decision'='approve' then
    if inv.status<>'pending' or inv.claimed_by is null or not exists(select 1 from public.user_secondary_credentials where user_id=inv.claimed_by) then raise exception '本人の登録と重要情報用パスワード設定を確認してください'; end if;
    update private.professional_invites set status='approved',approved_by=uid,approved_at=now() where id=inv.id;
   elsif p_data->>'decision'='restore' then
    if inv.status<>'revoked' or inv.claimed_by is null or not exists(select 1 from public.user_secondary_credentials where user_id=inv.claimed_by) then raise exception '登録済みの本人と重要情報用パスワードを確認してください'; end if;
    update private.professional_invites set status='pending',approved_by=null,approved_at=null where id=inv.id;
   elsif p_data->>'decision'='revoke' then
    update private.professional_invites set status='revoked' where id=inv.id;
   else raise exception '操作を確認してください'; end if;
   result:='{}'::jsonb;
  end if;
  insert into private.professional_access_audit(invite_id,actor_id,action) values(inv.id,uid,p_action||coalesce(':'||(p_data->>'decision'),''));
  return result;
 end if;
 if p_action='accept' then
  tok:=p_data->>'token';
  if tok is null or tok !~ '^[a-f0-9]{64}$' then raise exception '招待コードを確認してください'; end if;
  if not exists(select 1 from auth.identities where user_id=uid and provider in ('google','apple')) then raise exception 'GoogleまたはAppleでログインしてください'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
  select * into inv from private.professional_invites where token_hash=extensions.digest(tok,'sha256') for update;
  if not found then raise exception 'この招待は利用できません'; end if;
  if inv.claimed_by=uid and inv.status in ('pending','approved') then return jsonb_build_object('status',inv.status); end if;
  if inv.status<>'invited' or inv.expires_at<=now() or inv.claimed_by is not null then raise exception '招待は期限切れ、取消済み、または使用済みです'; end if;
  if exists(select 1 from public.company_members where user_id=uid) or exists(select 1 from public.employee_registration_invites where auth_user_id=uid) or exists(select 1 from private.professional_invites where claimed_by=uid) then raise exception 'すでに登録手続きがあります'; end if;
  if not exists(select 1 from public.user_secondary_credentials where user_id=uid) then raise exception '重要情報用パスワードを設定してください'; end if;
  update private.professional_invites set name=trim(p_data->>'name'),phone=trim(p_data->>'phone'),claimed_by=uid,status='pending' where id=inv.id;
  insert into private.professional_access_audit(invite_id,actor_id,action) values(inv.id,uid,'accept');
  return jsonb_build_object('status','pending');
 end if;
 select * into inv from private.professional_invites where claimed_by=uid;
 if p_action='self' then
  if not found then return 'null'::jsonb; end if;
  return jsonb_build_object('status',inv.status,'name',inv.name,'company_name',(select name from public.companies where id=inv.company_id),'payroll_access',inv.payroll_access,'invoice_access',inv.invoice_access,'attendance_view',inv.attendance_view);
 end if;
 if inv.id is null or inv.status<>'approved' then raise exception '管理者の承認が必要です'; end if;
 cid:=inv.company_id;
 if p_action='payroll' then
  if inv.payroll_access='none' then raise exception '給与の閲覧権限がありません'; end if;
  return jsonb_build_object('permissions',jsonb_build_object('view',true,'edit',inv.payroll_access='edit'),'workers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.workers where company_id=cid and status='active'),'[]'::jsonb),'settings',coalesce((select jsonb_agg(to_jsonb(s)) from public.worker_payroll_settings s where company_id=cid),'[]'::jsonb),'statements',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('worker_name',w.name) order by p.period_end desc) from public.payroll_statements p join public.workers w on w.id=p.worker_id and w.company_id=cid where p.company_id=cid),'[]'::jsonb),'company_name',(select name from public.companies where id=cid));
 elsif p_action='save_payroll' then
  if inv.payroll_access<>'edit' then raise exception '給与の編集権限がありません'; end if;
  wid:=(p_data->>'worker_id')::uuid; data:=p_data->'values';
  if not exists(select 1 from public.workers where id=wid and company_id=cid) then raise exception '対象者を確認してください'; end if;
  insert into public.worker_payroll_settings(worker_id,company_id,day_daily,day_overtime,day_early,night_daily,night_overtime,night_early,holiday_daily,holiday_overtime,holiday_early,holiday_night_daily,holiday_night_overtime,holiday_night_early,allowance_1,allowance_2,allowance_3,family_monthly,transport_monthly,income_tax_monthly,resident_tax_monthly,social_insurance_monthly,other_deduction_monthly,allowance_name_1,allowance_name_2,allowance_name_3,updated_at) values(wid,cid,coalesce((data->>'day_daily')::numeric,0),coalesce((data->>'day_overtime')::numeric,0),coalesce((data->>'day_early')::numeric,0),coalesce((data->>'night_daily')::numeric,0),coalesce((data->>'night_overtime')::numeric,0),coalesce((data->>'night_early')::numeric,0),coalesce((data->>'holiday_daily')::numeric,0),coalesce((data->>'holiday_overtime')::numeric,0),coalesce((data->>'holiday_early')::numeric,0),coalesce((data->>'holiday_night_daily')::numeric,0),coalesce((data->>'holiday_night_overtime')::numeric,0),coalesce((data->>'holiday_night_early')::numeric,0),coalesce((data->>'allowance_1')::numeric,0),coalesce((data->>'allowance_2')::numeric,0),coalesce((data->>'allowance_3')::numeric,0),coalesce((data->>'family_monthly')::numeric,0),coalesce((data->>'transport_monthly')::numeric,0),coalesce((data->>'income_tax_monthly')::numeric,0),coalesce((data->>'resident_tax_monthly')::numeric,0),coalesce((data->>'social_insurance_monthly')::numeric,0),coalesce((data->>'other_deduction_monthly')::numeric,0),coalesce(data->>'allowance_name_1',''),coalesce(data->>'allowance_name_2',''),coalesce(data->>'allowance_name_3',''),now()) on conflict(worker_id) do update set day_daily=excluded.day_daily,day_overtime=excluded.day_overtime,day_early=excluded.day_early,night_daily=excluded.night_daily,night_overtime=excluded.night_overtime,night_early=excluded.night_early,holiday_daily=excluded.holiday_daily,holiday_overtime=excluded.holiday_overtime,holiday_early=excluded.holiday_early,holiday_night_daily=excluded.holiday_night_daily,holiday_night_overtime=excluded.holiday_night_overtime,holiday_night_early=excluded.holiday_night_early,allowance_1=excluded.allowance_1,allowance_2=excluded.allowance_2,allowance_3=excluded.allowance_3,family_monthly=excluded.family_monthly,transport_monthly=excluded.transport_monthly,income_tax_monthly=excluded.income_tax_monthly,resident_tax_monthly=excluded.resident_tax_monthly,social_insurance_monthly=excluded.social_insurance_monthly,other_deduction_monthly=excluded.other_deduction_monthly,allowance_name_1=excluded.allowance_name_1,allowance_name_2=excluded.allowance_name_2,allowance_name_3=excluded.allowance_name_3,updated_at=now();
 elsif p_action='invoice' then
  if inv.invoice_access='none' then raise exception '請求書の閲覧権限がありません'; end if;
  return (select jsonb_build_object('company_name',name,'tax_rate',tax_rate,'welfare_rate',default_welfare_rate,'template_title',invoice_template_title,'footer_note',invoice_footer_note,'can_edit',inv.invoice_access='edit','invoices',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'invoice_number',i.invoice_number,'billing_period_start',i.billing_period_start,'billing_period_end',i.billing_period_end,'grand_total',i.grand_total,'status',i.status,'calculation_blocked',coalesce((to_jsonb(i)->>'calculation_blocked')::boolean,false)) order by i.billing_period_end desc) from public.invoices i where i.company_id=cid),'[]'::jsonb)) from public.companies where id=cid);
 elsif p_action='invoice_detail' then
  if inv.invoice_access='none' then raise exception '請求書の閲覧権限がありません'; end if;
  select jsonb_build_object('id',i.id,'status',i.status,'subtotal',i.subtotal,'tax',i.tax,'grand_total',i.grand_total,
   'calculation_blocked',i.calculation_blocked,'snapshot',
   case when i.automatic_calculation then jsonb_build_object(
    'customer_name',i.snapshot->'customer_name','billing_period',i.snapshot->'billing_period',
    'tax_rate_bps',i.snapshot->'tax_rate_bps','sites',i.snapshot->'sites')
   else jsonb_build_object('customer_name',c.name,'billing_period',to_char(i.billing_period_start,'YYYY年FMMM月'),
    'tax_rate_bps',coalesce((i.snapshot->>'tax_rate_bps')::numeric,case when i.subtotal=0 then 0 else round(i.tax*10000/i.subtotal) end),
    'sites',coalesce((select jsonb_agg(jsonb_build_object('site_id',coalesce(sc.site_id::text,''),'site_name',s.name,
     'manual_adjustment',sc.manual_adjustment_amount,'welfare_rate_bps',round(sc.welfare_rate_snapshot*100),
     'lines',coalesce((select jsonb_agg(jsonb_build_object('label',l.description,'quantity',l.quantity,'unit_price',l.unit_price) order by l.sort_order)
      from public.invoice_detail_lines l where l.company_id=cid and l.invoice_site_calculation_id=sc.id),'[]'::jsonb)) order by sc.created_at)
     from public.invoice_site_calculations sc left join public.sites s on s.id=sc.site_id and s.company_id=cid
     where sc.company_id=cid and sc.invoice_id=i.id),'[]'::jsonb)) end)
   into result from public.invoices i left join public.customers c on c.id=i.customer_id and c.company_id=cid
   where i.id=(p_data->>'invoice_id')::uuid and i.company_id=cid;
  if result is null then raise exception '請求書が見つからないか、閲覧権限がありません'; end if;
  insert into private.professional_access_audit(invite_id,actor_id,action) values(inv.id,uid,'invoice_detail');
  return result;
 elsif p_action='save_invoice' then
  if inv.invoice_access<>'edit' then raise exception '請求書設定の編集権限がありません'; end if;
  if (p_data->>'tax_rate')::numeric not between 0 and 100 or (p_data->>'welfare_rate')::numeric not between 0 and 100 or p_data->>'tax_rate' is null or p_data->>'welfare_rate' is null or length(p_data->>'template_title')>200 or length(p_data->>'footer_note')>10000 then raise exception '税率・文字数を確認してください'; end if;
  -- Explicit whitelist: never modifies bank details, membership or site billing rates.
  update public.companies set tax_rate=(p_data->>'tax_rate')::numeric,default_welfare_rate=(p_data->>'welfare_rate')::numeric,invoice_template_title=coalesce(nullif(trim(p_data->>'template_title'),''),'請求書'),invoice_footer_note=p_data->>'footer_note' where id=cid;
 elsif p_action='attendance' then
  if not inv.attendance_view then raise exception '出勤表の閲覧権限がありません'; end if;
  start_date:=date_trunc('month',(p_data->>'month')::date)::date;
  if start_date is null then raise exception '年月を指定してください'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('worker_id',e.worker_id,'work_date',e.work_date,'work_category',e.work_category,'regular_hours',e.regular_hours,'night_hours',e.night_hours,'early_hours',e.early_hours,'allowance_names',coalesce((select jsonb_agg(distinct trim(label)) from public.daily_reports dr join public.daily_report_workers dw on dw.report_id=dr.id cross join lateral regexp_split_to_table(coalesce(dw.allowance_label,''),E'\\n') label where dr.company_id=cid and dr.status='signed' and dr.site_id=e.site_id and dr.report_date=e.work_date and dw.worker_id=e.worker_id and trim(label)<>''),'[]'::jsonb),'overtime_hours',e.overtime_hours,'workers',jsonb_build_object('name',w.name),'sites',jsonb_build_object('name',s.name)) order by e.work_date,w.name) from public.attendance_entries e join public.workers w on w.id=e.worker_id and w.company_id=cid left join public.sites s on s.id=e.site_id and s.company_id=cid where e.company_id=cid and e.work_date>=start_date and e.work_date<start_date+interval '1 month'),'[]'::jsonb);
 else raise exception '操作を確認してください'; end if;
 insert into private.professional_access_audit(invite_id,actor_id,action) values(inv.id,uid,p_action);
 return '{}'::jsonb;
end $function$
;
revoke all on function private.professional_portal(text,jsonb) from public,anon;
grant execute on function private.professional_portal(text,jsonb) to authenticated;
