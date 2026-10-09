-- Exact staged capture schema/raw trigger/link RPC only. Other journey APIs intentionally not installed.
-- Staged OFF. Separate immutable evidence: never invent attendance events.
create table private.route_journey_rollouts (
 company_id uuid primary key references public.companies(id) on delete cascade,
 enabled boolean not null default false
);
create table private.route_journey_captures (
 id uuid primary key, company_id uuid not null references public.companies(id) on delete cascade,
 source_clock_in_id uuid not null references public.attendance_verifications(id) on delete cascade,
 worker_id uuid not null references public.workers(id) on delete cascade,
 route_assignment_id uuid not null, route_stop_id uuid not null, stop_order integer not null,
 stop_label text not null, work_date date not null, origin_kind text not null check(origin_kind in ('company','direct')),
 created_by uuid not null, recorded_at timestamptz not null default clock_timestamp(),
 payload jsonb not null, daily_report_id uuid references public.daily_reports(id) on delete set null
);
create unique index route_journey_captures_photo on private.route_journey_captures((payload->>'photo_storage_path')) where payload->>'photo_storage_path' is not null;
create index route_journey_captures_source on private.route_journey_captures(source_clock_in_id,recorded_at);
alter table private.route_journey_rollouts enable row level security;
alter table private.route_journey_captures enable row level security;
revoke all on private.route_journey_rollouts,private.route_journey_captures from public,anon,authenticated;
create function private.route_journey_raw_immutable() returns trigger language plpgsql set search_path='' as $$
begin
 if (to_jsonb(new)-'daily_report_id') is distinct from (to_jsonb(old)-'daily_report_id') then
  raise exception 'route journey raw evidence immutable' using errcode='42501';
 end if;
 return new;
end $$;
create trigger route_journey_raw_immutable before update on private.route_journey_captures for each row execute function private.route_journey_raw_immutable();

create function private.link_route_journey_report(p_report_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare d public.daily_reports%rowtype; n integer;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into d from public.daily_reports where id=p_report_id for update;
 if not found or d.route_assignment_id is null or d.site_id is not null or d.updated_by is distinct from auth.uid() or d.status='signed' or not exists(select 1 from public.company_members where company_id=d.company_id and user_id=auth.uid()) then raise exception 'saved editable report author required' using errcode='42501'; end if;
 if not exists(select 1 from private.route_journey_rollouts r where r.company_id=d.company_id and r.enabled) then return 0; end if;
 update private.route_journey_captures c set daily_report_id=d.id where c.company_id=d.company_id and c.route_assignment_id=d.route_assignment_id and c.work_date=d.report_date and (c.daily_report_id is null or c.daily_report_id=d.id)
 and exists(select 1 from public.daily_report_workers rw where rw.report_id=d.id and rw.worker_id=c.worker_id)
 and exists(select 1 from public.attendance_verifications a where a.id=c.source_clock_in_id and a.daily_report_id=d.id);
 get diagnostics n=row_count; return n;
end $$;
create function public.link_route_journey_report(p_report_id uuid) returns integer language sql security invoker set search_path='' as $$select private.link_route_journey_report(p_report_id)$$;
