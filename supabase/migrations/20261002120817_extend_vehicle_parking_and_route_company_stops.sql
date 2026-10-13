alter table public.vehicles
  add column if not exists parking_address text;

alter table public.route_stops
  add column if not exists source_kind text,
  add column if not exists source_id uuid,
  add column if not exists source_label text;

alter table public.route_stops
  drop constraint if exists route_stops_source_kind_check;

alter table public.route_stops
  add constraint route_stops_source_kind_check
  check (
    source_kind is null
    or source_kind in ('site','customer','partner','address')
  );
