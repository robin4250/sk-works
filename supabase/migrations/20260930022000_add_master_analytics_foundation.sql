-- Master analytics foundation.
-- Collects operational counts only. No message bodies, photos, file contents,
-- passwords, OTPs, My Number images, or other private document contents.

create table if not exists private.master_usage_events (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  company_id uuid,
  user_id uuid,
  event_key text not null check (length(event_key) between 1 and 120),
  surface_key text,
  feature_key text,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists master_usage_events_occurred_idx
  on private.master_usage_events (occurred_at desc);
create index if not exists master_usage_events_feature_idx
  on private.master_usage_events (feature_key, occurred_at desc);
create index if not exists master_usage_events_company_idx
  on private.master_usage_events (company_id, occurred_at desc);

revoke all on private.master_usage_events from anon, authenticated;

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
      -- Current production company-link source. Replace with the formal
      -- connection table when that contract is introduced.
      'connections', (
        select count(*) from public.partner_companies
      ),
      'companies_last_7_days', (
        select count(*) from public.companies
        where created_at >= now() - interval '7 days'
      ),
      'companies_last_30_days', (
        select count(*) from public.companies
        where created_at >= now() - interval '30 days'
      ),
      'users_last_7_days', (
        select count(distinct user_id) from public.company_members
        where created_at >= now() - interval '7 days'
      ),
      'users_last_30_days', (
        select count(distinct user_id) from public.company_members
        where created_at >= now() - interval '30 days'
      ),
      'members_per_company_average', (
        select coalesce(avg(member_count), 0)
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

revoke all on function public.get_master_growth_snapshot() from public;
grant execute on function public.get_master_growth_snapshot() to authenticated;
