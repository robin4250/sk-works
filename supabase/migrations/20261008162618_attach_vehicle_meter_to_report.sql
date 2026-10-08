-- Depends on staged vehicle claims and immutable meter events; rollout stays OFF.
alter table public.daily_report_workers
  add column vehicle_meter_event_id uuid references public.vehicle_meter_events(id),
  add column vehicle_meter_source_clock_in_id uuid,
  add column previous_odometer_km numeric(12,1),
  add column trip_distance_km numeric(12,1);

-- The existing draft RPC replaces worker rows. Keep attachment identity outside
-- those rows so a re-save cannot replace one committed event with another.
create table private.vehicle_meter_report_links (
  report_id uuid not null references public.daily_reports(id) on delete cascade,
  worker_id uuid not null,
  source_clock_in_id uuid not null,
  event_id uuid not null references public.vehicle_meter_events(id),
  primary key(report_id,worker_id)
);
revoke all on private.vehicle_meter_report_links from public,anon,authenticated;

create function private.require_vehicle_meter_report_context(p_report_id uuid)
returns public.daily_reports language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_report public.daily_reports%rowtype;
begin
 if v_actor is null or not private.account_access_allowed() then raise exception 'report access denied' using errcode='42501'; end if;
 select * into v_report from public.daily_reports d where d.id=p_report_id for share;
 if not found or (v_report.created_by is distinct from v_actor and v_report.updated_by is distinct from v_actor)
   or not (
     (v_report.site_id is not null and v_report.route_assignment_id is null and exists(
       select 1 from public.sites s where s.id=v_report.site_id and s.company_id=v_report.company_id))
     or (v_report.site_id is null and v_report.route_assignment_id is not null and exists(
       select 1 from public.route_assignments r where r.id=v_report.route_assignment_id and r.company_id=v_report.company_id))
   )
   or not exists(select 1 from public.company_members m where m.company_id=v_report.company_id and m.user_id=v_actor)
   or not exists(
     select 1 from public.workers w
     join public.daily_report_workers rw on rw.worker_id=w.id and rw.report_id=v_report.id
     join public.attendance_verifications a on a.worker_id=w.id and a.company_id=w.company_id
       and a.event_type='clock_in' and a.work_date=v_report.report_date
       and a.site_id is not distinct from v_report.site_id
       and a.route_assignment_id is not distinct from v_report.route_assignment_id
     where w.company_id=v_report.company_id and w.user_id=v_actor and w.status='active'
   ) then raise exception 'report author must be an actual shift participant' using errcode='42501'; end if;
 perform 1 from private.vehicle_usage_rollout r where r.company_id=v_report.company_id and r.enabled for share;
 if not found then raise exception 'vehicle report linkage is disabled' using errcode='42501'; end if;
 return v_report;
end $$;
revoke all on function private.require_vehicle_meter_report_context(uuid) from public,anon,authenticated;

create function public.get_report_vehicle_meter_context(p_report_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_report public.daily_reports%rowtype; result jsonb;
begin
 v_report:=private.require_vehicle_meter_report_context(p_report_id);
 select coalesce(jsonb_agg(jsonb_build_object(
   'source_clock_in_id',a.id,'worker_id',a.worker_id,'vehicle_id',a.vehicle_id,
   'vehicle_name',v.display_name,'work_date',a.work_date,
   'has_claim',c.source_clock_in_id is not null,'has_event',e.id is not null,
   'event_id',e.id,'previous_km',e.previous_km,'current_km',e.current_km,
   'distance_km',e.distance_km,'baseline_decreased',e.baseline_decreased
 ) order by a.confirmed_at,a.id),'[]'::jsonb) into result
 from public.attendance_verifications a
 join public.daily_report_workers rw on rw.report_id=v_report.id and rw.worker_id=a.worker_id
 left join public.vehicle_usage_claims c on c.source_clock_in_id=a.id and c.company_id=a.company_id
   and c.driver_worker_id=a.worker_id and c.vehicle_id=a.vehicle_id and c.work_date=a.work_date
 left join public.vehicle_meter_events e on e.source_clock_in_id=a.id and c.ended_at is not null
   and e.company_id=a.company_id and e.driver_worker_id=a.worker_id and e.vehicle_id=a.vehicle_id and e.work_date=a.work_date
 left join public.vehicles v on v.id=a.vehicle_id and v.company_id=a.company_id
 where a.company_id=v_report.company_id and a.event_type='clock_in' and a.work_date=v_report.report_date
   and a.site_id is not distinct from v_report.site_id
   and a.route_assignment_id is not distinct from v_report.route_assignment_id and a.vehicle_id is not null;
 return result;
end $$;
revoke all on function public.get_report_vehicle_meter_context(uuid) from public,anon;
grant execute on function public.get_report_vehicle_meter_context(uuid) to authenticated;

create function public.attach_vehicle_meter_to_report(p_report_id uuid,p_source_clock_in_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_report public.daily_reports%rowtype;
 v_start public.attendance_verifications%rowtype;
 v_claim public.vehicle_usage_claims%rowtype;
 v_event public.vehicle_meter_events%rowtype;
 v_worker public.daily_report_workers%rowtype;
 v_link private.vehicle_meter_report_links%rowtype;
 result jsonb;
begin
 v_report:=private.require_vehicle_meter_report_context(p_report_id);
 select * into v_start from public.attendance_verifications a where a.id=p_source_clock_in_id;
 if not found or v_start.event_type<>'clock_in' or v_start.company_id<>v_report.company_id
   or v_start.work_date is distinct from v_report.report_date
   or v_start.site_id is distinct from v_report.site_id
   or v_start.route_assignment_id is distinct from v_report.route_assignment_id then
   raise exception 'vehicle source does not match report shift' using errcode='42501';
 end if;
 select * into v_worker from public.daily_report_workers rw
   where rw.report_id=v_report.id and rw.worker_id=v_start.worker_id for update;
 if not found then raise exception 'vehicle driver is not in report roster' using errcode='42501'; end if;
 select * into v_link from private.vehicle_meter_report_links l
   where l.report_id=v_report.id and l.worker_id=v_start.worker_id;
 if found and v_link.source_clock_in_id<>v_start.id then
   raise exception 'report already has a different vehicle meter source';
 end if;
 if v_start.vehicle_id is null then return jsonb_build_object('attached',false,'has_claim',false,'has_event',false,'worker_id',v_start.worker_id); end if;
 select * into v_claim from public.vehicle_usage_claims c where c.source_clock_in_id=v_start.id;
 if not found then return jsonb_build_object('attached',false,'has_claim',false,'has_event',false,'worker_id',v_start.worker_id); end if;
 if row(v_claim.company_id,v_claim.driver_worker_id,v_claim.vehicle_id,v_claim.work_date)
   is distinct from row(v_start.company_id,v_start.worker_id,v_start.vehicle_id,v_start.work_date) then
   raise exception 'vehicle claim snapshot mismatch';
 end if;
 select * into v_event from public.vehicle_meter_events e where e.source_clock_in_id=v_start.id;
 if not found then return jsonb_build_object('attached',false,'has_claim',true,'has_event',false,'worker_id',v_start.worker_id); end if;
 if v_claim.ended_at is null or row(v_event.company_id,v_event.driver_worker_id,v_event.vehicle_id,v_event.work_date)
   is distinct from row(v_start.company_id,v_start.worker_id,v_start.vehicle_id,v_start.work_date) then
   raise exception 'committed vehicle meter event does not match source';
 end if;
 if v_link.event_id is not null and v_link.event_id<>v_event.id then
   raise exception 'report already has a different vehicle meter event';
 end if;
 result:=jsonb_build_object('attached',true,'has_claim',true,'has_event',true,
   'event_id',v_event.id,'source_clock_in_id',v_start.id,'worker_id',v_start.worker_id,
   'vehicle_id',v_event.vehicle_id,'work_date',v_event.work_date,
   'previous_km',v_event.previous_km,'current_km',v_event.current_km,'distance_km',v_event.distance_km);
 if v_worker.vehicle_meter_event_id is not null then
   if row(v_worker.vehicle_meter_event_id,v_worker.vehicle_meter_source_clock_in_id,v_worker.vehicle_id,
     v_worker.route_assignment_id,v_worker.previous_odometer_km,v_worker.odometer_km,v_worker.trip_distance_km)
     is distinct from row(v_event.id,v_start.id,v_event.vehicle_id,v_start.route_assignment_id,
       v_event.previous_km,v_event.current_km,v_event.distance_km) then
     raise exception 'report already has a different vehicle meter snapshot';
   end if;
   -- Signed reports may retry this exact read-only attachment; never mutate.
   return result;
 end if;
 if v_report.status<>'draft' or v_report.signed_at is not null or v_report.signature_json is not null
   or v_report.representative_signature_json is not null or v_report.supervisor_signature_json is not null then
   raise exception 'signed report vehicle snapshot cannot be changed';
 end if;
 if (v_worker.vehicle_id is not null and v_worker.vehicle_id<>v_event.vehicle_id)
   or (v_worker.route_assignment_id is not null and v_worker.route_assignment_id is distinct from v_start.route_assignment_id) then
   raise exception 'existing report vehicle or route differs from source';
 end if;
 update public.daily_report_workers set vehicle_id=v_event.vehicle_id,
   route_assignment_id=v_start.route_assignment_id,odometer_km=v_event.current_km,
   vehicle_meter_event_id=v_event.id,vehicle_meter_source_clock_in_id=v_start.id,
   previous_odometer_km=v_event.previous_km,trip_distance_km=v_event.distance_km
 where report_id=v_report.id and worker_id=v_start.worker_id;
 insert into private.vehicle_meter_report_links(report_id,worker_id,source_clock_in_id,event_id)
   values(v_report.id,v_start.worker_id,v_start.id,v_event.id)
   on conflict(report_id,worker_id) do nothing;
 return result;
end $$;
revoke all on function public.attach_vehicle_meter_to_report(uuid,uuid) from public,anon;
grant execute on function public.attach_vehicle_meter_to_report(uuid,uuid) to authenticated;

create function private.guard_linked_vehicle_meter_report()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 -- Only real staged claims in this report's saved roster participate. Do not
 -- infer vehicle usage from optional vehicle selections or legacy NULL rows.
 -- Validate every signature channel, including the first dual-signature write.
 if (NEW.status='signed' or NEW.signed_at is not null or NEW.signature_json is not null
   or NEW.representative_signature_json is not null or NEW.supervisor_signature_json is not null)
   and exists(select 1 from private.vehicle_usage_rollout r where r.company_id=NEW.company_id and r.enabled)
   and exists(
     select 1 from public.daily_report_workers w
     join public.attendance_verifications a on a.worker_id=w.worker_id
       and a.company_id=NEW.company_id and a.event_type='clock_in' and a.work_date=NEW.report_date
       and a.site_id is not distinct from NEW.site_id
       and a.route_assignment_id is not distinct from NEW.route_assignment_id
     join public.vehicle_usage_claims c on c.source_clock_in_id=a.id
       and c.company_id=a.company_id and c.driver_worker_id=a.worker_id
       and c.vehicle_id=a.vehicle_id and c.work_date=a.work_date
     left join public.vehicle_meter_events e on e.source_clock_in_id=c.source_clock_in_id
     left join private.vehicle_meter_report_links l on l.report_id=NEW.id and l.worker_id=w.worker_id
     where w.report_id=NEW.id and (
       c.ended_at is null or e.id is null
       or row(e.company_id,e.driver_worker_id,e.vehicle_id,e.work_date)
         is distinct from row(c.company_id,c.driver_worker_id,c.vehicle_id,c.work_date)
       or row(l.source_clock_in_id,l.event_id) is distinct from row(a.id,e.id)
       or row(w.vehicle_meter_event_id,w.vehicle_meter_source_clock_in_id,w.vehicle_id,
         w.route_assignment_id,w.previous_odometer_km,w.odometer_km,w.trip_distance_km)
         is distinct from row(e.id,a.id,e.vehicle_id,a.route_assignment_id,e.previous_km,e.current_km,e.distance_km)
     )
   ) then raise exception 'complete committed vehicle meter attachments before signing report'; end if;
 if exists(select 1 from private.vehicle_meter_report_links l where l.report_id=OLD.id) then
   if row(NEW.company_id,NEW.report_date,NEW.site_id,NEW.route_assignment_id)
     is distinct from row(OLD.company_id,OLD.report_date,OLD.site_id,OLD.route_assignment_id) then
     raise exception 'linked vehicle report identity cannot be changed';
   end if;
   if NEW.status='signed' or NEW.signed_at is not null or NEW.signature_json is not null
     or NEW.representative_signature_json is not null or NEW.supervisor_signature_json is not null then
     if exists(
       select 1 from private.vehicle_meter_report_links l
       join public.vehicle_meter_events e on e.id=l.event_id
       left join public.daily_report_workers w on w.report_id=l.report_id and w.worker_id=l.worker_id
       where l.report_id=OLD.id and (
         w.worker_id is null or row(w.vehicle_meter_event_id,w.vehicle_meter_source_clock_in_id,
           w.vehicle_id,w.previous_odometer_km,w.odometer_km,w.trip_distance_km)
           is distinct from row(e.id,l.source_clock_in_id,e.vehicle_id,e.previous_km,e.current_km,e.distance_km)
       )
     ) then raise exception 'restore committed vehicle snapshots before signing report'; end if;
   end if;
 end if;
 return NEW;
end $$;
revoke all on function private.guard_linked_vehicle_meter_report() from public,anon,authenticated;
create trigger linked_vehicle_meter_report_guard before update on public.daily_reports
  for each row execute function private.guard_linked_vehicle_meter_report();
