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
  else
    update public.gps_auto_attendance_schedules
    set enabled=false,
        updated_by=v_user,
        updated_at=now()
    where company_id=v_company and worker_id=v_worker;
  end if;

  return jsonb_build_object(
    'mode',v_mode,'site_id',p_site_id,'work_date',v_today
  );
end
$$;
