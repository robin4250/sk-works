-- Aggregate Master feature-control usage status.
-- Separates disabled features from enabled-but-unused features without exposing identities.

create or replace function public.get_master_feature_usage_status(
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

  with settings as (
    select feature_key,enabled
    from private.master_feature_settings
  ),
  usage_counts as (
    select
      feature_key,
      count(*)::bigint as event_count,
      count(distinct company_id) filter (where company_id is not null)::bigint as company_count,
      count(distinct user_id) filter (where user_id is not null)::bigint as user_count
    from private.master_usage_events
    where occurred_at >= now() - make_interval(days => v_days)
      and feature_key is not null
    group by feature_key
  ),
  rows as (
    select
      s.feature_key,
      s.enabled,
      coalesce(u.event_count,0)::bigint as event_count,
      coalesce(u.company_count,0)::bigint as company_count,
      coalesce(u.user_count,0)::bigint as user_count,
      case
        when not s.enabled then 'disabled'
        when coalesce(u.event_count,0)=0 then 'enabled_unused'
        else 'enabled_used'
      end as usage_state
    from settings s
    left join usage_counts u using(feature_key)
  )
  select jsonb_build_object(
    'window_days',v_days,
    'controlled_features_total',count(*),
    'disabled_features',count(*) filter (where usage_state='disabled'),
    'enabled_unused_features',count(*) filter (where usage_state='enabled_unused'),
    'enabled_used_features',count(*) filter (where usage_state='enabled_used'),
    'features',coalesce(jsonb_agg(
      jsonb_build_object(
        'feature_key',feature_key,
        'enabled',enabled,
        'usage_state',usage_state,
        'event_count',event_count,
        'company_count',company_count,
        'user_count',user_count
      )
      order by feature_key
    ),'[]'::jsonb)
  )
  into v_result
  from rows;

  return v_result;
end;
$$;

revoke all on function public.get_master_feature_usage_status(integer)
  from public, anon;
grant execute on function public.get_master_feature_usage_status(integer)
  to authenticated;
