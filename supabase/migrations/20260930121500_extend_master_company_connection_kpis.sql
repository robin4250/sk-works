-- Extend aggregate-only Master growth analytics with company-connection KPIs.
-- A company is "connected" when it has at least one partner_companies row.

create or replace function public.get_master_growth_snapshot()
returns jsonb
language sql
security definer
set search_path = public, private
as $$
  select case when public.is_current_user_master_admin() then
    jsonb_build_object(
      'companies', (select count(*) from public.companies),
      'users', (select count(distinct user_id) from public.company_members),
      'connections', (select count(*) from public.partner_companies),
      'connected_companies', (
        select count(distinct company_id)
        from public.partner_companies
      ),
      'unconnected_companies', (
        select greatest(
          (select count(*) from public.companies) -
          (select count(distinct company_id) from public.partner_companies),
          0
        )
      ),
      'connection_rate_percent', (
        select case
          when count(*) = 0 then 0
          else round(
            (
              select count(distinct company_id)::numeric
              from public.partner_companies
            ) / count(*)::numeric * 100,
            1
          )
        end
        from public.companies
      ),
      'companies_last_7_days', (
        select count(*) from public.companies
        where created_at >= now() - interval '7 days'
      ),
      'companies_last_30_days', (
        select count(*) from public.companies
        where created_at >= now() - interval '30 days'
      ),
      'companies_current_month', (
        select count(*) from public.companies
        where created_at >= date_trunc('month', now())
      ),
      'users_last_7_days', (
        select count(distinct user_id) from public.company_members
        where created_at >= now() - interval '7 days'
      ),
      'users_last_30_days', (
        select count(distinct user_id) from public.company_members
        where created_at >= now() - interval '30 days'
      ),
      'users_current_month', (
        select count(distinct user_id) from public.company_members
        where created_at >= date_trunc('month', now())
      ),
      'members_per_company_average', (
        select coalesce(avg(member_count), 0)
        from (
          select count(*)::numeric as member_count
          from public.company_members
          group by company_id
        ) counts
      ),
      'members_per_company_median', (
        select coalesce(
          percentile_cont(0.5) within group (order by member_count),
          0
        )
        from (
          select count(*)::numeric as member_count
          from public.company_members
          group by company_id
        ) counts
      ),
      'members_per_company_min', (
        select coalesce(min(member_count), 0)
        from (
          select count(*) as member_count
          from public.company_members
          group by company_id
        ) counts
      ),
      'members_per_company_max', (
        select coalesce(max(member_count), 0)
        from (
          select count(*) as member_count
          from public.company_members
          group by company_id
        ) counts
      )
    )
  else null end;
$$;

revoke all on function public.get_master_growth_snapshot() from public, anon;
grant execute on function public.get_master_growth_snapshot() to authenticated;
