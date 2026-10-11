-- Preserve intermediate guards; close the final visit and clock-out in one transaction.
do $guard$
begin
 if to_regprocedure('private.route_journey_visit_before_clock_out()') is null or
  md5(pg_get_functiondef('private.route_journey_visit_before_clock_out()'::regprocedure)) <> '567a7aae68c20e161daa76c9ab7f9b67' then
  raise exception 'route clock-out guard definition changed; inspect before applying';
 end if;
end $guard$;
create or replace function private.route_journey_visit_before_clock_out() returns trigger language plpgsql set search_path='' security definer as $$
declare source public.attendance_verifications%rowtype;
 active private.route_journey_visit_events%rowtype; origin text; payload jsonb;
 ended timestamptz; started timestamptz;
begin
 if new.event_type='clock_out' and new.source_clock_in_id is not null then
  select * into source from public.attendance_verifications where id=new.source_clock_in_id;
  if source.route_assignment_id is null then return new; end if;
  if source.company_id is distinct from new.company_id or source.worker_id is distinct from new.worker_id or
     auth.uid() is null or not private.account_access_allowed() or
     not exists(select 1 from public.company_members where company_id=source.company_id and user_id=auth.uid()) or
     not (exists(select 1 from public.workers where id=source.worker_id and company_id=source.company_id and user_id=auth.uid()) or private.has_company_feature(source.company_id,'can_manage_attendance')) then
   raise exception 'route clock-out source not permitted' using errcode='42501';
  end if;
  perform 1 from public.companies where id=source.company_id for key share;
  select * into source from public.attendance_verifications where id=new.source_clock_in_id for update;
  if current_setting('transaction_isolation') <> 'read committed' then
   raise exception 'visit clock-out guard requires read committed';
  end if;
  select s.* into active from private.route_journey_visit_events s
   where s.source_clock_in_id=source.id and s.kind='start'
   and not exists(select 1 from private.route_journey_visit_events e where e.start_capture_id=s.capture_id and e.kind='end');
  if found then
   -- Intermediate visits still require explicit movement. The last visit ends
   -- atomically with clock-out; an insert failure rolls both records back.
   if exists(select 1 from public.route_stops rs where rs.route_assignment_id=source.route_assignment_id
    and not exists(select 1 from private.route_journey_visit_events v
     where v.source_clock_in_id=source.id and v.route_stop_id=rs.id and v.kind='start')) then
    raise exception 'finish current visit before clock-out';
   end if;
   select c.origin_kind, (c.payload->>'attempted_at')::timestamptz into origin,started
    from private.route_journey_captures c where c.id=active.capture_id;
   ended:=coalesce((to_jsonb(new)->>'attempted_at')::timestamptz,
                  (to_jsonb(new)->>'confirmed_at')::timestamptz,clock_timestamp());
   if not isfinite(ended) or ended<started then raise exception 'clock-out precedes final arrival'; end if;
   payload:=jsonb_build_object('capture_contract_version',1,'gps_capture_status','missing',
    'photo_capture_status','missing','gps_captured_at',null,'photo_captured_at',null,
    'photo_observed_at',null,'captured_address',null,'latitude',null,'longitude',null,
    'accuracy_m',null,'photo_storage_path',null,'attempted_at',ended);
   perform private.save_route_journey_visit(new.id,source.id,active.route_stop_id,origin,payload,'end',active.capture_id);
  end if;
 end if;
 return new;
end $$;
revoke all on function private.route_journey_visit_before_clock_out() from public,anon,authenticated;
