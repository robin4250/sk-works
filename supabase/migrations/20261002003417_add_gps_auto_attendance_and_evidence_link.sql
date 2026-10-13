create table if not exists public.work_attendance_selections (
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  work_date date not null,
  verification_mode text not null default 'manual'
    check (verification_mode in ('manual','gps_auto','location_photo')),
  site_id uuid references public.sites(id) on delete set null,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key(company_id,worker_id,work_date)
);

alter table public.work_attendance_selections enable row level security;

drop policy if exists "worker can view own attendance selection"
on public.work_attendance_selections;
create policy "worker can view own attendance selection"
on public.work_attendance_selections for select
using (
  exists(
    select 1 from public.workers w
    where w.id=work_attendance_selections.worker_id
      and w.company_id=work_attendance_selections.company_id
      and w.user_id=(select auth.uid())
  )
);

drop policy if exists "worker can insert own attendance selection"
on public.work_attendance_selections;
create policy "worker can insert own attendance selection"
on public.work_attendance_selections for insert
with check (
  exists(
    select 1 from public.workers w
    where w.id=work_attendance_selections.worker_id
      and w.company_id=work_attendance_selections.company_id
      and w.user_id=(select auth.uid())
  )
);

drop policy if exists "worker can update own attendance selection"
on public.work_attendance_selections;
create policy "worker can update own attendance selection"
on public.work_attendance_selections for update
using (
  exists(
    select 1 from public.workers w
    where w.id=work_attendance_selections.worker_id
      and w.company_id=work_attendance_selections.company_id
      and w.user_id=(select auth.uid())
  )
)
with check (
  exists(
    select 1 from public.workers w
    where w.id=work_attendance_selections.worker_id
      and w.company_id=work_attendance_selections.company_id
      and w.user_id=(select auth.uid())
  )
);

grant select,insert,update on public.work_attendance_selections to authenticated;

create table if not exists public.gps_auto_attendance_schedules (
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  weekdays smallint[] not null default array[1,2,3,4,5]::smallint[],
  local_time time not null default '08:00',
  timezone text not null default 'Asia/Tokyo',
  radius_m integer not null default 300 check (radius_m between 50 and 3000),
  enabled boolean not null default true,
  last_attempt_date date,
  last_result text,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key(company_id,worker_id),
  check (
    array_length(weekdays,1) is not null
    and weekdays <@ array[1,2,3,4,5,6,7]::smallint[]
  )
);

alter table public.gps_auto_attendance_schedules enable row level security;

drop policy if exists "worker can manage own gps auto schedule"
on public.gps_auto_attendance_schedules;
create policy "worker can manage own gps auto schedule"
on public.gps_auto_attendance_schedules
for all
using (
  exists(
    select 1 from public.workers w
    where w.id=gps_auto_attendance_schedules.worker_id
      and w.company_id=gps_auto_attendance_schedules.company_id
      and w.user_id=(select auth.uid())
  )
)
with check (
  exists(
    select 1 from public.workers w
    where w.id=gps_auto_attendance_schedules.worker_id
      and w.company_id=gps_auto_attendance_schedules.company_id
      and w.user_id=(select auth.uid())
  )
);

grant select,insert,update on public.gps_auto_attendance_schedules to authenticated;

alter table public.attendance_verifications
  add column if not exists daily_report_id uuid
    references public.daily_reports(id) on delete set null;

create index if not exists attendance_verifications_daily_report_idx
  on public.attendance_verifications(daily_report_id)
  where daily_report_id is not null;

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
  v_today date:=current_date;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;

  select cm.company_id,w.id
  into v_company,v_worker
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
    where s.id=p_site_id
      and s.company_id=v_company
      and s.status<>'completed'
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
      coalesce(nullif(trim(p_timezone),''),'Asia/Tokyo'),
      300,true,null,null,v_user,now()
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
    'mode',v_mode,
    'site_id',p_site_id,
    'work_date',v_today
  );
end
$$;

create or replace function public.save_my_attendance_selection(
  p_mode text,
  p_site_id uuid,
  p_weekdays smallint[] default null,
  p_local_time time default null,
  p_timezone text default 'Asia/Tokyo'
)
returns jsonb
language sql
set search_path=''
as $$
  select private.save_my_attendance_selection(
    p_mode,p_site_id,p_weekdays,p_local_time,p_timezone
  )
$$;

revoke all on function public.save_my_attendance_selection(
  text,uuid,smallint[],time,text
) from public,anon;
grant execute on function public.save_my_attendance_selection(
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
  v_today date:=current_date;
  v_selection jsonb;
  v_schedule jsonb;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;

  select cm.company_id,w.id
  into v_company,v_worker
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

create or replace function public.my_attendance_selection_workspace()
returns jsonb
language sql
set search_path=''
as $$ select private.my_attendance_selection_workspace() $$;

revoke all on function public.my_attendance_selection_workspace()
from public,anon;
grant execute on function public.my_attendance_selection_workspace()
to authenticated;

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
    return jsonb_build_object('status','already_attempted','result',v_schedule.last_result);
  end if;

  v_scheduled:=v_local::date + v_schedule.local_time;
  if abs(extract(epoch from (v_local-v_scheduled)))>300 then
    return jsonb_build_object('status','outside_time_window');
  end if;

  select * into v_site
  from public.sites s
  where s.id=v_schedule.site_id
    and s.company_id=v_company;

  if v_site.latitude is null or v_site.longitude is null then
    update public.gps_auto_attendance_schedules
    set last_attempt_date=v_local::date,last_result='site_location_missing',updated_at=now()
    where company_id=v_company and worker_id=v_worker;
    perform private.enqueue_notification(
      v_company,v_user,'attendance',
      'GPS自動出勤を登録しませんでした',
      '選択中の現場に基準位置が登録されていません。',
      'attendance_verify',null
    );
    return jsonb_build_object('status','site_location_missing');
  end if;

  select av.event_type into v_existing
  from public.attendance_verifications av
  where av.worker_id=v_worker
    and av.confirmed_at >= (v_local::date::timestamp at time zone v_schedule.timezone)
    and av.confirmed_at < ((v_local::date+1)::timestamp at time zone v_schedule.timezone)
  order by av.confirmed_at desc
  limit 1;

  if v_existing in ('clock_in','clock_out') then
    update public.gps_auto_attendance_schedules
    set last_attempt_date=v_local::date,last_result='already_recorded',updated_at=now()
    where company_id=v_company and worker_id=v_worker;
    return jsonb_build_object('status','already_recorded');
  end if;

  v_distance:=6371000 * acos(
    least(1.0,greatest(-1.0,
      sin(radians(p_latitude))*sin(radians(v_site.latitude)) +
      cos(radians(p_latitude))*cos(radians(v_site.latitude)) *
      cos(radians(p_longitude-v_site.longitude))
    ))
  );

  if v_distance>v_schedule.radius_m then
    update public.gps_auto_attendance_schedules
    set last_attempt_date=v_local::date,last_result='outside_site',updated_at=now()
    where company_id=v_company and worker_id=v_worker;

    perform private.enqueue_notification(
      v_company,v_user,'attendance',
      'GPS自動出勤を登録しませんでした',
      '現場にいないようなのでGPS自動出勤は出勤を登録しませんでした。',
      'attendance_verify',null
    );

    return jsonb_build_object(
      'status','outside_site',
      'distance_m',v_distance
    );
  end if;

  insert into public.work_attendance_selections(
    company_id,worker_id,work_date,verification_mode,site_id,updated_by,updated_at
  )
  values(
    v_company,v_worker,v_local::date,'gps_auto',v_schedule.site_id,v_user,now()
  )
  on conflict(company_id,worker_id,work_date)
  do update set
    verification_mode='gps_auto',
    site_id=excluded.site_id,
    updated_by=v_user,
    updated_at=now();

  insert into public.attendance_verifications(
    company_id,worker_id,site_id,event_type,verification_mode,
    confirmed_at,latitude,longitude,accuracy_m,distance_to_site_m,
    proximity_status,note,created_by
  )
  values(
    v_company,v_worker,v_schedule.site_id,'clock_in','gps_auto',
    now(),p_latitude,p_longitude,p_accuracy_m,v_distance,
    'near_site','GPS自動出勤',v_user
  )
  returning id into v_id;

  update public.gps_auto_attendance_schedules
  set last_attempt_date=v_local::date,last_result='clocked_in',updated_at=now()
  where company_id=v_company and worker_id=v_worker;

  return jsonb_build_object(
    'status','clocked_in',
    'attendance_id',v_id,
    'distance_m',v_distance
  );
end
$$;

create or replace function public.attempt_gps_auto_attendance(
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_m double precision
)
returns jsonb
language sql
set search_path=''
as $$
  select private.attempt_gps_auto_attendance(
    p_latitude,p_longitude,p_accuracy_m
  )
$$;

revoke all on function public.attempt_gps_auto_attendance(
  double precision,double precision,double precision
) from public,anon;
grant execute on function public.attempt_gps_auto_attendance(
  double precision,double precision,double precision
) to authenticated;

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

  update public.attendance_verifications a
  set daily_report_id=p_report_id
  where a.company_id=v_company
    and a.site_id=v_site
    and a.confirmed_at >= v_date::timestamp
    and a.confirmed_at < (v_date+1)::timestamp
    and a.photo_storage_path is not null
    and a.daily_report_id is null;

  get diagnostics v_count=row_count;
  return v_count;
end
$$;

create or replace function public.link_daily_report_attendance_evidence(
  p_report_id uuid
)
returns integer
language sql
set search_path=''
as $$ select private.link_daily_report_attendance_evidence(p_report_id) $$;

revoke all on function public.link_daily_report_attendance_evidence(uuid)
from public,anon;
grant execute on function public.link_daily_report_attendance_evidence(uuid)
to authenticated;
