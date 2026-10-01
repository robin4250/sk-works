create or replace function private.site_map_workspace()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_role text;
  v_worker uuid;
  v_sites jsonb;
  v_workers jsonb;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  select m.company_id,m.role::text into v_company,v_role
  from public.company_members m
  where m.user_id=v_user
  limit 1;
  if v_company is null then raise exception '会社への所属が必要です'; end if;

  select w.id into v_worker
  from public.workers w
  where w.company_id=v_company and w.user_id=v_user
  limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'site_id',s.id,
    'site_name',s.name,
    'address',coalesce(s.address,''),
    'latitude',s.latitude,
    'longitude',s.longitude,
    'status',s.status
  ) order by s.name),'[]'::jsonb)
  into v_sites
  from public.sites s
  where s.company_id=v_company
    and s.status<>'completed'
    and s.latitude is not null
    and s.longitude is not null;

  with latest as (
    select distinct on (a.worker_id)
      a.worker_id,a.site_id,a.latitude,a.longitude,a.confirmed_at,a.event_type
    from public.attendance_verifications a
    join public.workers w on w.id=a.worker_id
    where w.company_id=v_company
      and a.latitude is not null
      and a.longitude is not null
      and (
        v_role in ('owner','admin','manager')
        or a.worker_id=v_worker
      )
    order by a.worker_id,a.confirmed_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'worker_id',w.id,
    'worker_name',w.name,
    'site_id',l.site_id,
    'site_name',coalesce(s.name,''),
    'latitude',l.latitude,
    'longitude',l.longitude,
    'confirmed_at',l.confirmed_at,
    'event_type',l.event_type
  ) order by w.name),'[]'::jsonb)
  into v_workers
  from latest l
  join public.workers w on w.id=l.worker_id
  left join public.sites s on s.id=l.site_id;

  return jsonb_build_object(
    'can_view_all',v_role in ('owner','admin','manager'),
    'sites',v_sites,
    'workers',v_workers
  );
end
$$;

create or replace function public.site_map_workspace()
returns jsonb language sql set search_path=''
as $$ select private.site_map_workspace() $$;

revoke all on function public.site_map_workspace() from public,anon;
grant execute on function public.site_map_workspace() to authenticated;
