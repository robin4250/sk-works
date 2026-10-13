alter table public.route_stops
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

alter table public.work_attendance_selections
  add column if not exists route_assignment_id uuid
    references public.route_assignments(id) on delete set null;

alter table public.gps_auto_attendance_schedules
  alter column site_id drop not null,
  add column if not exists route_assignment_id uuid
    references public.route_assignments(id) on delete set null;

alter table public.attendance_verifications
  alter column site_id drop not null;

alter table public.daily_reports
  alter column site_id drop not null,
  add column if not exists route_assignment_id uuid
    references public.route_assignments(id) on delete restrict;

alter table public.attendance_entries
  alter column site_id drop not null,
  add column if not exists route_assignment_id uuid
    references public.route_assignments(id) on delete restrict;

alter table public.work_attendance_selections
  drop constraint if exists work_attendance_selection_destination_check;
alter table public.work_attendance_selections
  add constraint work_attendance_selection_destination_check
  check (site_id is null or route_assignment_id is null);

alter table public.gps_auto_attendance_schedules
  drop constraint if exists gps_auto_attendance_destination_check;
alter table public.gps_auto_attendance_schedules
  add constraint gps_auto_attendance_destination_check
  check (
    (site_id is not null and route_assignment_id is null)
    or (site_id is null and route_assignment_id is not null)
  );

alter table public.daily_reports
  drop constraint if exists daily_reports_destination_check;
alter table public.daily_reports
  add constraint daily_reports_destination_check
  check (
    (site_id is not null and route_assignment_id is null)
    or (site_id is null and route_assignment_id is not null)
  );

alter table public.attendance_entries
  drop constraint if exists attendance_entries_destination_check;
alter table public.attendance_entries
  add constraint attendance_entries_destination_check
  check (
    (site_id is not null and route_assignment_id is null)
    or (site_id is null and route_assignment_id is not null)
  );

create index if not exists daily_reports_route_date_idx
  on public.daily_reports(company_id,route_assignment_id,report_date)
  where route_assignment_id is not null;

create index if not exists attendance_entries_route_date_idx
  on public.attendance_entries(company_id,route_assignment_id,work_date)
  where route_assignment_id is not null;
