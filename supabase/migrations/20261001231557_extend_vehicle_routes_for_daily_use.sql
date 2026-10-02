alter table public.vehicles
  add column if not exists odometer_km numeric(12,1) not null default 0,
  add column if not exists registration_document_path text,
  add column if not exists compulsory_insurance_path text,
  add column if not exists voluntary_insurance_path text;

alter table public.vehicles
  drop constraint if exists vehicles_odometer_km_check;
alter table public.vehicles
  add constraint vehicles_odometer_km_check check (odometer_km >= 0);

alter table public.route_assignments
  alter column service_date drop not null;

create table if not exists public.route_stops (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  route_assignment_id uuid not null references public.route_assignments(id) on delete cascade,
  stop_order integer not null check (stop_order >= 0),
  site_id uuid references public.sites(id) on delete set null,
  address text,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(route_assignment_id, stop_order),
  check (site_id is not null or nullif(trim(address),'') is not null)
);

create index if not exists route_stops_route_order_idx
  on public.route_stops(route_assignment_id, stop_order);

alter table public.route_stops enable row level security;

drop policy if exists "company members can view route stops" on public.route_stops;
create policy "company members can view route stops"
on public.route_stops for select
using (
  exists(
    select 1 from public.company_members cm
    where cm.company_id=route_stops.company_id
      and cm.user_id=(select auth.uid())
  )
);

drop policy if exists "vehicle route managers can insert route stops" on public.route_stops;
create policy "vehicle route managers can insert route stops"
on public.route_stops for insert
with check (
  private.can_manage_vehicle_routes(company_id,'route')
  and exists(
    select 1 from public.route_assignments r
    where r.id=route_assignment_id
      and r.company_id=route_stops.company_id
  )
  and (
    site_id is null or exists(
      select 1 from public.sites s
      where s.id=route_stops.site_id
        and s.company_id=route_stops.company_id
    )
  )
);

drop policy if exists "vehicle route managers can update route stops" on public.route_stops;
create policy "vehicle route managers can update route stops"
on public.route_stops for update
using (private.can_manage_vehicle_routes(company_id,'route'))
with check (private.can_manage_vehicle_routes(company_id,'route'));

drop policy if exists "vehicle route managers can delete route stops" on public.route_stops;
create policy "vehicle route managers can delete route stops"
on public.route_stops for delete
using (private.can_manage_vehicle_routes(company_id,'route'));

grant select,insert,update,delete on public.route_stops to authenticated;

create table if not exists public.work_vehicle_route_selections (
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  work_date date not null,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  route_assignment_id uuid references public.route_assignments(id) on delete set null,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key(company_id,worker_id,work_date)
);

alter table public.work_vehicle_route_selections enable row level security;

drop policy if exists "worker can view own vehicle route selection" on public.work_vehicle_route_selections;
create policy "worker can view own vehicle route selection"
on public.work_vehicle_route_selections for select
using (
  exists(
    select 1 from public.workers w
    where w.id=work_vehicle_route_selections.worker_id
      and w.company_id=work_vehicle_route_selections.company_id
      and (
        w.user_id=(select auth.uid())
        or private.can_manage_vehicle_routes(w.company_id,'route')
      )
  )
);

drop policy if exists "worker can insert own vehicle route selection" on public.work_vehicle_route_selections;
create policy "worker can insert own vehicle route selection"
on public.work_vehicle_route_selections for insert
with check (
  exists(
    select 1 from public.workers w
    where w.id=work_vehicle_route_selections.worker_id
      and w.company_id=work_vehicle_route_selections.company_id
      and w.user_id=(select auth.uid())
  )
);

drop policy if exists "worker can update own vehicle route selection" on public.work_vehicle_route_selections;
create policy "worker can update own vehicle route selection"
on public.work_vehicle_route_selections for update
using (
  exists(
    select 1 from public.workers w
    where w.id=work_vehicle_route_selections.worker_id
      and w.company_id=work_vehicle_route_selections.company_id
      and w.user_id=(select auth.uid())
  )
)
with check (
  exists(
    select 1 from public.workers w
    where w.id=work_vehicle_route_selections.worker_id
      and w.company_id=work_vehicle_route_selections.company_id
      and w.user_id=(select auth.uid())
  )
);

grant select,insert,update on public.work_vehicle_route_selections to authenticated;

alter table public.attendance_verifications
  add column if not exists vehicle_id uuid references public.vehicles(id) on delete set null,
  add column if not exists route_assignment_id uuid references public.route_assignments(id) on delete set null;

alter table public.daily_report_workers
  add column if not exists vehicle_id uuid references public.vehicles(id) on delete set null,
  add column if not exists route_assignment_id uuid references public.route_assignments(id) on delete set null,
  add column if not exists odometer_km numeric(12,1);

alter table public.daily_report_workers
  drop constraint if exists daily_report_workers_odometer_km_check;
alter table public.daily_report_workers
  add constraint daily_report_workers_odometer_km_check
  check (odometer_km is null or odometer_km >= 0);

create or replace function private.validate_work_vehicle_route_selection()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if not exists(
    select 1 from public.workers w
    where w.id=new.worker_id and w.company_id=new.company_id
  ) then
    raise exception 'worker must belong to company';
  end if;

  if new.vehicle_id is not null and not exists(
    select 1 from public.vehicles v
    where v.id=new.vehicle_id
      and v.company_id=new.company_id
      and v.is_active=true
  ) then
    raise exception 'vehicle must belong to company and be active';
  end if;

  if new.route_assignment_id is not null and not exists(
    select 1 from public.route_assignments r
    where r.id=new.route_assignment_id
      and r.company_id=new.company_id
      and r.is_active=true
  ) then
    raise exception 'route must belong to company and be active';
  end if;

  new.updated_at=now();
  return new;
end
$$;

drop trigger if exists validate_work_vehicle_route_selection
  on public.work_vehicle_route_selections;
create trigger validate_work_vehicle_route_selection
before insert or update
on public.work_vehicle_route_selections
for each row execute function private.validate_work_vehicle_route_selection();

create or replace function private.touch_route_stop_updated_at()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  new.updated_at=now();
  return new;
end
$$;

drop trigger if exists touch_route_stop_updated_at on public.route_stops;
create trigger touch_route_stop_updated_at
before update on public.route_stops
for each row execute function private.touch_route_stop_updated_at();
