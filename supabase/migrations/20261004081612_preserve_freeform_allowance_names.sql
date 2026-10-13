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
  v_source_report_id uuid;
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
      insert into public.attendance_entries(
        company_id,work_date,worker_id,site_id,
        base_man_days,overtime_hours,early_hours,night_hours,
        allowance_amount,allowance_names,notes,created_by,updated_by
      ) values (
        v_request.company_id,
        replace(v_item.proposed_snapshot->>'date','/','-')::date,
        v_worker_id,v_site_id,
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
    else
      select ae.source_report_id,ae.worker_id
      into v_source_report_id,v_worker_id
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
$$;
