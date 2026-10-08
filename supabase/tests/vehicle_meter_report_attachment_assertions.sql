-- Isolated synthetic company: driver and non-driver report writer.
insert into companies values('10000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000001');
insert into company_members values
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','employee'),
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000012','employee'),
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000022','admin'),
 ('20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','employee');
insert into workers(id,company_id,status,user_id,name) values
 ('10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','active','10000000-0000-0000-0000-000000000002','driver'),
 ('10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000001','active','10000000-0000-0000-0000-000000000012','writer'),
 ('20000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','active','20000000-0000-0000-0000-000000000002','foreign');
insert into sites(id,company_id,name) values
 ('10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','fixture'),
 ('10000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001','different');
insert into vehicles(id,company_id,is_active,display_name) values
 ('10000000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000001',true,'fixture car');
insert into private.vehicle_usage_rollout values('10000000-0000-0000-0000-000000000001',true);
select set_config('test.actor','10000000-0000-0000-0000-000000000002',false);
set role authenticated;
insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at)
 values('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_in','2026-10-31 20:00+09');
insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at,source_clock_in_id)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_out','2026-11-01 05:00+09','10000000-0000-0000-0000-000000000041');
select public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000051',1100);
select set_config('test.actor','10000000-0000-0000-0000-000000000012',false);
insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at)
 values('10000000-0000-0000-0000-000000000042','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000004','clock_in','2026-10-31 20:00+09');
select set_config('test.report',public.save_daily_report_destination_draft(null,'10000000-0000-0000-0000-000000000004',null,'2026-10-31','fixture',
 '[{"worker_id":"10000000-0000-0000-0000-000000000003"},{"worker_id":"10000000-0000-0000-0000-000000000013"}]')::text,false);
do $$ declare context jsonb; result jsonb; begin
 if exists(select 1 from vehicle_meter_events) then raise exception 'other driver broad read accidentally allowed'; end if;
 context:=public.get_report_vehicle_meter_context(current_setting('test.report')::uuid);
 if jsonb_array_length(context)<>1 or context->0->>'event_id'<>'10000000-0000-0000-0000-000000000051'
   or context->0->>'work_date'<>'2026-10-31' or context->0->>'has_event'<>'true' then raise exception 'scoped other-driver readonly context missing'; end if;
 result:=public.attach_vehicle_meter_to_report(current_setting('test.report')::uuid,'10000000-0000-0000-0000-000000000041');
 if result->>'attached'<>'true' or result->>'distance_km'<>'100.0' then raise exception 'snapshot not attached'; end if;
 result:=public.attach_vehicle_meter_to_report(current_setting('test.report')::uuid,'10000000-0000-0000-0000-000000000041');
 if result->>'attached'<>'true' then raise exception 'retry failed'; end if;
 if not exists(select 1 from daily_report_workers where report_id=current_setting('test.report')::uuid
   and worker_id='10000000-0000-0000-0000-000000000003' and odometer_km=1100 and previous_odometer_km=1000
   and trip_distance_km=100 and vehicle_meter_event_id='10000000-0000-0000-0000-000000000051') then raise exception 'stored snapshot fields wrong'; end if;
 begin
  select * from private.vehicle_meter_report_links; raise exception 'private attachment ledger exposed';
 exception when insufficient_privilege then null; end;
end $$;
-- Actual existing draft RPC deletes/recreates workers: preserve event identity
-- outside those rows, restore the same immutable snapshot on the next attach.
select public.save_daily_report_destination_draft(current_setting('test.report')::uuid,'10000000-0000-0000-0000-000000000004',null,'2026-10-31','resave',
 '[{"worker_id":"10000000-0000-0000-0000-000000000003"},{"worker_id":"10000000-0000-0000-0000-000000000013"}]');
reset role;

do $$ begin
 begin
  update daily_reports set status='signed',signature_json='{}' where id=current_setting('test.report')::uuid;
  raise exception 'signed report with lost snapshots';
 exception when raise_exception then if sqlerrm<>'complete committed vehicle meter attachments before signing report' then raise; end if; end;
end $$;
set role authenticated;
select public.attach_vehicle_meter_to_report(current_setting('test.report')::uuid,'10000000-0000-0000-0000-000000000041');
reset role;
update daily_reports set status='signed',signature_json='{}',signed_at='2026-11-01 05:10+09' where id=current_setting('test.report')::uuid;
set role authenticated;
-- Signed retry is exact and read-only; signatures never cleared.
select public.attach_vehicle_meter_to_report(current_setting('test.report')::uuid,'10000000-0000-0000-0000-000000000041');
reset role;
do $$ begin
 if not exists(select 1 from daily_reports where id=current_setting('test.report')::uuid and status='signed'
   and signature_json='{}'::jsonb and signed_at='2026-11-01 05:10+09') then raise exception 'attachment altered signatures'; end if;
 if (select odometer_km from vehicles where id='10000000-0000-0000-0000-000000000007')<>1100 then raise exception 'attachment touched vehicle baseline'; end if;
 begin
  update daily_reports set report_date='2026-11-01' where id=current_setting('test.report')::uuid;
  raise exception 'linked report date changed';
 exception when raise_exception then if sqlerrm<>'linked vehicle report identity cannot be changed' then raise; end if; end;
end $$;
select set_config('test.actor','10000000-0000-0000-0000-000000000022',false);
set role authenticated;
do $$ begin
 begin
  perform public.get_report_vehicle_meter_context(current_setting('test.report')::uuid);
  raise exception 'nonparticipant manager gained snapshot access';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
do $$ begin
 begin
  perform public.attach_vehicle_meter_to_report(current_setting('test.report')::uuid,'10000000-0000-0000-0000-000000000041');
  raise exception 'foreign company attached';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('test.actor','10000000-0000-0000-0000-000000000012',false);
select set_config('test.blocked','true',false);
do $$ begin
 begin
  perform public.get_report_vehicle_meter_context(current_setting('test.report')::uuid);
  raise exception 'blocked author accessed snapshots';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('test.blocked','false',false);
reset role;

-- A new day's uncommitted claim remains pending without writing any snapshot.
select set_config('test.actor','10000000-0000-0000-0000-000000000002',false);
set role authenticated;
insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at)
 values('10000000-0000-0000-0000-000000000043','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_in','2026-11-01 08:00+09');
insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at,source_clock_in_id)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_out','2026-11-01 17:00+09','10000000-0000-0000-0000-000000000043');
select set_config('test.actor','10000000-0000-0000-0000-000000000012',false);
insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at)
 values('10000000-0000-0000-0000-000000000044','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000004','clock_in','2026-11-01 08:00+09');
select set_config('test.report_next',public.save_daily_report_destination_draft(null,'10000000-0000-0000-0000-000000000004',null,'2026-11-01','next day',
 '[{"worker_id":"10000000-0000-0000-0000-000000000003"},{"worker_id":"10000000-0000-0000-0000-000000000013"}]')::text,false);
do $$ declare value jsonb; begin
 value:=public.get_report_vehicle_meter_context(current_setting('test.report_next')::uuid);
 if value->0->>'has_claim'<>'true' or value->0->>'has_event'<>'false' then raise exception 'pending claim invented event'; end if;
 value:=public.attach_vehicle_meter_to_report(current_setting('test.report_next')::uuid,'10000000-0000-0000-0000-000000000043');
 if value->>'attached'<>'false' or value->>'has_claim'<>'true' or value->>'has_event'<>'false' then raise exception 'pending claim not distinguished'; end if;
 if exists(select 1 from daily_report_workers where report_id=current_setting('test.report_next')::uuid and vehicle_meter_event_id is not null)
 then raise exception 'pending claim wrote snapshot'; end if;
 begin
  perform public.attach_vehicle_meter_to_report(current_setting('test.report_next')::uuid,'10000000-0000-0000-0000-000000000041');
  raise exception 'wrong month source attached';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
-- Pending real claim: no signature API or individual signature column bypass.
do $$ begin
 begin
  update daily_reports set status='signed' where id=current_setting('test.report_next')::uuid;
  raise exception 'pending vehicle signature accepted';
 exception when raise_exception then if sqlerrm<>'complete committed vehicle meter attachments before signing report' then raise; end if; end;
 begin
  update daily_reports set signed_at=now() where id=current_setting('test.report_next')::uuid;
  raise exception 'pending vehicle signature accepted';
 exception when raise_exception then if sqlerrm<>'complete committed vehicle meter attachments before signing report' then raise; end if; end;
 begin
  update daily_reports set signature_json='{}' where id=current_setting('test.report_next')::uuid;
  raise exception 'pending vehicle signature accepted';
 exception when raise_exception then if sqlerrm<>'complete committed vehicle meter attachments before signing report' then raise; end if; end;
 begin
  update daily_reports set representative_signature_json='{}' where id=current_setting('test.report_next')::uuid;
  raise exception 'pending vehicle signature accepted';
 exception when raise_exception then if sqlerrm<>'complete committed vehicle meter attachments before signing report' then raise; end if; end;
 begin
  update daily_reports set supervisor_signature_json='{}' where id=current_setting('test.report_next')::uuid;
  raise exception 'pending vehicle signature accepted';
 exception when raise_exception then if sqlerrm<>'complete committed vehicle meter attachments before signing report' then raise; end if; end;
end $$;
set role authenticated;
select set_config('test.actor','10000000-0000-0000-0000-000000000002',false);
select public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000043','10000000-0000-0000-0000-000000000053',1200);
reset role;
-- A committed event alone does not bypass the missing report attachment.
do $$ begin
 begin
  update daily_reports set representative_signature_json='{}' where id=current_setting('test.report_next')::uuid;
  raise exception 'unattached committed event signature accepted';
 exception when raise_exception then if sqlerrm<>'complete committed vehicle meter attachments before signing report' then raise; end if; end;
end $$;
-- A pre-rollout signature is not silently cleared by attachment after enable.
update private.vehicle_usage_rollout set enabled=false;
update daily_reports set status='signed',signature_json='{}' where id=current_setting('test.report_next')::uuid;
update private.vehicle_usage_rollout set enabled=true;
select set_config('test.actor','10000000-0000-0000-0000-000000000012',false);
set role authenticated;
do $$ begin
 begin
  perform public.attach_vehicle_meter_to_report(current_setting('test.report_next')::uuid,'10000000-0000-0000-0000-000000000043');
  raise exception 'fresh signed attachment accepted';
 exception when raise_exception then if sqlerrm<>'signed report vehicle snapshot cannot be changed' then raise; end if; end;
end $$;
reset role;
update daily_reports set status='draft',signature_json=null where id=current_setting('test.report_next')::uuid;
set role authenticated;
select public.save_daily_report_destination_draft(current_setting('test.report_next')::uuid,'10000000-0000-0000-0000-000000000004',null,'2026-11-01','missing driver',
 '[{"worker_id":"10000000-0000-0000-0000-000000000013"}]');
do $$ begin
 begin
  perform public.attach_vehicle_meter_to_report(current_setting('test.report_next')::uuid,'10000000-0000-0000-0000-000000000043');
  raise exception 'driver absent from report roster accepted';
 exception when insufficient_privilege then null; end;
end $$;
select public.save_daily_report_destination_draft(current_setting('test.report_next')::uuid,'10000000-0000-0000-0000-000000000004',null,'2026-11-01','restore driver',
 '[{"worker_id":"10000000-0000-0000-0000-000000000003"},{"worker_id":"10000000-0000-0000-0000-000000000013"}]');
select public.attach_vehicle_meter_to_report(current_setting('test.report_next')::uuid,'10000000-0000-0000-0000-000000000043');
reset role;
-- Simulate a conflicting preexisting stored event; the RPC refuses overwrite.
update daily_report_workers set vehicle_meter_event_id='10000000-0000-0000-0000-000000000053'
 where report_id=current_setting('test.report')::uuid and worker_id='10000000-0000-0000-0000-000000000003';
set role authenticated;
do $$ begin
 begin
  perform public.attach_vehicle_meter_to_report(current_setting('test.report')::uuid,'10000000-0000-0000-0000-000000000041');
  raise exception 'different existing event overwritten';
 exception when raise_exception then if sqlerrm<>'report already has a different vehicle meter snapshot' then raise; end if; end;
end $$;
reset role;
update daily_report_workers set vehicle_meter_event_id='10000000-0000-0000-0000-000000000051'
 where report_id=current_setting('test.report')::uuid and worker_id='10000000-0000-0000-0000-000000000003';
-- Wrong site with a real same-company/day source is also rejected.
select set_config('test.actor','10000000-0000-0000-0000-000000000002',false);
set role authenticated;
insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at)
 values('10000000-0000-0000-0000-000000000045','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000007','clock_in','2026-11-01 18:00+09');
insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at,source_clock_in_id)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000007','clock_out','2026-11-01 20:00+09','10000000-0000-0000-0000-000000000045');
select public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000045','10000000-0000-0000-0000-000000000055',1210);
select set_config('test.actor','10000000-0000-0000-0000-000000000012',false);
do $$ begin
 begin
  perform public.attach_vehicle_meter_to_report(current_setting('test.report_next')::uuid,'10000000-0000-0000-0000-000000000045');
  raise exception 'wrong site source attached';
 exception when insufficient_privilege then null; end;
end $$;
select public.attach_vehicle_meter_to_report(current_setting('test.report')::uuid,'10000000-0000-0000-0000-000000000041');
reset role;
do $$ begin
 if (select odometer_km from vehicles where id='10000000-0000-0000-0000-000000000007')<>1210 then raise exception 'old attachment retry rewound current meter'; end if;
 if has_function_privilege('anon','public.attach_vehicle_meter_to_report(uuid,uuid)','EXECUTE')
   or has_function_privilege('anon','public.get_report_vehicle_meter_context(uuid)','EXECUTE')
   or has_function_privilege('authenticated','private.require_vehicle_meter_report_context(uuid)','EXECUTE')
 then raise exception 'attachment RPC ACL exposed'; end if;
end $$;

-- Existing approved correction flow may reopen a signed report, but must
-- restore the original committed event rather than silently changing mileage.
select set_config('test.actor','10000000-0000-0000-0000-000000000012',false);
set role authenticated;
do $$ begin
 begin
  perform public.save_daily_report_destination_draft(current_setting('test.report')::uuid,'10000000-0000-0000-0000-000000000004',null,'2026-10-31','unapproved correction',
   '[{"worker_id":"10000000-0000-0000-0000-000000000003"},{"worker_id":"10000000-0000-0000-0000-000000000013"}]');
  raise exception 'signed draft reopened without approval';
 exception when raise_exception then if sqlerrm<>'signed report requires approved edit request' then raise; end if; end;
end $$;
reset role;
insert into daily_report_edit_requests(id,report_id,requested_by,status,created_at) values
 ('10000000-0000-0000-0000-000000000081',current_setting('test.report')::uuid,'10000000-0000-0000-0000-000000000012','approved',now());
set role authenticated;
select public.save_daily_report_destination_draft(current_setting('test.report')::uuid,'10000000-0000-0000-0000-000000000004',null,'2026-10-31','approved correction',
 '[{"worker_id":"10000000-0000-0000-0000-000000000003"},{"worker_id":"10000000-0000-0000-0000-000000000013"}]');
select public.attach_vehicle_meter_to_report(current_setting('test.report')::uuid,'10000000-0000-0000-0000-000000000041');
reset role;
do $$ begin
 if not exists(select 1 from daily_report_edit_requests where id='10000000-0000-0000-0000-000000000081' and status='used')
 or not exists(select 1 from daily_report_workers where report_id=current_setting('test.report')::uuid
   and worker_id='10000000-0000-0000-0000-000000000003' and vehicle_meter_event_id='10000000-0000-0000-0000-000000000051'
   and previous_odometer_km=1000 and odometer_km=1100 and trip_distance_km=100)
 then raise exception 'approved correction failed to preserve committed snapshot'; end if;
 if (select odometer_km from vehicles where id='10000000-0000-0000-0000-000000000007')<>1210
 then raise exception 'approved correction rewound live vehicle baseline'; end if;
end $$;
