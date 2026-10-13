create or replace function public.company_member_vehicle_route_permission_rows()
returns table(
  user_id uuid,
  can_manage_vehicles boolean,
  can_manage_routes boolean
)
language sql
stable
security definer
set search_path='public','pg_temp'
as $$
  with my_company as (
    select cm.company_id
    from public.company_members cm
    where cm.user_id=(select auth.uid())
      and cm.role::text in ('owner','admin')
    limit 1
  )
  select
    cm.user_id,
    case
      when cm.role::text in ('owner','admin','manager') then true
      else coalesce(p.can_manage_vehicles,false)
    end as can_manage_vehicles,
    case
      when cm.role::text in ('owner','admin','manager') then true
      else coalesce(p.can_manage_routes,false)
    end as can_manage_routes
  from public.company_members cm
  join my_company mc on mc.company_id=cm.company_id
  left join public.member_feature_permissions p
    on p.company_id=cm.company_id
   and p.user_id=cm.user_id;
$$;

revoke all on function public.company_member_vehicle_route_permission_rows()
  from public,anon;
grant execute on function public.company_member_vehicle_route_permission_rows()
  to authenticated;
