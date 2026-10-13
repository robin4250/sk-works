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

      update public.attendance_verifications
      set daily_report_id = null
      where daily_report_id = v_report.id
        and worker_id = v_worker_id;

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
      and confirmed_at >= (v_date::timestamp at time zone 'Asia/Tokyo')
      and confirmed_at < ((v_date + 1)::timestamp at time zone 'Asia/Tokyo');

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


revoke execute on function public.force_manage_attendance(text,jsonb) from public, anon;
grant execute on function public.force_manage_attendance(text,jsonb) to authenticated;
