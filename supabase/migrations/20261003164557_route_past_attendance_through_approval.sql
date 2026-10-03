alter table public.attendance_correction_requests
  add column if not exists request_kind text not null default 'correction'
    check (request_kind in ('correction','past_attendance'));

alter table public.attendance_correction_items
  alter column attendance_entry_id drop not null;

create or replace function public.submit_past_attendance_request(
  p_items jsonb,
  p_signer_name text,
  p_signature_json jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_request_id uuid;
  v_item jsonb;
  v_worker_id uuid;
  v_site_id uuid;
  v_work_date date;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_assignee_count integer;
  v_assignee record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) < 1 then
    raise exception 'at least one attendance item is required';
  end if;
  if jsonb_array_length(p_items) > 100 then
    raise exception 'too many attendance items';
  end if;
  if trim(coalesce(p_signer_name,'')) = '' or p_signature_json is null then
    raise exception 'signature is required';
  end if;

  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_actor limit 1;

  if v_company_id is null
     or not public.can_manage_attendance_corrections(v_company_id) then
    raise exception 'attendance management permission required';
  end if;

  select count(*) into v_assignee_count
  from public.company_approval_assignees
  where company_id=v_company_id;
  if v_assignee_count < 1 or v_assignee_count > 3 then
    raise exception 'company approval assignee configuration is invalid';
  end if;

  insert into public.attendance_correction_requests(
    company_id, requested_by, status, request_kind,
    signer_name, signature_json, signed_at, submitted_at
  ) values (
    v_company_id, v_actor, 'submitted', 'past_attendance',
    trim(p_signer_name), p_signature_json, now(), now()
  ) returning id into v_request_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_work_date := replace(coalesce(v_item->>'date',''),'/','-')::date;
    if v_work_date >= v_today then
      raise exception 'past attendance date must be before today';
    end if;

    select w.id into v_worker_id
    from public.workers w
    where w.company_id=v_company_id
      and w.name=trim(coalesce(v_item->>'workerName',''))
      and w.status='active'
    limit 2;
    if v_worker_id is null then raise exception 'worker not found'; end if;
    if (
      select count(*) from public.workers w
      where w.company_id=v_company_id
        and w.name=trim(coalesce(v_item->>'workerName',''))
        and w.status='active'
    ) > 1 then
      raise exception 'duplicate worker name';
    end if;

    select s.id into v_site_id
    from public.sites s
    where s.company_id=v_company_id
      and s.name=trim(coalesce(v_item->>'siteName',''))
    limit 2;
    if v_site_id is null then raise exception 'site not found'; end if;
    if (
      select count(*) from public.sites s
      where s.company_id=v_company_id
        and s.name=trim(coalesce(v_item->>'siteName',''))
    ) > 1 then
      raise exception 'duplicate site name';
    end if;

    insert into public.attendance_correction_items(
      request_id, company_id, attendance_entry_id,
      original_snapshot, proposed_snapshot, change_summary
    ) values (
      v_request_id, v_company_id, null,
      jsonb_build_object(
        'date',v_item->>'date',
        'workerName',v_item->>'workerName'
      ),
      v_item || jsonb_build_object(
        'workerId',v_worker_id,
        'siteId',v_site_id
      ),
      '過去出勤を新規登録'
    );
  end loop;

  for v_assignee in
    select caa.user_id from public.company_approval_assignees caa
    where caa.company_id=v_company_id
  loop
    perform private.enqueue_notification(
      v_company_id,v_assignee.user_id,'approval',
      '過去のまとめて出勤申請',
      '過去の出勤をまとめて登録する申請があります。',
      'attendance_correction_request',v_request_id
    );
  end loop;

  return v_request_id;
exception
  when others then
    if v_request_id is not null then
      delete from public.attendance_correction_requests where id=v_request_id;
    end if;
    raise;
end;
$$;

drop function if exists public.pending_attendance_correction_rows();

create function public.pending_attendance_correction_rows()
returns table(
  request_id uuid,
  requested_by uuid,
  requested_by_name text,
  item_count bigint,
  signer_name text,
  submitted_at timestamptz,
  request_kind text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
begin
  select caa.company_id into v_company_id
  from public.company_approval_assignees caa
  where caa.user_id=v_actor limit 1;

  if v_company_id is null then
    raise exception 'approval assignee permission required';
  end if;

  return query
  select r.id,r.requested_by,coalesce(up.display_name,'SKOユーザー'),
         count(i.id),r.signer_name,r.submitted_at,r.request_kind
  from public.attendance_correction_requests r
  left join public.attendance_correction_items i on i.request_id=r.id
  left join public.user_profiles up on up.user_id=r.requested_by
  where r.company_id=v_company_id and r.status='submitted'
  group by r.id,r.requested_by,up.display_name,
           r.signer_name,r.submitted_at,r.request_kind
  order by r.submitted_at;
end;
$$;

create or replace function public.decide_attendance_correction_request(
  p_request_id uuid,
  p_decision text,
  p_note text default null
)
returns text
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_request public.attendance_correction_requests%rowtype;
  v_assignee_count integer;
  v_item record;
  v_site_id uuid;
  v_worker_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision';
  end if;

  select * into v_request
  from public.attendance_correction_requests
  where id=p_request_id for update;

  if not found or v_request.status <> 'submitted' then
    raise exception 'submitted attendance request not found';
  end if;

  if not exists (
    select 1 from public.company_approval_assignees caa
    where caa.company_id=v_request.company_id
      and caa.user_id=v_actor
  ) then
    raise exception 'approval assignee permission required';
  end if;

  select count(*) into v_assignee_count
  from public.company_approval_assignees
  where company_id=v_request.company_id;

  if v_request.requested_by=v_actor and v_assignee_count > 1 then
    raise exception 'requester cannot approve own request';
  end if;

  if p_decision='reject' then
    update public.attendance_correction_requests
    set status='rejected',reviewed_by=v_actor,reviewed_at=now(),
        review_note=nullif(trim(coalesce(p_note,'')),''),
        updated_at=now()
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
    where request_id=p_request_id
      and company_id=v_request.company_id
    order by created_at
  loop
    if v_request.request_kind='past_attendance'
       or v_item.attendance_entry_id is null then
      v_worker_id := (v_item.proposed_snapshot->>'workerId')::uuid;
      v_site_id := (v_item.proposed_snapshot->>'siteId')::uuid;

      if not exists (
        select 1 from public.workers w
        where w.id=v_worker_id and w.company_id=v_request.company_id
      ) then raise exception 'worker not found for past attendance'; end if;
      if not exists (
        select 1 from public.sites s
        where s.id=v_site_id and s.company_id=v_request.company_id
      ) then raise exception 'site not found for past attendance'; end if;

      insert into public.attendance_entries(
        company_id,work_date,worker_id,site_id,
        base_man_days,overtime_hours,early_hours,night_hours,
        allowance_amount,notes,created_by,updated_by
      ) values (
        v_request.company_id,
        replace(v_item.proposed_snapshot->>'date','/','-')::date,
        v_worker_id,v_site_id,
        coalesce((v_item.proposed_snapshot->>'manDays')::numeric,1),
        coalesce((v_item.proposed_snapshot->>'overtimeHours')::numeric,0),
        coalesce((v_item.proposed_snapshot->>'earlyHours')::numeric,0),
        coalesce((v_item.proposed_snapshot->>'nightHours')::numeric,0),
        coalesce((v_item.proposed_snapshot->>'allowanceYen')::integer,0),
        nullif(trim(coalesce(v_item.proposed_snapshot->>'notes','')),''),
        v_request.requested_by,v_actor
      );
    else
      select s.id into v_site_id
      from public.sites s
      where s.company_id=v_request.company_id
        and s.name=trim(coalesce(v_item.proposed_snapshot->>'siteName',''))
      limit 2;
      if v_site_id is null then
        raise exception 'site not found for correction item';
      end if;

      update public.attendance_entries
      set site_id=v_site_id,
          base_man_days=coalesce((v_item.proposed_snapshot->>'manDays')::numeric,base_man_days),
          overtime_hours=coalesce((v_item.proposed_snapshot->>'overtimeHours')::numeric,overtime_hours),
          early_hours=coalesce((v_item.proposed_snapshot->>'earlyHours')::numeric,early_hours),
          night_hours=coalesce((v_item.proposed_snapshot->>'nightHours')::numeric,night_hours),
          allowance_amount=coalesce((v_item.proposed_snapshot->>'allowanceYen')::integer,allowance_amount),
          notes=nullif(trim(coalesce(v_item.proposed_snapshot->>'notes','')),''),
          updated_by=v_actor,updated_at=now()
      where id=v_item.attendance_entry_id
        and company_id=v_request.company_id;
    end if;
  end loop;

  update public.attendance_correction_requests
  set status='approved',reviewed_by=v_actor,reviewed_at=now(),
      review_note=nullif(trim(coalesce(p_note,'')),''),
      updated_at=now()
  where id=p_request_id;

  perform private.enqueue_notification(
    v_request.company_id,v_request.requested_by,'approval',
    case when v_request.request_kind='past_attendance'
      then '過去のまとめて出勤が反映されました'
      else '過去勤怠の修正が反映されました' end,
    case when v_request.request_kind='past_attendance'
      then '過去のまとめて出勤申請が承認され、出勤表へ反映されました。'
      else 'まとめて修正申請が承認され、勤怠へ反映されました。' end,
    'attendance_correction_request',p_request_id
  );
  return 'approved';
end;
$$;

revoke execute on function public.pending_attendance_correction_rows()
  from public, anon;
grant execute on function public.pending_attendance_correction_rows()
  to authenticated;
revoke execute on function public.submit_past_attendance_request(jsonb,text,jsonb)
  from public, anon;
grant execute on function public.submit_past_attendance_request(jsonb,text,jsonb)
  to authenticated;
