-- Extend privacy-bounded Master usage analytics with aggregate reach and trend metrics.
-- No company/user identifiers or free-form metadata are returned.

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

  with current_scoped as (
    select event_key,surface_key,feature_key,company_id,user_id
    from private.master_usage_events
    where occurred_at >= now() - make_interval(days => v_days)
  ),
  previous_scoped as (
    select event_key,surface_key,feature_key,company_id,user_id
    from private.master_usage_events
    where occurred_at < now() - make_interval(days => v_days)
      and occurred_at >= now() - make_interval(days => v_days * 2)
  ),
  event_rank as (
    select
      event_key,
      count(*) as event_count,
      count(distinct company_id) filter (where company_id is not null) as company_count,
      count(distinct user_id) filter (where user_id is not null) as user_count
    from current_scoped
    group by event_key
    order by event_count desc,event_key
    limit 20
  ),
  surface_rank as (
    select
      surface_key,
      count(*) as event_count,
      count(distinct company_id) filter (where company_id is not null) as company_count,
      count(distinct user_id) filter (where user_id is not null) as user_count
    from current_scoped
    where surface_key is not null
    group by surface_key
    order by event_count desc,surface_key
    limit 20
  ),
  feature_rank as (
    select
      feature_key,
      count(*) as event_count,
      count(distinct company_id) filter (where company_id is not null) as company_count,
      count(distinct user_id) filter (where user_id is not null) as user_count
    from current_scoped
    where feature_key is not null
    group by feature_key
    order by event_count desc,feature_key
    limit 20
  ),
  current_totals as (
    select
      count(*)::bigint as events_total,
      count(distinct company_id) filter (where company_id is not null)::bigint as companies_active,
      count(distinct user_id) filter (where user_id is not null)::bigint as users_active
    from current_scoped
  ),
  previous_totals as (
    select
      count(*)::bigint as events_total,
      count(distinct company_id) filter (where company_id is not null)::bigint as companies_active,
      count(distinct user_id) filter (where user_id is not null)::bigint as users_active
    from previous_scoped
  )
  select jsonb_build_object(
    'window_days',v_days,
    'events_total',ct.events_total,
    'companies_active',ct.companies_active,
    'users_active',ct.users_active,
    'events_per_company',case when ct.companies_active = 0 then 0 else round(ct.events_total::numeric / ct.companies_active, 2) end,
    'events_per_user',case when ct.users_active = 0 then 0 else round(ct.events_total::numeric / ct.users_active, 2) end,
    'previous_events_total',pt.events_total,
    'previous_companies_active',pt.companies_active,
    'previous_users_active',pt.users_active,
    'events_change_percent',case
      when pt.events_total = 0 then null
      else round(((ct.events_total - pt.events_total)::numeric / pt.events_total) * 100, 1)
    end,
    'companies_change_percent',case
      when pt.companies_active = 0 then null
      else round(((ct.companies_active - pt.companies_active)::numeric / pt.companies_active) * 100, 1)
    end,
    'users_change_percent',case
      when pt.users_active = 0 then null
      else round(((ct.users_active - pt.users_active)::numeric / pt.users_active) * 100, 1)
    end,
    'top_events',coalesce((
      select jsonb_agg(jsonb_build_object(
        'event_key',event_key,
        'event_count',event_count,
        'company_count',company_count,
        'user_count',user_count,
        'events_per_company',case when company_count = 0 then 0 else round(event_count::numeric / company_count, 2) end,
        'events_per_user',case when user_count = 0 then 0 else round(event_count::numeric / user_count, 2) end
      ) order by event_count desc,event_key)
      from event_rank
    ),'[]'::jsonb),
    'top_surfaces',coalesce((
      select jsonb_agg(jsonb_build_object(
        'surface_key',surface_key,
        'event_count',event_count,
        'company_count',company_count,
        'user_count',user_count,
        'events_per_company',case when company_count = 0 then 0 else round(event_count::numeric / company_count, 2) end,
        'events_per_user',case when user_count = 0 then 0 else round(event_count::numeric / user_count, 2) end
      ) order by event_count desc,surface_key)
      from surface_rank
    ),'[]'::jsonb),
    'top_features',coalesce((
      select jsonb_agg(jsonb_build_object(
        'feature_key',feature_key,
        'event_count',event_count,
        'company_count',company_count,
        'user_count',user_count,
        'events_per_company',case when company_count = 0 then 0 else round(event_count::numeric / company_count, 2) end,
        'events_per_user',case when user_count = 0 then 0 else round(event_count::numeric / user_count, 2) end
      ) order by event_count desc,feature_key)
      from feature_rank
    ),'[]'::jsonb)
  )
  into v_result
  from current_totals ct
  cross join previous_totals pt;

  return v_result;
end;
$$;

revoke all on function public.get_master_usage_snapshot(integer)
  from public, anon;
grant execute on function public.get_master_usage_snapshot(integer)
  to authenticated;
