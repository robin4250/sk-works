-- Aggregate-only Master dashboard extension for vehicle/route rollout.
-- No vehicle names, registrations, site names, chat content, files, photos,
-- passwords, OTPs, or personal document contents are returned.

create or replace function public.get_master_operations_snapshot()
returns jsonb
language sql
stable
security definer
set search_path='public','private','pg_temp'
as $$
  select case when private.is_current_master_admin() then
    jsonb_build_object(
      'vehicles_total', (select count(*) from public.vehicles),
      'vehicles_active', (select count(*) from public.vehicles where is_active),
      'vehicles_disabled', (select count(*) from public.vehicles where not is_active),
      'routes_total', (select count(*) from public.route_assignments),
      'routes_active', (select count(*) from public.route_assignments where is_active),
      'routes_disabled', (select count(*) from public.route_assignments where not is_active),
      'sites_total', (select count(*) from public.sites),
      'site_chats_total', (
        select count(*) from public.communication_groups where group_type='site'
      ),
      'site_chats_archived', (
        select count(*) from public.communication_groups
        where group_type='site' and archived_at is not null
      )
    )
  else null end;
$$;

revoke all on function public.get_master_operations_snapshot()
  from public,anon;
grant execute on function public.get_master_operations_snapshot()
  to authenticated;
