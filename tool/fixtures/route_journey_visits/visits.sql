-- Candidate only: requires the existing capture migration; no production ON.
-- Raw capture payloads/bucket policies are unchanged. Events are derived links.
create table private.route_journey_visit_events (
 capture_id uuid primary key references private.route_journey_captures(id) on delete cascade,
 source_clock_in_id uuid not null,
 route_stop_id uuid not null,
 kind text not null check(kind in ('start','end')),
 start_capture_id uuid not null,
 check(kind<>'start' or start_capture_id=capture_id),
 check(kind<>'end' or start_capture_id<>capture_id)
);
create unique index route_journey_visit_end_once on private.route_journey_visit_events(start_capture_id) where kind='end';
create index route_journey_visit_source on private.route_journey_visit_events(source_clock_in_id);
alter table private.route_journey_visit_events enable row level security;
revoke all on private.route_journey_visit_events from public,anon,authenticated;

create function private.route_journey_visit_workspace(p_source_clock_in_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare ws jsonb; visits jsonb;
begin
 ws:=private.route_journey_workspace(p_source_clock_in_id);
 select coalesce(jsonb_agg(jsonb_build_object(
  'start_capture_id',s.capture_id,'route_stop_id',s.route_stop_id,
  'stop_label',c.stop_label,'work_date',c.work_date,
  'started_at',c.recorded_at,'ended_at',ec.recorded_at,
  'end_capture_id',e.capture_id) order by c.recorded_at,c.id),'[]'::jsonb)
 into visits from private.route_journey_visit_events s
 join private.route_journey_captures c on c.id=s.capture_id
 left join private.route_journey_visit_events e on e.start_capture_id=s.capture_id and e.kind='end'
 left join private.route_journey_captures ec on ec.id=e.capture_id
 where s.source_clock_in_id=p_source_clock_in_id and s.kind='start';
 return ws||jsonb_build_object('visit_contract_version',1,'visits',visits);
end $$;
create function public.route_journey_visit_workspace(p_source_clock_in_id uuid) returns jsonb
language sql security invoker set search_path='' as $$select private.route_journey_visit_workspace(p_source_clock_in_id)$$;

create function private.save_route_journey_visit(
 p_id uuid,p_source_clock_in_id uuid,p_route_stop_id uuid,p_origin_kind text,
 p_payload jsonb,p_kind text,p_start_capture_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare source public.attendance_verifications%rowtype; old private.route_journey_visit_events%rowtype;
 active private.route_journey_visit_events%rowtype; saved jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 if current_setting('transaction_isolation') <> 'read committed' then raise exception 'visit writes require read committed'; end if;
 if p_kind is null or p_kind not in ('start','end') or p_start_capture_id is null or
   (p_kind='start' and p_start_capture_id is distinct from p_id) or
   (p_kind='end' and p_start_capture_id=p_id) then raise exception 'invalid visit command'; end if;
 -- Scope validation first, even for retries. Lock order matches capture saves.
 perform private.route_journey_workspace(p_source_clock_in_id);
 select * into source from public.attendance_verifications where id=p_source_clock_in_id;
 perform 1 from public.companies where id=source.company_id for key share;
 select * into source from public.attendance_verifications where id=p_source_clock_in_id for update;
 if not found then raise exception 'route source not found'; end if;
 select * into old from private.route_journey_visit_events where capture_id=p_id;
 if found then
  if old.source_clock_in_id is distinct from p_source_clock_in_id or
     old.route_stop_id is distinct from p_route_stop_id or old.kind is distinct from p_kind or
     old.start_capture_id is distinct from p_start_capture_id then raise exception 'fixed visit command mismatch' using errcode='23505'; end if;
  -- Existing exact capture retry validates actor, origin and raw payload, even
  -- after clock-out/OFF. It does not produce another capture.
  saved:=private.save_route_journey_capture(p_id,p_source_clock_in_id,p_route_stop_id,p_origin_kind,p_payload);
  return saved||jsonb_build_object('visit_kind',old.kind,'start_capture_id',old.start_capture_id);
 end if;
 if exists(select 1 from private.route_journey_captures where id=p_id) then
  raise exception 'legacy capture cannot become a visit';
 end if;
 select s.* into active from private.route_journey_visit_events s
 where s.source_clock_in_id=p_source_clock_in_id and s.kind='start'
 and not exists(select 1 from private.route_journey_visit_events e where e.start_capture_id=s.capture_id and e.kind='end');
 if p_kind='start' and found then raise exception 'finish current visit first'; end if;
 if p_kind='end' and (not found or active.capture_id is distinct from p_start_capture_id or active.route_stop_id is distinct from p_route_stop_id) then
  raise exception 'selected open visit required';
 end if;
 -- OFF/open-shift/stop/capture checks remain in the original implementation.
 -- Its INSERT and this event INSERT share one transaction (all-or-nothing).
 saved:=private.save_route_journey_capture(p_id,p_source_clock_in_id,p_route_stop_id,p_origin_kind,p_payload);
 insert into private.route_journey_visit_events values(p_id,p_source_clock_in_id,p_route_stop_id,p_kind,p_start_capture_id);
 return saved||jsonb_build_object('visit_kind',p_kind,'start_capture_id',p_start_capture_id);
end $$;
create function public.save_route_journey_visit(p_id uuid,p_source_clock_in_id uuid,p_route_stop_id uuid,p_origin_kind text,p_payload jsonb,p_kind text,p_start_capture_id uuid) returns jsonb
language sql security invoker set search_path='' as $$select private.save_route_journey_visit(p_id,p_source_clock_in_id,p_route_stop_id,p_origin_kind,p_payload,p_kind,p_start_capture_id)$$;


create function private.route_journey_visit_exact(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare raw jsonb; event private.route_journey_visit_events%rowtype;
begin
 raw:=private.route_journey_capture_exact(p_id);
 if raw is null then return null; end if;
 select * into event from private.route_journey_visit_events where capture_id=p_id;
 if not found then return null; end if;
 return raw||jsonb_build_object('visit_kind',event.kind,'start_capture_id',event.start_capture_id);
end $$;
create function public.route_journey_visit_exact(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.route_journey_visit_exact(p_id)$$;
revoke all on function private.route_journey_visit_workspace(uuid),public.route_journey_visit_workspace(uuid),private.route_journey_visit_exact(uuid),public.route_journey_visit_exact(uuid),private.save_route_journey_visit(uuid,uuid,uuid,text,jsonb,text,uuid),public.save_route_journey_visit(uuid,uuid,uuid,text,jsonb,text,uuid) from public,anon;
grant execute on function private.route_journey_visit_workspace(uuid),public.route_journey_visit_workspace(uuid),private.route_journey_visit_exact(uuid),public.route_journey_visit_exact(uuid),private.save_route_journey_visit(uuid,uuid,uuid,text,jsonb,text,uuid),public.save_route_journey_visit(uuid,uuid,uuid,text,jsonb,text,uuid) to authenticated;

-- Do not silently close a visit when the shift is clocked out elsewhere.
create function private.route_journey_visit_before_clock_out() returns trigger language plpgsql set search_path='' security definer as $$
declare source public.attendance_verifications%rowtype;
begin
 if new.event_type='clock_out' and new.source_clock_in_id is not null then
  select * into source from public.attendance_verifications where id=new.source_clock_in_id for update;
  if source.route_assignment_id is null then return new; end if;
  if current_setting('transaction_isolation') <> 'read committed' then
   raise exception 'visit clock-out guard requires read committed';
  end if;
  if exists(select 1 from private.route_journey_visit_events s where s.source_clock_in_id=new.source_clock_in_id and s.kind='start'
   and not exists(select 1 from private.route_journey_visit_events e where e.start_capture_id=s.capture_id and e.kind='end')) then
   raise exception 'finish current visit before clock-out';
  end if;
 end if;
 return new;
end $$;
revoke all on function private.route_journey_visit_before_clock_out() from public,anon,authenticated;
create trigger route_journey_visit_before_clock_out before insert on public.attendance_verifications for each row execute function private.route_journey_visit_before_clock_out();
