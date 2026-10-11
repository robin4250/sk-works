-- Exact, read-only recovery of a removed route clock-in. Tombstones stay intact.
create function private.archived_attendance_capture_exact(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare snapshot jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then
  raise exception 'account unavailable' using errcode='42501';
 end if;
 if exists(select 1 from public.attendance_verifications where id=p_id) then return null; end if;
 select a.source_snapshot into snapshot from private.route_journey_visit_archive a
 where a.source_clock_in_id=p_id
 and a.source_snapshot->>'id'=p_id::text
 and a.source_snapshot->>'company_id'=a.company_id::text
 and a.source_snapshot->>'created_by'=auth.uid()::text
 and a.source_snapshot->>'event_type'='clock_in'
 and exists(select 1 from public.company_members m where m.company_id=a.company_id and m.user_id=auth.uid())
 order by a.archived_at,a.id limit 1;
 if snapshot is null then return null; end if;
 -- Conflicting archived versions must not release a pending local attempt.
 if exists(select 1 from private.route_journey_visit_archive a where a.source_clock_in_id=p_id
  and a.source_snapshot is distinct from snapshot) then return null; end if;
 return jsonb_build_object('version',1,'archived',true,'verification',snapshot);
end $$;
revoke all on function private.archived_attendance_capture_exact(uuid) from public,anon;
grant execute on function private.archived_attendance_capture_exact(uuid) to authenticated;
create function public.get_archived_attendance_capture(p_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
 select private.archived_attendance_capture_exact(p_id)
$$;
revoke all on function public.get_archived_attendance_capture(uuid) from public,anon;
grant execute on function public.get_archived_attendance_capture(uuid) to authenticated;
