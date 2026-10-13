create or replace function private.can_manage_vehicle_routes(
  p_company_id uuid,
  p_kind text
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1
    from public.company_members cm
    where cm.company_id=p_company_id
      and cm.user_id=auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
$$;

revoke all on function private.can_manage_vehicle_routes(uuid,text)
from public,anon,authenticated;

create or replace function public.company_member_vehicle_route_permission_rows()
returns table(
  user_id uuid,
  can_manage_vehicles boolean,
  can_manage_routes boolean
)
language sql
stable
security definer
set search_path=''
as $$
  with my_company as (
    select cm.company_id
    from public.company_members cm
    where cm.user_id=auth.uid()
      and cm.role::text in ('owner','admin')
    limit 1
  )
  select
    cm.user_id,
    cm.role::text in ('owner','admin','manager') as can_manage_vehicles,
    cm.role::text in ('owner','admin','manager') as can_manage_routes
  from public.company_members cm
  join my_company mc on mc.company_id=cm.company_id
$$;

revoke all on function public.company_member_vehicle_route_permission_rows()
from public,anon;
grant execute on function public.company_member_vehicle_route_permission_rows()
to authenticated;
