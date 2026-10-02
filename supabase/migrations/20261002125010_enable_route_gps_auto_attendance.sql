create or replace function public.save_my_route_attendance_selection(
  p_mode text,
  p_route_assignment_id uuid,
  p_weekdays smallint[] default null,
  p_local_time time default null,
  p_timezone text default 'Asia/Tokyo'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_worker uuid;
  v_mode text:=case when p_mode='location' then 'gps_auto' else p_mode end;
  v_timezone text:=coalesce(nullif(trim(p_timezone),''),'Asia/Tokyo');
  v_today date:=(now() at time zone coalesce(nullif(trim(p_timezone),''),'Asia/Tokyo'))::date;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;

  select cm.company_id,w.id into v_company,v_worker
  from public.company_members cm
  join public.workers w
    on w.company_id=cm.company_id and w.user_id=cm.user_id
  where cm.user_id=v_user
  limit 1;

  if v_company is null or v_worker is null then
    raise exception '社員情報を確認できません';
  end if;
  if v_mode not in ('manual','gps_auto','location_photo') then
    raise exception '出勤方法を確認してください';
  end if;
  if p_route_assignment_id is null or not exists(
    select 1 from public.route_assignments r
    where r.id=p_route_assignment_id
      and r.company_id=v_company
      and r.is_active=true
  ) then
    raise exception 'ルートを確認してください';
  end if;

  insert into public.work_attendance_selections(
    company_id,worker_id,work_date,verification_mode,
    site_id,route_assignment_id,updated_by,updated_at
  )
  values(
    v_company,v_worker,v_today,v_mode,
    null,p_route_assignment_id,v_user,now()
  )
  on conflict(company_id,worker_id,work_date)
  do update set
    verification_mode=excluded.verification_mode,
    site_id=null,
    route_assignment_id=excluded.route_assignment_id,
    updated_by=v_user,
    updated_at=now();

  if v_mode='gps_auto' then
    if p_weekdays is null or array_length(p_weekdays,1) is null then
      raise exception 'GPS自動出勤の曜日を選択してください';
    end if;
    if p_local_time is null then
      raise exception 'GPS取得時間を選択してください';
    end if;

    insert into public.gps_auto_attendance_schedules(
      company_id,worker_id,site_id,route_assignment_id,
      weekdays,local_time,timezone,radius_m,enabled,
      last_attempt_date,last_result,updated_by,updated_at
    )
    values(
      v_company,v_worker,null,p_route_assignment_id,
      p_weekdays,p_local_time,v_timezone,300,true,
      null,null,v_user,now()
    )
    on conflict(company_id,worker_id)
    do update set
      site_id=null,
      route_assignment_id=excluded.route_assignment_id,
      weekdays=excluded.weekdays,
      local_time=excluded.local_time,
      timezone=excluded.timezone,
      enabled=true,
      last_attempt_date=null,
      last_result=null,
      updated_by=v_user,
      updated_at=now();
  end if;

  return jsonb_build_object(
    'mode',v_mode,
    'route_assignment_id',p_route_assignment_id,
    'work_date',v_today
  );
end
$$;

revoke all on function public.save_my_route_attendance_selection(
  text,uuid,smallint[],time,text
) from public,anon;
grant execute on function public.save_my_route_attendance_selection(
  text,uuid,smallint[],time,text
) to authenticated;

create or replace function private.my_attendance_selection_workspace()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_worker uuid;
  v_today date:=(now() at time zone 'Asia/Tokyo')::date;
  v_selection jsonb;
  v_schedule jsonb;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;

  select cm.company_id,w.id into v_company,v_worker
  from public.company_members cm
  join public.workers w
    on w.company_id=cm.company_id and w.user_id=cm.user_id
  where cm.user_id=v_user
  limit 1;

  select jsonb_build_object(
    'mode',a.verification_mode,
    'site_id',a.site_id,
    'site_name',s.name,
    'site_address',s.address,
    'route_assignment_id',a.route_assignment_id,
    'route_name',r.route_name
  )
  into v_selection
  from public.work_attendance_selections a
  left join public.sites s on s.id=a.site_id
  left join public.route_assignments r on r.id=a.route_assignment_id
  where a.company_id=v_company
    and a.worker_id=v_worker
    and a.work_date=v_today;

  select jsonb_build_object(
    'enabled',g.enabled,
    'site_id',g.site_id,
    'site_name',s.name,
    'site_address',s.address,
    'route_assignment_id',g.route_assignment_id,
    'route_name',r.route_name,
    'weekdays',g.weekdays,
    'local_time',g.local_time::text,
    'timezone',g.timezone,
    'radius_m',g.radius_m,
    'last_attempt_date',g.last_attempt_date,
    'last_result',g.last_result
  )
  into v_schedule
  from public.gps_auto_attendance_schedules g
  left join public.sites s on s.id=g.site_id
  left join public.route_assignments r on r.id=g.route_assignment_id
  where g.company_id=v_company and g.worker_id=v_worker;

  return jsonb_build_object(
    'selection',coalesce(v_selection,'{}'::jsonb),
    'gps_schedule',coalesce(v_schedule,'{}'::jsonb)
  );
end
$$;

create or replace function private.attempt_gps_auto_attendance(
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_m double precision
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
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
    and av.confirmed_at >=
      (v_local::date::timestamp at time zone v_schedule.timezone)
    and av.confirmed_at <
      ((v_local::date+1)::timestamp at time zone v_schedule.timezone)
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

  insert into public.attendance_verifications(
    company_id,worker_id,site_id,route_assignment_id,
    event_type,verification_mode,confirmed_at,
    latitude,longitude,accuracy_m,distance_to_site_m,
    proximity_status,note,created_by
  )
  values(
    v_company,v_worker,v_schedule.site_id,v_schedule.route_assignment_id,
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
$$;
