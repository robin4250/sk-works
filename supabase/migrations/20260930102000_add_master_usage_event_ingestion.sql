-- Privacy-bounded product usage analytics foundation.
-- Records only explicitly allowlisted event/surface/feature keys. No arbitrary metadata,
-- message/file/photo contents, coordinates, phone numbers, or document data.

create index if not exists master_usage_events_user_recent_idx
  on private.master_usage_events(user_id,occurred_at desc)
  where user_id is not null;

create or replace function public.record_usage_event(
  p_event_key text,
  p_surface_key text default null,
  p_feature_key text default null
)
returns void
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_event_key text := lower(btrim(coalesce(p_event_key,'')));
  v_surface_key text := nullif(lower(btrim(coalesce(p_surface_key,''))), '');
  v_feature_key text := nullif(lower(btrim(coalesce(p_feature_key,''))), '');
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if v_event_key <> all(array[
       'page_open',
       'button_tap',
       'feature_use',
       'action_complete'
     ]::text[]) then
    raise exception 'invalid event key';
  end if;

  if v_surface_key is not null and v_surface_key <> all(array[
       'home',
       'attendance',
       'attendance_sheet',
       'daily_report',
       'payroll',
       'invoice',
       'chat',
       'people',
       'qualifications',
       'documents',
       'sites',
       'vehicle_routes',
       'settings',
       'profile',
       'help'
     ]::text[]) then
    raise exception 'invalid surface key';
  end if;

  if v_feature_key is not null and v_feature_key <> all(array[
       'clock_in',
       'clock_out',
       'attendance',
       'daily_report',
       'payroll',
       'invoice',
       'chat',
       'print',
       'company_connection',
       'people',
       'qualifications',
       'documents',
       'site_chat',
       'vehicle_management',
       'route_assignment'
     ]::text[]) then
    raise exception 'invalid feature key';
  end if;

  if (
    select count(*)
    from private.master_usage_events mue
    where mue.user_id=v_user_id
      and mue.occurred_at >= now() - interval '1 minute'
  ) >= 120 then
    raise exception 'usage event rate limit exceeded';
  end if;

  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id=v_user_id
  limit 1;

  if v_company_id is null then
    raise exception 'company membership required';
  end if;

  insert into private.master_usage_events(
    company_id,
    user_id,
    event_key,
    surface_key,
    feature_key
  ) values (
    v_company_id,
    v_user_id,
    v_event_key,
    v_surface_key,
    v_feature_key
  );
end;
$$;

revoke all on function public.record_usage_event(text,text,text)
  from public, anon;
grant execute on function public.record_usage_event(text,text,text)
  to authenticated;

create or replace function public.get_master_usage_snapshot(
  p_days integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path='public','private','pg_temp'
as $$
declare
  v_days integer := greatest(1,least(coalesce(p_days,30),365));
  v_result jsonb;
begin
  if not public.is_current_user_master_admin() then
    return null;
  end if;

  with scoped as (
    select event_key,surface_key,feature_key,company_id,user_id
    from private.master_usage_events
    where occurred_at >= now() - make_interval(days => v_days)
  ),
  event_rank as (
    select
      event_key,
      count(*) as event_count,
      count(distinct company_id) filter (where company_id is not null) as company_count,
      count(distinct user_id) filter (where user_id is not null) as user_count
    from scoped
    group by event_key
    order by event_count desc,event_key
    limit 20
  ),
  surface_rank as (
    select
      surface_key,
      count(*) as event_count
    from scoped
    where surface_key is not null
    group by surface_key
    order by event_count desc,surface_key
    limit 20
  ),
  feature_rank as (
    select
      feature_key,
      count(*) as event_count
    from scoped
    where feature_key is not null
    group by feature_key
    order by event_count desc,feature_key
    limit 20
  )
  select jsonb_build_object(
    'window_days',v_days,
    'events_total',(select count(*) from scoped),
    'companies_active',(select count(distinct company_id) from scoped where company_id is not null),
    'users_active',(select count(distinct user_id) from scoped where user_id is not null),
    'top_events',coalesce((
      select jsonb_agg(jsonb_build_object(
        'event_key',event_key,
        'event_count',event_count,
        'company_count',company_count,
        'user_count',user_count
      ) order by event_count desc,event_key)
      from event_rank
    ),'[]'::jsonb),
    'top_surfaces',coalesce((
      select jsonb_agg(jsonb_build_object(
        'surface_key',surface_key,
        'event_count',event_count
      ) order by event_count desc,surface_key)
      from surface_rank
    ),'[]'::jsonb),
    'top_features',coalesce((
      select jsonb_agg(jsonb_build_object(
        'feature_key',feature_key,
        'event_count',event_count
      ) order by event_count desc,feature_key)
      from feature_rank
    ),'[]'::jsonb)
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_master_usage_snapshot(integer)
  from public, anon;
grant execute on function public.get_master_usage_snapshot(integer)
  to authenticated;
