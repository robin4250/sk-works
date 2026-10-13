-- Synthetic fixture. No production queries, backfill or guessed associations.
insert into companies values('10000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000001');
insert into company_members values
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','employee'),
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000012','employee'),
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000022','admin'),
 ('20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','employee');
insert into workers(id,company_id,status,user_id,name) values
 ('10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','active','10000000-0000-0000-0000-000000000002','driver'),
 ('10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000001','active','10000000-0000-0000-0000-000000000012','second'),
 ('20000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','active','20000000-0000-0000-0000-000000000002','foreign');
insert into sites(id,company_id,name,latitude,longitude) values
 ('10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','fixture',35,139),
 ('20000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000001','foreign',35,139);
insert into vehicles values
 ('10000000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000001',true),
 ('10000000-0000-0000-0000-000000000008','10000000-0000-0000-0000-000000000001',false);

-- Off means unchanged legacy behavior, including rows lacking explicit source.
insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at)
 values('10000000-0000-0000-0000-000000000031','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_in','2026-10-01 08:00+09');
do $$ begin
 if exists(select 1 from vehicle_usage_claims) then raise exception 'rollout unexpectedly on'; end if;
 begin
  insert into private.vehicle_usage_rollout values('10000000-0000-0000-0000-000000000001',true);
  raise exception 'unresolved legacy start allowed activation';
 exception when raise_exception then if sqlerrm='unresolved legacy start allowed activation' then raise; end if; end;
end $$;
insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at,source_clock_in_id)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_out','2026-10-01 17:00+09','10000000-0000-0000-0000-000000000031');
insert into private.vehicle_usage_rollout values('10000000-0000-0000-0000-000000000001',true);
select set_config('test.actor','10000000-0000-0000-0000-000000000002',false);
set role authenticated;
insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at,work_date)
 values('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_in','2026-10-31 20:00+09','1999-01-01');
do $$ begin
 if not exists(select 1 from vehicle_usage_claims where source_clock_in_id='10000000-0000-0000-0000-000000000041'
   and driver_worker_id='10000000-0000-0000-0000-000000000003' and work_date='2026-10-31' and ended_at is null)
 then raise exception 'driver or canonical work date not captured'; end if;
 begin
  update vehicle_usage_claims set ended_at=now(); raise exception 'direct claim edit accepted';
 exception when insufficient_privilege then null; end;
 begin
  select * from private.vehicle_usage_rollout; raise exception 'rollout exposed';
 exception when insufficient_privilege then null; end;
end $$;
-- Same-company non-driver cannot see/steal active claim; insertion rolls back.
select set_config('test.actor','10000000-0000-0000-0000-000000000012',false);
do $$ begin
 if exists(select 1 from vehicle_usage_claims) then raise exception 'other driver read exposed'; end if;
 begin
  insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at)
   values('10000000-0000-0000-0000-000000000042','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_in','2026-11-01 00:01+09');
  raise exception 'second active driver accepted';
 exception when unique_violation then null; end;
 if exists(select 1 from attendance_verifications where id='10000000-0000-0000-0000-000000000042') then raise exception 'failed claim kept attendance'; end if;
end $$;
select set_config('test.actor','10000000-0000-0000-0000-000000000022',false);
do $$ begin
 if not exists(select 1 from vehicle_usage_claims) then raise exception 'existing manager cannot read claim'; end if;
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at)
   values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_in','2026-11-01 00:01+09');
  raise exception 'manager claimed other driver';
 exception when raise_exception then if sqlerrm='manager claimed other driver' then raise; end if; end;
end $$;
reset role;
do $$ begin
 begin
  update private.vehicle_usage_rollout set enabled=false; raise exception 'active rollout disabled';
 exception when raise_exception then if sqlerrm='active rollout disabled' then raise; end if; end;
end $$;
-- Existing attendance manager can explicitly close the driver, not impersonate
-- their clock in. The actual checkout timestamp determines release.
set role authenticated;
insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at,source_clock_in_id)
 values('10000000-0000-0000-0000-000000000043','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_out','2026-11-01 05:00+09','10000000-0000-0000-0000-000000000041');
do $$ begin
 if not exists(select 1 from vehicle_usage_claims where work_date='2026-10-31' and ended_at='2026-11-01 05:00+09' and source_clock_out_id='10000000-0000-0000-0000-000000000043')
 then raise exception 'overnight checkout did not release exact shift'; end if;
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at,source_clock_in_id)
   values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_out','2026-11-01 06:00+09','10000000-0000-0000-0000-000000000041');
  raise exception 'duplicate checkout accepted';
 exception when unique_violation then null; end;
end $$;
select set_config('test.actor','10000000-0000-0000-0000-000000000012',false);
insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at)
 values('10000000-0000-0000-0000-000000000044','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_in','2026-11-01 08:00+09');
select set_config('test.blocked','true',false);
do $$ begin
 if exists(select 1 from vehicle_usage_claims) then raise exception 'blocked user read claim'; end if;
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at,source_clock_in_id)
   values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_out','2026-11-01 17:00+09','10000000-0000-0000-0000-000000000044');
  raise exception 'blocked checkout accepted';
 exception when insufficient_privilege then null;
 when raise_exception then
  if sqlerrm <> 'clock out source is unavailable or inconsistent' then raise; end if;
 end;
end $$;
select set_config('test.blocked','false',false);
insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at,source_clock_in_id)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_out','2026-11-01 17:00+09','10000000-0000-0000-0000-000000000044');
reset role;
-- Actual existing auto-GPS RPC takes the vehicle snapshot and creates a claim.
insert into work_vehicle_route_selections values
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003',(now() at time zone 'Asia/Tokyo')::date,'10000000-0000-0000-0000-000000000007'),
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013',(now() at time zone 'Asia/Tokyo')::date,'10000000-0000-0000-0000-000000000007');
insert into gps_auto_attendance_schedules(company_id,worker_id,enabled,site_id,timezone,weekdays,local_time,radius_m) values
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003',true,'10000000-0000-0000-0000-000000000004','Asia/Tokyo',array[1,2,3,4,5,6,7]::smallint[],(now() at time zone 'Asia/Tokyo')::time,100),
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013',true,'10000000-0000-0000-0000-000000000004','Asia/Tokyo',array[1,2,3,4,5,6,7]::smallint[],(now() at time zone 'Asia/Tokyo')::time,100);
select set_config('test.actor','10000000-0000-0000-0000-000000000002',false);
set role authenticated;
do $$ declare result jsonb; begin
 result:=public.attempt_gps_auto_attendance(35,139,5);
 if result->>'status' <> 'clocked_in' then raise exception 'GPS start failed: %',result; end if;
 if not exists(select 1 from vehicle_usage_claims where ended_at is null and driver_worker_id='10000000-0000-0000-0000-000000000003'
   and work_date=(now() at time zone 'Asia/Tokyo')::date) then raise exception 'GPS omitted active vehicle claim'; end if;
end $$;
select set_config('test.actor','10000000-0000-0000-0000-000000000012',false);
do $$ begin
 begin
  perform public.attempt_gps_auto_attendance(35,139,5);
  raise exception 'second GPS driver accepted';
 exception when unique_violation then null; end;
 if exists(select 1 from attendance_verifications where worker_id='10000000-0000-0000-0000-000000000013'
   and work_date=(now() at time zone 'Asia/Tokyo')::date) then raise exception 'failed GPS saved evidence'; end if;
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at)
   values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000008','clock_in',now());
  raise exception 'inactive vehicle accepted';
 exception when raise_exception then if sqlerrm <> 'vehicle is unavailable' then raise; end if; end;
end $$;
select set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
do $$ begin
 if exists(select 1 from vehicle_usage_claims) then raise exception 'foreign company read exposed'; end if;
end $$;
reset role;
