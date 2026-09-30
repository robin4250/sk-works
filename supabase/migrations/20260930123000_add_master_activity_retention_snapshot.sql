-- Aggregate-only Master activity, retention, and growth-velocity KPIs.
-- Company/user identifiers remain internal to aggregation and are never returned.

create or replace function public.get_master_activity_snapshot()
returns jsonb
language sql
stable
security definer
set search_path='public','private','pg_temp'
as $$
  with usage_windows as (
    select
      company_id,
      bool_or(occurred_at >= now() - interval '7 days') as active_7,
      bool_or(
        occurred_at >= now() - interval '14 days'
        and occurred_at < now() - interval '7 days'
      ) as active_prev_7,
      bool_or(occurred_at >= now() - interval '30 days') as active_30,
      bool_or(
        occurred_at >= now() - interval '60 days'
        and occurred_at < now() - interval '30 days'
      ) as active_prev_30
    from private.master_usage_events
    where company_id is not null
      and occurred_at >= now() - interval '60 days'
    group by company_id
  ),
  activity as (
    select
      count(*) filter (where active_7)::bigint as active_companies_7,
      count(*) filter (where active_prev_7)::bigint as previous_active_companies_7,
      count(*) filter (where active_30)::bigint as active_companies_30,
      count(*) filter (where active_prev_30)::bigint as previous_active_companies_30,
      count(*) filter (where active_30 and active_prev_30)::bigint as retained_companies_30
    from usage_windows
  ),
  registrations as (
    select
      count(*) filter (
        where created_at >= now() - interval '7 days'
      )::bigint as registrations_7,
      count(*) filter (
        where created_at >= now() - interval '14 days'
          and created_at < now() - interval '7 days'
      )::bigint as previous_registrations_7
    from public.companies
  )
  select case when public.is_current_user_master_admin() then
    jsonb_build_object(
      'active_companies_7', a.active_companies_7,
      'active_companies_30', a.active_companies_30,
      'previous_active_companies_7', a.previous_active_companies_7,
      'previous_active_companies_30', a.previous_active_companies_30,
      'retained_companies_30', a.retained_companies_30,
      'retention_rate_30_percent', case
        when a.previous_active_companies_30 = 0 then null
        else round(
          a.retained_companies_30::numeric /
          a.previous_active_companies_30::numeric * 100,
          1
        )
      end,
      'usage_growth_7_percent', case
        when a.previous_active_companies_7 = 0 then null
        else round(
          (a.active_companies_7 - a.previous_active_companies_7)::numeric /
          a.previous_active_companies_7::numeric * 100,
          1
        )
      end,
      'registrations_7', r.registrations_7,
      'previous_registrations_7', r.previous_registrations_7,
      'registration_growth_7_percent', case
        when r.previous_registrations_7 = 0 then null
        else round(
          (r.registrations_7 - r.previous_registrations_7)::numeric /
          r.previous_registrations_7::numeric * 100,
          1
        )
      end
    )
  else null end
  from activity a
  cross join registrations r;
$$;

revoke all on function public.get_master_activity_snapshot()
  from public, anon;
grant execute on function public.get_master_activity_snapshot()
  to authenticated;
