-- Keep all "today" decisions aligned with the production user timezone.
-- The full function bodies are forward replacements of the functions introduced in
-- 20261002003417_add_gps_auto_attendance_and_evidence_link.sql.

create or replace function private.save_my_attendance_selection(
  p_mode text,
  p_site_id uuid,
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
  v_today date;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  v_today:=(now() at time zone v_timezone)::date;

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
  if p_site_id is null or not exists(
    select 1 from public.sites s
    where s.id=p_site_id and s.company_id=v_company and s.status<>'completed'
  ) then
    raise exception '現場を確認してください';
  end if;

  insert into public.work_attendance_selections(
    company_id,worker_id,work_date,verification_mode,site_id,updated_by,updated_at
  )
  values(v_company,v_worker,v_today,v_mode,p_site_id,v_user,now())
  on conflict(company_id,worker_id,work_date)
  do update set
    verification_mode=excluded.verification_mode,
    site_id=excluded.site_id,
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
      company_id,worker_id,site_id,weekdays,local_time,timezone,
      radius_m,enabled,last_attempt_date,last_result,updated_by,updated_at
    )
    values(
      v_company,v_worker,p_site_id,p_weekdays,p_local_time,
      v_timezone,300,true,null,null,v_user,now()
    )
    on conflict(company_id,worker_id)
    do update set
      site_id=excluded.site_id,
      weekdays=excluded.weekdays,
      local_time=excluded.local_time,
      timezone=excluded.timezone,
      enabled=true,
      updated_by=v_user,
      updated_at=now();
  end if;

  return jsonb_build_object(
    'mode',v_mode,'site_id',p_site_id,'work_date',v_today
  );
end
$$;

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
    'site_address',s.address
  )
  into v_selection
  from public.work_attendance_selections a
  join public.sites s on s.id=a.site_id
  where a.company_id=v_company
    and a.worker_id=v_worker
    and a.work_date=v_today;

  select jsonb_build_object(
    'enabled',g.enabled,
    'site_id',g.site_id,
    'site_name',s.name,
    'site_address',s.address,
    'weekdays',g.weekdays,
    'local_time',g.local_time::text,
    'timezone',g.timezone,
    'radius_m',g.radius_m,
    'last_attempt_date',g.last_attempt_date,
    'last_result',g.last_result
  )
  into v_schedule
  from public.gps_auto_attendance_schedules g
  join public.sites s on s.id=g.site_id
  where g.company_id=v_company and g.worker_id=v_worker;

  return jsonb_build_object(
    'selection',coalesce(v_selection,'{}'::jsonb),
    'gps_schedule',coalesce(v_schedule,'{}'::jsonb)
  );
end
$$;

create or replace function private.link_daily_report_attendance_evidence(
  p_report_id uuid
)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_site uuid;
  v_date date;
  v_count integer;
  v_start timestamptz;
  v_end timestamptz;
begin
  select d.company_id,d.site_id,d.report_date
  into v_company,v_site,v_date
  from public.daily_reports d
  where d.id=p_report_id
  limit 1;

  if v_company is null then raise exception '日報を確認できません'; end if;
  if not exists(
    select 1 from public.company_members m
    where m.company_id=v_company and m.user_id=v_user
  ) then
    raise exception '日報を確認する権限がありません';
  end if;

  v_start:=v_date::timestamp at time zone 'Asia/Tokyo';
  v_end:=(v_date+1)::timestamp at time zone 'Asia/Tokyo';

  update public.attendance_verifications a
  set daily_report_id=p_report_id
  where a.company_id=v_company
    and a.site_id=v_site
    and a.confirmed_at >= v_start
    and a.confirmed_at < v_end
    and a.photo_storage_path is not null
    and a.daily_report_id is null;

  get diagnostics v_count=row_count;
  return v_count;
end
$$;
