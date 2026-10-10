-- Candidate implementation of PR838's original-row/actor/UUID requirements for
-- actual route captures and their visit links. No expiry or production rollout.
create table private.route_journey_visit_archive (
 id uuid primary key, company_id uuid not null, source_clock_in_id uuid not null,
 created_by uuid not null, raw_capture jsonb not null, visit_event jsonb,
 source_snapshot jsonb, report_snapshot jsonb,
 changed_by uuid, archived_at timestamptz not null default clock_timestamp()
);
alter table private.route_journey_visit_archive enable row level security;
revoke all on private.route_journey_visit_archive from public,anon,authenticated;
create index route_journey_visit_archive_source on private.route_journey_visit_archive(source_clock_in_id);
create function private.archive_route_journey_visit(p_id uuid,p_source jsonb default null,p_report jsonb default null) returns void
language sql security definer set search_path='' as $$
 insert into private.route_journey_visit_archive(id,company_id,source_clock_in_id,created_by,raw_capture,visit_event,source_snapshot,report_snapshot,changed_by)
 select c.id,c.company_id,c.source_clock_in_id,c.created_by,to_jsonb(c),to_jsonb(e),
 coalesce(p_source,(select to_jsonb(s) from public.attendance_verifications s where s.id=c.source_clock_in_id)),
 coalesce(p_report,(select to_jsonb(d) from public.daily_reports d where d.id=c.daily_report_id)),auth.uid()
 from private.route_journey_captures c left join private.route_journey_visit_events e on e.capture_id=c.id
 where c.id=p_id on conflict(id) do nothing
$$;
create function private.archive_route_journey_visit_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare capture record;
begin
 if tg_table_name='attendance_verifications' then
  for capture in select id from private.route_journey_captures where source_clock_in_id=old.id loop
   perform private.archive_route_journey_visit(capture.id,to_jsonb(old));
  end loop;
 elsif tg_table_name='daily_reports' then
  for capture in select id from private.route_journey_captures where daily_report_id=old.id loop
   perform private.archive_route_journey_visit(capture.id,null,to_jsonb(old));
  end loop;
 else
  perform private.archive_route_journey_visit(old.id);
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;
create trigger route_visit_archive_parent before delete on public.attendance_verifications for each row execute function private.archive_route_journey_visit_change();
create trigger route_visit_archive_report before delete on public.daily_reports for each row execute function private.archive_route_journey_visit_change();
create trigger route_visit_archive_capture before delete on private.route_journey_captures for each row execute function private.archive_route_journey_visit_change();
create trigger route_visit_archive_unlink before update of daily_report_id on private.route_journey_captures for each row when(old.daily_report_id is not null and old.daily_report_id is distinct from new.daily_report_id) execute function private.archive_route_journey_visit_change();

create function private.route_visit_reject_archived_id() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (tg_table_name='route_journey_captures' and exists(select 1 from private.route_journey_visit_archive where id=new.id)) or
    (tg_table_name='attendance_verifications' and exists(select 1 from private.route_journey_visit_archive where source_clock_in_id=new.id)) then
  raise exception 'archived route identity cannot be reused' using errcode='23505';
 end if;
 return new;
end $$;
create trigger route_visit_capture_tombstone before insert on private.route_journey_captures for each row execute function private.route_visit_reject_archived_id();
create trigger route_visit_source_tombstone before insert on public.attendance_verifications for each row execute function private.route_visit_reject_archived_id();

create function private.route_journey_archived_visit_exact(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare archived private.route_journey_visit_archive%rowtype;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into archived from private.route_journey_visit_archive a where a.id=p_id and a.created_by=auth.uid()
 and exists(select 1 from public.company_members where company_id=a.company_id and user_id=auth.uid());
 if not found or archived.visit_event is null then return null; end if;
 return archived.raw_capture||jsonb_build_object('visit_kind',archived.visit_event->>'kind',
  'start_capture_id',archived.visit_event->>'start_capture_id','archived',true);
end $$;
create or replace function private.route_journey_visit_exact(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare raw jsonb; event private.route_journey_visit_events%rowtype;
begin
 raw:=private.route_journey_capture_exact(p_id);
 if raw is null then return private.route_journey_archived_visit_exact(p_id); end if;
 select * into event from private.route_journey_visit_events where capture_id=p_id;
 if not found then return null; end if;
 return raw||jsonb_build_object('visit_kind',event.kind,'start_capture_id',event.start_capture_id);
end $$;
-- Keep the live implementation intact, including its authorization checks.
alter function private.route_journey_visit_workspace(uuid) rename to route_journey_live_visit_workspace;
create function private.route_journey_visit_workspace(p_source_clock_in_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare archived private.route_journey_visit_archive%rowtype;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 if exists(select 1 from public.attendance_verifications where id=p_source_clock_in_id) then
  return private.route_journey_live_visit_workspace(p_source_clock_in_id);
 end if;
 select * into archived from private.route_journey_visit_archive a where a.source_clock_in_id=p_source_clock_in_id and a.created_by=auth.uid()
 and exists(select 1 from public.company_members where company_id=a.company_id and user_id=auth.uid()) order by archived_at,id limit 1;
 if not found then raise exception 'actual personal route start required' using errcode='42501'; end if;
 return jsonb_build_object('version',1,'visit_contract_version',1,'enabled',false,'is_open',false,'archived',true,
  'source_clock_in_id',archived.source_clock_in_id,'company_id',archived.company_id,
  'worker_id',archived.raw_capture->>'worker_id','route_assignment_id',archived.raw_capture->>'route_assignment_id',
  'work_date',archived.raw_capture->>'work_date','origin_kind',archived.raw_capture->>'origin_kind','stops','[]'::jsonb,'visits','[]'::jsonb);
end $$;
-- Rebind public wrapper: SQL-language dependencies may otherwise keep the renamed OID.
create or replace function public.route_journey_visit_workspace(p_source_clock_in_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.route_journey_visit_workspace(p_source_clock_in_id)$$;
revoke all on function private.archive_route_journey_visit(uuid,jsonb,jsonb),private.archive_route_journey_visit_change(),private.route_visit_reject_archived_id(),private.route_journey_archived_visit_exact(uuid),private.route_journey_live_visit_workspace(uuid) from public,anon,authenticated;
revoke all on function private.route_journey_visit_workspace(uuid) from public,anon;
grant execute on function private.route_journey_visit_workspace(uuid) to authenticated;
-- A restrictive guard combines with existing owner/manager DELETE policies;
-- it grants no DELETE/SELECT rights and never touches photo bytes itself.
create function private.route_visit_photo_unreferenced(p_bucket text,p_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select case
 when p_bucket='attendance-route-evidence' then not exists(
  select 1 from private.route_journey_captures c where c.payload->>'photo_storage_path'=p_name
  union all select 1 from private.route_journey_visit_archive a where a.raw_capture->'payload'->>'photo_storage_path'=p_name)
 when p_bucket='attendance-evidence' then not exists(
  select 1 from public.attendance_verifications s where s.route_assignment_id is not null and to_jsonb(s)->>'photo_storage_path'=p_name
  union all select 1 from private.route_journey_visit_archive a where a.source_snapshot->>'photo_storage_path'=p_name)
 else true end
$$;
revoke all on function private.route_visit_photo_unreferenced(text,text) from public,anon;
grant execute on function private.route_visit_photo_unreferenced(text,text) to authenticated;
create policy route_visit_referenced_photo_delete_guard on storage.objects as restrictive for delete to authenticated
using(private.route_visit_photo_unreferenced(bucket_id,name));
create index route_visit_archive_photo_path on private.route_journey_visit_archive((raw_capture->'payload'->>'photo_storage_path')) where raw_capture->'payload'->>'photo_storage_path' is not null;
create index route_visit_archive_source_photo_path on private.route_journey_visit_archive((source_snapshot->>'photo_storage_path')) where source_snapshot->>'photo_storage_path' is not null;
create policy route_visit_referenced_photo_update_guard on storage.objects as restrictive for update to authenticated
using(private.route_visit_photo_unreferenced(bucket_id,name))
with check(private.route_visit_photo_unreferenced(bucket_id,name));
