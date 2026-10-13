-- New evidence only: preserve existing rows, financial records and all RPC ACLs.
alter table public.attendance_verifications add column work_date date;
alter table public.attendance_verifications add column source_clock_in_id uuid
  references public.attendance_verifications(id) on delete no action;
create unique index attendance_verifications_one_out_per_start
  on public.attendance_verifications(source_clock_in_id)
  where source_clock_in_id is not null;

create or replace function private.validate_attendance_shift_evidence()
returns trigger language plpgsql security invoker set search_path='' as $$
declare
  v_start public.attendance_verifications%rowtype;
  v_report public.daily_reports%rowtype;
  v_date date;
begin
  -- Evidence chronology/ownership cannot be rewritten. Management corrects by
  -- replacing complete shifts, and photograph/report linking stays available.
  if TG_OP='UPDATE' then
    if row(NEW.id,NEW.company_id,NEW.worker_id,NEW.site_id,NEW.route_assignment_id,
           NEW.event_type,NEW.confirmed_at,NEW.source_clock_in_id,NEW.work_date)
       is distinct from
       row(OLD.id,OLD.company_id,OLD.worker_id,OLD.site_id,OLD.route_assignment_id,
           OLD.event_type,OLD.confirmed_at,OLD.source_clock_in_id,OLD.work_date) then
      raise exception 'attendance evidence chronology is immutable';
    end if;
    -- Preserve existing vehicle FK ON DELETE SET NULL while preventing edits.
    if NEW.vehicle_id is distinct from OLD.vehicle_id and not (
      NEW.vehicle_id is null and OLD.vehicle_id is not null and not exists (
        select 1 from public.vehicles v where v.id=OLD.vehicle_id
      )
    ) then raise exception 'attendance evidence vehicle is immutable'; end if;
    v_date := coalesce(NEW.work_date,(NEW.confirmed_at at time zone 'Asia/Tokyo')::date);
  else
    v_date := (NEW.confirmed_at at time zone 'Asia/Tokyo')::date;
  end if;

  if NEW.vehicle_id is not null and not exists (
    select 1 from public.vehicles v where v.id=NEW.vehicle_id and v.company_id=NEW.company_id
  ) then raise exception 'attendance vehicle does not belong to company'; end if;

  if NEW.source_clock_in_id is not null then
    if NEW.event_type <> 'clock_out' or NEW.source_clock_in_id=NEW.id then
      raise exception 'only clock out can reference its clock in';
    end if;
    -- SECURITY INVOKER: source visibility is governed by the existing RLS.
    select * into v_start from public.attendance_verifications
      where id=NEW.source_clock_in_id;
    if not found or v_start.event_type <> 'clock_in'
       or row(v_start.company_id,v_start.worker_id,v_start.site_id,v_start.route_assignment_id,v_start.vehicle_id)
          is distinct from row(NEW.company_id,NEW.worker_id,NEW.site_id,NEW.route_assignment_id,NEW.vehicle_id)
       or NEW.confirmed_at < v_start.confirmed_at then
      raise exception 'clock out source is unavailable or inconsistent';
    end if;
    v_date := coalesce(v_start.work_date,(v_start.confirmed_at at time zone 'Asia/Tokyo')::date);
    if v_start.work_date is null and v_start.daily_report_id is not null then
      select * into v_report from public.daily_reports where id=v_start.daily_report_id;
      if not found or row(v_report.company_id,v_report.site_id,v_report.route_assignment_id)
         is distinct from row(NEW.company_id,NEW.site_id,NEW.route_assignment_id) then
        raise exception 'clock in report is inconsistent';
      end if;
      v_date := v_report.report_date;
    end if;
    if TG_OP='INSERT' and exists (
      select 1 from public.attendance_verifications a
      where a.company_id=NEW.company_id and a.worker_id=NEW.worker_id
        and a.site_id is not distinct from NEW.site_id
        and a.route_assignment_id is not distinct from NEW.route_assignment_id
        and a.confirmed_at >= v_start.confirmed_at
        and a.confirmed_at <= NEW.confirmed_at
        and a.event_type='clock_out' and a.source_clock_in_id is null
    ) then
      raise exception 'clock in is already closed or its evidence is ambiguous';
    end if;
  end if;

  if NEW.daily_report_id is not null then
    select * into v_report from public.daily_reports where id=NEW.daily_report_id;
    if not found or row(v_report.company_id,v_report.site_id,v_report.route_assignment_id)
       is distinct from row(NEW.company_id,NEW.site_id,NEW.route_assignment_id)
       or (NEW.source_clock_in_id is not null and v_report.report_date <> v_date)
       or (NEW.work_date is not null and TG_OP='UPDATE' and v_report.report_date <> NEW.work_date) then
      raise exception 'attendance report date or destination is inconsistent';
    end if;
    -- Existing management RPC associates a next-morning end with the report day.
    if NEW.source_clock_in_id is null then v_date := v_report.report_date; end if;
  end if;
  if TG_OP='UPDATE' and NEW.event_type='clock_in' and exists (
    select 1 from public.attendance_verifications child
    where child.source_clock_in_id=NEW.id and child.work_date is distinct from v_date
  ) then
    raise exception 'clock in report cannot change its closed shift date';
  end if;
  if TG_OP='INSERT' then NEW.work_date := v_date; end if;
  return NEW;
end $$;
revoke all on function private.validate_attendance_shift_evidence() from public, anon;
create trigger attendance_shift_evidence_guard before insert or update
  on public.attendance_verifications for each row
  execute function private.validate_attendance_shift_evidence();

-- Retain ownership/feature gates and restrictive account guard. Only one
-- destination is accepted, and both site and route must belong to this company.
alter policy "worker or attendance manager can create verification"
on public.attendance_verifications with check (
  exists (select 1 from public.workers company_worker
    where company_worker.id=attendance_verifications.worker_id
      and company_worker.company_id=attendance_verifications.company_id)
  and (exists (select 1 from public.workers w
     where w.id=attendance_verifications.worker_id
       and w.company_id=attendance_verifications.company_id
       and w.user_id=(select auth.uid()))
   or private.has_company_feature(company_id,'can_manage_attendance'))
  and (
    (route_assignment_id is null and site_id is not null and exists (
      select 1 from public.sites s where s.id=attendance_verifications.site_id
        and s.company_id=attendance_verifications.company_id))
    or (site_id is null and route_assignment_id is not null and exists (
      select 1 from public.route_assignments r where r.id=attendance_verifications.route_assignment_id
        and r.company_id=attendance_verifications.company_id))
  )
);

CREATE OR REPLACE FUNCTION private.attempt_gps_auto_attendance(p_latitude double precision, p_longitude double precision, p_accuracy_m double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_worker uuid;
  v_schedule public.gps_auto_attendance_schedules%rowtype;
  v_site public.sites%rowtype;
  v_local timestamp;
  v_scheduled timestamp;
  v_distance double precision;
  v_existing text;
  v_today_selection text;
  v_id uuid;
  v_target_lat double precision;
  v_target_lon double precision;
  v_target_label text;
  v_stop_id uuid;
  v_vehicle_id uuid;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;

  select cm.company_id,w.id
  into v_company,v_worker
  from public.company_members cm
  join public.workers w
    on w.company_id=cm.company_id and w.user_id=cm.user_id
  where cm.user_id=v_user
  limit 1;

  select * into v_schedule
  from public.gps_auto_attendance_schedules g
  where g.company_id=v_company
    and g.worker_id=v_worker
    and g.enabled=true
  for update;

  if not found then
    return jsonb_build_object('status','disabled');
  end if;

  v_local:=now() at time zone v_schedule.timezone;

  if extract(isodow from v_local)::smallint <> all(v_schedule.weekdays) then
    return jsonb_build_object('status','not_scheduled_day');
  end if;

  select a.verification_mode into v_today_selection
  from public.work_attendance_selections a
  where a.company_id=v_company
    and a.worker_id=v_worker
    and a.work_date=v_local::date;

  if v_today_selection is not null and v_today_selection<>'gps_auto' then
    return jsonb_build_object('status','overridden_for_day');
  end if;

  if v_schedule.last_attempt_date=v_local::date then
    return jsonb_build_object(
      'status','already_attempted',
      'result',v_schedule.last_result
    );
  end if;

  v_scheduled:=v_local::date + v_schedule.local_time;
  if abs(extract(epoch from (v_local-v_scheduled)))>300 then
    return jsonb_build_object('status','outside_time_window');
  end if;

  if v_schedule.site_id is not null then
    select * into v_site
    from public.sites s
    where s.id=v_schedule.site_id
      and s.company_id=v_company;

    if v_site.latitude is null or v_site.longitude is null then
      update public.gps_auto_attendance_schedules
      set last_attempt_date=v_local::date,
          last_result='site_location_missing',
          updated_at=now()
      where company_id=v_company and worker_id=v_worker;
      return jsonb_build_object('status','site_location_missing');
    end if;

    v_target_lat:=v_site.latitude;
    v_target_lon:=v_site.longitude;
    v_target_label:=v_site.name;
  else
    select rs.id,rs.latitude,rs.longitude,
           coalesce(nullif(rs.source_label,''),nullif(rs.address,''),'ルート地点')
    into v_stop_id,v_target_lat,v_target_lon,v_target_label
    from public.route_stops rs
    join public.route_assignments r on r.id=rs.route_assignment_id
    where rs.route_assignment_id=v_schedule.route_assignment_id
      and r.company_id=v_company
      and rs.latitude is not null
      and rs.longitude is not null
    order by (
      6371000 * acos(
        least(1.0,greatest(-1.0,
          sin(radians(p_latitude))*sin(radians(rs.latitude)) +
          cos(radians(p_latitude))*cos(radians(rs.latitude)) *
          cos(radians(p_longitude-rs.longitude))
        ))
      )
    ) asc
    limit 1;

    if v_target_lat is null or v_target_lon is null then
      update public.gps_auto_attendance_schedules
      set last_attempt_date=v_local::date,
          last_result='route_location_missing',
          updated_at=now()
      where company_id=v_company and worker_id=v_worker;
      return jsonb_build_object('status','route_location_missing');
    end if;
  end if;

  select av.event_type into v_existing
  from public.attendance_verifications av
  where av.worker_id=v_worker
    and coalesce(av.work_date,(av.confirmed_at at time zone v_schedule.timezone)::date)=v_local::date
  order by av.confirmed_at desc
  limit 1;

  if v_existing in ('clock_in','clock_out') then
    update public.gps_auto_attendance_schedules
    set last_attempt_date=v_local::date,
        last_result='already_recorded',
        updated_at=now()
    where company_id=v_company and worker_id=v_worker;
    return jsonb_build_object('status','already_recorded');
  end if;

  v_distance:=6371000 * acos(
    least(1.0,greatest(-1.0,
      sin(radians(p_latitude))*sin(radians(v_target_lat)) +
      cos(radians(p_latitude))*cos(radians(v_target_lat)) *
      cos(radians(p_longitude-v_target_lon))
    ))
  );

  if v_distance>v_schedule.radius_m then
    update public.gps_auto_attendance_schedules
    set last_attempt_date=v_local::date,
        last_result='outside_site',
        updated_at=now()
    where company_id=v_company and worker_id=v_worker;

    return jsonb_build_object(
      'status','outside_site',
      'distance_m',v_distance,
      'target_label',v_target_label
    );
  end if;

  insert into public.work_attendance_selections(
    company_id,worker_id,work_date,verification_mode,
    site_id,route_assignment_id,updated_by,updated_at
  )
  values(
    v_company,v_worker,v_local::date,'gps_auto',
    v_schedule.site_id,v_schedule.route_assignment_id,v_user,now()
  )
  on conflict(company_id,worker_id,work_date)
  do update set
    verification_mode='gps_auto',
    site_id=excluded.site_id,
    route_assignment_id=excluded.route_assignment_id,
    updated_by=v_user,
    updated_at=now();

  -- Snapshot the selected vehicle on the actual start, never next-day selection.
  select s.vehicle_id into v_vehicle_id
  from public.work_vehicle_route_selections s
  join public.vehicles v on v.id=s.vehicle_id and v.company_id=v_company
  where s.company_id=v_company and s.worker_id=v_worker
    and s.work_date=v_local::date;

  insert into public.attendance_verifications(
    company_id,worker_id,site_id,route_assignment_id,vehicle_id,
    event_type,verification_mode,confirmed_at,
    latitude,longitude,accuracy_m,distance_to_site_m,
    proximity_status,note,created_by
  )
  values(
    v_company,v_worker,v_schedule.site_id,v_schedule.route_assignment_id,v_vehicle_id,
    'clock_in','gps_auto',now(),
    p_latitude,p_longitude,p_accuracy_m,v_distance,
    'near_site',
    case when v_schedule.route_assignment_id is not null
      then 'GPS自動出勤：'||coalesce(v_target_label,'ルート地点')
      else 'GPS自動出勤'
    end,
    v_user
  )
  returning id into v_id;

  update public.gps_auto_attendance_schedules
  set last_attempt_date=v_local::date,
      last_result='clocked_in',
      updated_at=now()
  where company_id=v_company and worker_id=v_worker;

  return jsonb_build_object(
    'status','clocked_in',
    'attendance_id',v_id,
    'distance_m',v_distance,
    'route_stop_id',v_stop_id,
    'target_label',v_target_label
  );
end
$function$;

CREATE OR REPLACE FUNCTION private.link_daily_report_attendance_evidence(p_report_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_site uuid;
  v_route uuid;
  v_date date;
  v_count integer;
  v_start timestamptz;
  v_end timestamptz;
begin
  select d.company_id,d.site_id,d.route_assignment_id,d.report_date
  into v_company,v_site,v_route,v_date
  from public.daily_reports d
  where d.id=p_report_id
  limit 1;

  if v_company is null then raise exception '日報を確認できません'; end if;
  if not exists(
    select 1 from public.company_members m
    where m.company_id=v_company and m.user_id=v_user
  ) then raise exception '日報を確認する権限がありません'; end if;

  v_start:=v_date::timestamp at time zone 'Asia/Tokyo';
  v_end:=(v_date+1)::timestamp at time zone 'Asia/Tokyo';

  update public.attendance_verifications a
  set daily_report_id=p_report_id
  where a.company_id=v_company
    and a.site_id is not distinct from v_site
    and a.route_assignment_id is not distinct from v_route
    and coalesce(a.work_date,(a.confirmed_at at time zone 'Asia/Tokyo')::date)=v_date
    and a.photo_storage_path is not null
    and a.daily_report_id is null;

  get diagnostics v_count=row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.daily_report_clocked_in_destinations(p_date date)
 RETURNS TABLE(destination_kind text, destination_id uuid, destination_name text, site_id uuid, route_assignment_id uuid, worker_id uuid, worker_name text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with membership as (
    select cm.company_id
    from public.company_members cm
    where cm.user_id=auth.uid()
    limit 1
  ),
  first_clock_in as (
    select distinct on (
      av.worker_id,
      coalesce(av.site_id,av.route_assignment_id)
    )
      av.worker_id,
      av.site_id,
      av.route_assignment_id,
      av.confirmed_at
    from public.attendance_verifications av
    join membership m on m.company_id=av.company_id
    where av.event_type='clock_in'
      and coalesce(av.work_date,(av.confirmed_at at time zone 'Asia/Tokyo')::date)=p_date
      and ((av.site_id is not null and av.route_assignment_id is null)
        or (av.site_id is null and av.route_assignment_id is not null))
    order by
      av.worker_id,
      coalesce(av.site_id,av.route_assignment_id),
      av.confirmed_at
  )
  select
    case when f.site_id is not null then 'site' else 'route' end,
    coalesce(f.site_id,f.route_assignment_id),
    coalesce(s.name,r.route_name,'未登録'),
    f.site_id,
    f.route_assignment_id,
    w.id,
    w.name
  from first_clock_in f
  join public.workers w on w.id=f.worker_id
  left join public.sites s on s.id=f.site_id
  left join public.route_assignments r on r.id=f.route_assignment_id
  order by 3,w.name;
$function$;

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
$function$;

-- Canonical shifts keep their report date/destination. Editing text, signatures
-- and review status remains available; management replaces a complete shift.
create or replace function private.guard_daily_report_shift_identity()
returns trigger language plpgsql security invoker set search_path='' as $$
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
end $$;
revoke all on function private.guard_daily_report_shift_identity() from public, anon;
create trigger daily_report_shift_identity_guard
  before update of company_id,report_date,site_id,route_assignment_id
  on public.daily_reports for each row
  execute function private.guard_daily_report_shift_identity();
