alter table public.route_stops
  drop constraint if exists route_stops_source_kind_check;

alter table public.route_stops
  add constraint route_stops_source_kind_check
  check (
    source_kind is null
    or source_kind in ('site','customer','partner','parking','address')
  );
