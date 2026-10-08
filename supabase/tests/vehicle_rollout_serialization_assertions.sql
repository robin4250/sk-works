-- Snapshot-refresh contract: READ COMMITTED is required by the advisory protocol.
-- These single-session assertions do not replace the real two-connection tests.
begin isolation level repeatable read;
reset role;
select set_config('test.actor','10000000-0000-0000-0000-000000000002',false);
select set_config('test.blocked','false',false);
set local role authenticated;
do $$ begin
  begin
    insert into public.attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,verification_mode,confirmed_at,created_by)
    values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_in','manual',now(),auth.uid());
    raise exception 'repeatable-read vehicle INSERT was allowed';
  exception when raise_exception then
    if sqlerrm<>'vehicle attendance requires read committed isolation' then raise; end if;
  end;
  if to_regprocedure('public.record_vehicle_driver_meter(uuid,uuid,numeric,numeric)') is not null then
    begin
      perform public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000099',1001,null);
      raise exception 'repeatable-read meter was allowed';
    exception when raise_exception then
      if sqlerrm<>'vehicle meter registration requires read committed isolation' then raise; end if;
    end;
  end if;
end $$;
reset role;
do $$ begin
  begin
    update private.vehicle_usage_rollout set enabled=enabled;
    raise exception 'repeatable-read rollout was allowed';
  exception when raise_exception then
    if sqlerrm<>'vehicle rollout changes require read committed isolation' then raise; end if;
  end;
end $$;
rollback;
