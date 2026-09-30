-- Privacy-preserving usage event foundation for Master analytics.
-- Only fixed product keys are accepted. No free-form metadata, content, GPS,
-- file names, document values, phone numbers, or user-entered text is stored.

create or replace function public.record_usage_event(
  p_event_key text,
  p_surface_key text,
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
begin
  if v_user_id is null then
    return;
  end if;

  if p_event_key not in ('page_view','action') then
    raise exception 'unsupported usage event key';
  end if;

  if p_surface_key not in (
    'home',
    'attendance',
    'attendance_sheet',
    'daily_report',
    'payroll',
    'invoice',
    'chat',
    'company_exchange',
    'vehicle_routes',
    'sites',
    'people',
    'qualifications',
    'documents',
    'profile',
    'settings',
    'help'
  ) then
    raise exception 'unsupported usage surface key';
  end if;

  if p_feature_key is not null and p_feature_key not in (
    'open',
    'clock_in',
    'clock_out',
    'print',
    'share',
    'send',
    'approve',
    'edit',
    'create',
    'archive',
    'vehicle',
    'route',
    'site_chat'
  ) then
    raise exception 'unsupported usage feature key';
  end if;

  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id=v_user_id
  limit 1;

  if v_company_id is null then
    return;
  end if;

  insert into private.master_usage_events(
    company_id,
    user_id,
    event_key,
    surface_key,
    feature_key,
    metadata
  ) values (
    v_company_id,
    v_user_id,
    p_event_key,
    p_surface_key,
    p_feature_key,
    '{}'::jsonb
  );
end;
$$;

revoke all on function public.record_usage_event(text,text,text)
  from public, anon;
grant execute on function public.record_usage_event(text,text,text)
  to authenticated;

create or replace function public.get_master_usage_ranking(
  p_days integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path='public','private','pg_temp'
as $$
declare
  v_result jsonb;
begin
  if not public.is_current_user_master_admin() then
    return null;
  end if;

  if p_days not in (7,30,90) then
    raise exception 'unsupported usage ranking period';
  end if;

  with scoped as (
    select
      event_key,
      surface_key,
      feature_key,
      company_id,
      user_id
    from private.master_usage_events
    where occurred_at >= now() - make_interval(days => p_days)
  ),
  ranked as (
    select
      event_key,
      surface_key,
      feature_key,
      count(*) as event_count,
      count(distinct company_id) as company_count,
      count(distinct user_id) as user_count
    from scoped
    group by event_key,surface_key,feature_key
    order by event_count desc,event_key,surface_key,feature_key
    limit 50
  )
  select jsonb_build_object(
    'days', p_days,
    'events_total', (select count(*) from scoped),
    'companies_active', (select count(distinct company_id) from scoped),
    'users_active', (select count(distinct user_id) from scoped),
    'rankings', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'event_key',event_key,
            'surface_key',surface_key,
            'feature_key',feature_key,
            'event_count',event_count,
            'company_count',company_count,
            'user_count',user_count
          )
          order by event_count desc,event_key,surface_key,feature_key
        )
        from ranked
      ),
      '[]'::jsonb
    )
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_master_usage_ranking(integer)
  from public, anon;
grant execute on function public.get_master_usage_ranking(integer)
  to authenticated;
