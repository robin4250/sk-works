alter table public.member_feature_permissions
  add column if not exists can_manage_vehicles boolean not null default false,
  add column if not exists can_manage_routes boolean not null default false;

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  display_name text not null check (length(btrim(display_name)) between 1 and 120),
  registration_number text,
  vehicle_type text,
  capacity integer check (capacity is null or capacity > 0),
  notes text check (notes is null or length(notes) <= 2000),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.route_assignments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  service_date date not null,
  route_name text not null check (length(btrim(route_name)) between 1 and 120),
  vehicle_id uuid references public.vehicles(id) on delete restrict,
  site_id uuid references public.sites(id) on delete restrict,
  driver_user_id uuid references auth.users(id) on delete set null,
  notes text check (notes is null or length(notes) <= 2000),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.vehicles enable row level security;
alter table public.route_assignments enable row level security;

create index if not exists vehicles_company_active_idx
  on public.vehicles(company_id,is_active,display_name);
create index if not exists route_assignments_company_date_idx
  on public.route_assignments(company_id,service_date,is_active);
create index if not exists route_assignments_vehicle_idx
  on public.route_assignments(vehicle_id)
  where vehicle_id is not null;
create index if not exists route_assignments_site_idx
  on public.route_assignments(site_id)
  where site_id is not null;
create index if not exists route_assignments_driver_idx
  on public.route_assignments(driver_user_id)
  where driver_user_id is not null;

create or replace function private.can_manage_vehicle_routes(
  p_company_id uuid,
  p_kind text
)
returns boolean
language plpgsql
stable
security definer
set search_path='public','private','pg_temp'
as $$
declare
  uid uuid := auth.uid();
  role_name text;
begin
  if uid is null or p_company_id is null then return false; end if;

  select cm.role::text into role_name
  from public.company_members cm
  where cm.company_id=p_company_id and cm.user_id=uid
  limit 1;

  if role_name in ('owner','admin','manager') then return true; end if;
  if role_name is null then return false; end if;

  if p_kind='vehicle' then
    return exists(
      select 1 from public.member_feature_permissions p
      where p.company_id=p_company_id
        and p.user_id=uid
        and p.can_manage_vehicles=true
    );
  elsif p_kind='route' then
    return exists(
      select 1 from public.member_feature_permissions p
      where p.company_id=p_company_id
        and p.user_id=uid
        and p.can_manage_routes=true
    );
  end if;

  return false;
end;
$$;

revoke all on function private.can_manage_vehicle_routes(uuid,text)
  from public,anon,authenticated;

drop policy if exists "company members can view vehicles" on public.vehicles;
create policy "company members can view vehicles"
on public.vehicles for select
using (
  exists(
    select 1 from public.company_members cm
    where cm.company_id=vehicles.company_id
      and cm.user_id=(select auth.uid())
  )
);

drop policy if exists "authorized members can create vehicles" on public.vehicles;
create policy "authorized members can create vehicles"
on public.vehicles for insert
with check (
  private.can_manage_vehicle_routes(company_id,'vehicle')
  and created_by=(select auth.uid())
);

drop policy if exists "authorized members can update vehicles" on public.vehicles;
create policy "authorized members can update vehicles"
on public.vehicles for update
using (private.can_manage_vehicle_routes(company_id,'vehicle'))
with check (
  private.can_manage_vehicle_routes(company_id,'vehicle')
  and updated_by=(select auth.uid())
);

drop policy if exists "company members can view route assignments" on public.route_assignments;
create policy "company members can view route assignments"
on public.route_assignments for select
using (
  exists(
    select 1 from public.company_members cm
    where cm.company_id=route_assignments.company_id
      and cm.user_id=(select auth.uid())
  )
);

drop policy if exists "authorized members can create route assignments" on public.route_assignments;
create policy "authorized members can create route assignments"
on public.route_assignments for insert
with check (
  private.can_manage_vehicle_routes(company_id,'route')
  and created_by=(select auth.uid())
);

drop policy if exists "authorized members can update route assignments" on public.route_assignments;
create policy "authorized members can update route assignments"
on public.route_assignments for update
using (private.can_manage_vehicle_routes(company_id,'route'))
with check (
  private.can_manage_vehicle_routes(company_id,'route')
  and updated_by=(select auth.uid())
);

revoke delete on public.vehicles from anon,authenticated;
revoke delete on public.route_assignments from anon,authenticated;

grant select on public.vehicles to authenticated;
grant insert,update on public.vehicles to authenticated;
grant select on public.route_assignments to authenticated;
grant insert,update on public.route_assignments to authenticated;

create or replace function private.validate_route_assignment_company_scope()
returns trigger
language plpgsql
set search_path='public','private','pg_temp'
as $$
begin
  if new.vehicle_id is not null and not exists(
    select 1 from public.vehicles v
    where v.id=new.vehicle_id and v.company_id=new.company_id
  ) then
    raise exception 'vehicle must belong to the same company';
  end if;

  if new.site_id is not null and not exists(
    select 1 from public.sites s
    where s.id=new.site_id and s.company_id=new.company_id
  ) then
    raise exception 'site must belong to the same company';
  end if;

  if new.driver_user_id is not null and not exists(
    select 1 from public.company_members cm
    where cm.user_id=new.driver_user_id and cm.company_id=new.company_id
  ) then
    raise exception 'driver must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_route_assignment_company_scope
  on public.route_assignments;
create trigger validate_route_assignment_company_scope
before insert or update of company_id,vehicle_id,site_id,driver_user_id
on public.route_assignments
for each row execute function private.validate_route_assignment_company_scope();

create or replace function private.touch_vehicle_route_updated_at()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  new.updated_at=now();
  return new;
end;
$$;

drop trigger if exists touch_vehicle_updated_at on public.vehicles;
create trigger touch_vehicle_updated_at
before update on public.vehicles
for each row execute function private.touch_vehicle_route_updated_at();

drop trigger if exists touch_route_assignment_updated_at on public.route_assignments;
create trigger touch_route_assignment_updated_at
before update on public.route_assignments
for each row execute function private.touch_vehicle_route_updated_at();

create or replace function public.current_feature_permissions()
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_role text;
  v_perm public.member_feature_permissions%rowtype;
  v_is_approval_assignee boolean := false;
begin
  if v_user_id is null then return '{}'::jsonb; end if;

  select cm.company_id,cm.role::text into v_company_id,v_role
  from public.company_members cm
  where cm.user_id=v_user_id
  limit 1;

  if v_company_id is null then return '{}'::jsonb; end if;

  select exists(
    select 1 from public.company_approval_assignees caa
    where caa.company_id=v_company_id and caa.user_id=v_user_id
  ) into v_is_approval_assignee;

  if v_role in ('owner','admin') then
    return jsonb_build_object(
      'can_approve_daily_report_edits',v_is_approval_assignee,
      'can_manage_attendance',true,
      'can_manage_people',true,
      'can_view_invoices',true,
      'can_manage_invoices',true,
      'can_view_admin_site_data',true,
      'can_manage_admin_site_data',true,
      'can_manage_payroll',true,
      'can_manage_partner_chat',true,
      'can_manage_vehicles',true,
      'can_manage_routes',true
    );
  end if;

  select * into v_perm
  from public.member_feature_permissions
  where company_id=v_company_id and user_id=v_user_id;

  if found then
    return jsonb_build_object(
      'can_approve_daily_report_edits',v_is_approval_assignee,
      'can_manage_attendance',coalesce(v_perm.can_manage_attendance,false),
      'can_manage_people',coalesce(v_perm.can_manage_people,false),
      'can_view_invoices',coalesce(v_perm.can_view_invoices,false),
      'can_manage_invoices',coalesce(v_perm.can_manage_invoices,false),
      'can_view_admin_site_data',coalesce(v_perm.can_view_admin_site_data,false),
      'can_manage_admin_site_data',coalesce(v_perm.can_manage_admin_site_data,false),
      'can_manage_payroll',coalesce(v_perm.can_manage_payroll,false),
      'can_manage_partner_chat',coalesce(v_perm.can_manage_partner_chat,false),
      'can_manage_vehicles',coalesce(v_perm.can_manage_vehicles,false),
      'can_manage_routes',coalesce(v_perm.can_manage_routes,false)
    );
  end if;

  return jsonb_build_object(
    'can_approve_daily_report_edits',v_is_approval_assignee,
    'can_manage_attendance',v_role='manager',
    'can_manage_people',false,
    'can_view_invoices',false,
    'can_manage_invoices',false,
    'can_view_admin_site_data',false,
    'can_manage_admin_site_data',false,
    'can_manage_payroll',false,
    'can_manage_partner_chat',false,
    'can_manage_vehicles',v_role='manager',
    'can_manage_routes',v_role='manager'
  );
end;
$$;

create or replace function public.set_member_feature_permissions(
  p_user_id uuid,
  p_role text,
  p_permissions jsonb
)
returns void
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_target_role text;
  v_assignee_count integer;
  v_can_manage_attendance boolean;
  v_can_manage_people boolean;
  v_can_manage_partner_chat boolean;
  v_can_manage_vehicles boolean;
  v_can_manage_routes boolean;
begin
  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_actor and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  select cm.role::text into v_target_role
  from public.company_members cm
  where cm.company_id=v_company_id and cm.user_id=p_user_id
  limit 1;

  if v_target_role is null then raise exception 'target user is not in company'; end if;
  if v_target_role='owner' then raise exception 'owner role cannot be changed'; end if;
  if p_role not in ('admin','manager','viewer') then raise exception 'invalid role'; end if;

  if p_role='viewer' and exists(
    select 1 from public.company_approval_assignees
    where company_id=v_company_id and user_id=p_user_id
  ) then
    select count(*) into v_assignee_count
    from public.company_approval_assignees
    where company_id=v_company_id;
    if v_assignee_count<=1 then
      raise exception 'remove approval duty after assigning another approver';
    end if;
    delete from public.company_approval_assignees
    where company_id=v_company_id and user_id=p_user_id;
  end if;

  update public.company_members
  set role=p_role
  where company_id=v_company_id and user_id=p_user_id;

  if p_role='admin' then
    delete from public.member_feature_permissions
    where company_id=v_company_id and user_id=p_user_id;
    return;
  end if;

  v_can_manage_attendance :=
    coalesce((p_permissions->>'can_manage_attendance')::boolean,false);
  v_can_manage_people :=
    coalesce((p_permissions->>'can_manage_people')::boolean,false);
  v_can_manage_partner_chat :=
    coalesce((p_permissions->>'can_manage_partner_chat')::boolean,false);
  v_can_manage_vehicles :=
    coalesce((p_permissions->>'can_manage_vehicles')::boolean,false);
  v_can_manage_routes :=
    coalesce((p_permissions->>'can_manage_routes')::boolean,false);

  insert into public.member_feature_permissions(
    company_id,user_id,
    can_approve_daily_report_edits,
    can_manage_attendance,
    can_manage_people,
    can_view_invoices,
    can_manage_invoices,
    can_view_admin_site_data,
    can_manage_admin_site_data,
    can_manage_payroll,
    can_manage_partner_chat,
    can_manage_vehicles,
    can_manage_routes,
    updated_by,updated_at
  ) values(
    v_company_id,p_user_id,
    false,
    v_can_manage_attendance,
    v_can_manage_people,
    false,false,false,false,false,
    v_can_manage_partner_chat,
    v_can_manage_vehicles,
    v_can_manage_routes,
    v_actor,now()
  )
  on conflict(company_id,user_id) do update
  set can_approve_daily_report_edits=false,
      can_manage_attendance=excluded.can_manage_attendance,
      can_manage_people=excluded.can_manage_people,
      can_view_invoices=false,
      can_manage_invoices=false,
      can_view_admin_site_data=false,
      can_manage_admin_site_data=false,
      can_manage_payroll=false,
      can_manage_partner_chat=excluded.can_manage_partner_chat,
      can_manage_vehicles=excluded.can_manage_vehicles,
      can_manage_routes=excluded.can_manage_routes,
      updated_by=v_actor,
      updated_at=now();
end;
$$;
