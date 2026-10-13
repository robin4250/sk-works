-- Synthetic fixture only. No production rows or clocks are rewritten.
insert into company_members values
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','admin');
insert into workers(id,company_id,status,user_id,name) values
 ('10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','active','10000000-0000-0000-0000-000000000002','fixture');
insert into sites(id,company_id,name) values
 ('10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','fixture');
insert into vehicles(id,company_id,is_active) values
 ('10000000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000001',true),
 ('20000000-0000-0000-0000-000000000007','20000000-0000-0000-0000-000000000001',true);
insert into route_assignments values
 ('10000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001','fixture'),
 ('10000000-0000-0000-0000-000000000006','20000000-0000-0000-0000-000000000001','foreign');
insert into workers(id,company_id,status,user_id,name) values
 ('20000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','active','20000000-0000-0000-0000-000000000002','foreign');
-- Insert a genuinely legacy row before the new trigger for NULL fallback checks.
alter table attendance_verifications disable trigger attendance_shift_evidence_guard;
insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','clock_in','2026-09-01 08:00+09');
alter table attendance_verifications enable trigger attendance_shift_evidence_guard;
select set_config('test.actor','10000000-0000-0000-0000-000000000002',false);
set role authenticated;
do $$
declare
 cid uuid := '10000000-0000-0000-0000-000000000001';
 wid uuid := '10000000-0000-0000-0000-000000000003';
 sid uuid := '10000000-0000-0000-0000-000000000004';
 rid uuid := '10000000-0000-0000-0000-000000000005';
 start_id uuid; end_id uuid; c record; n integer;
begin
 for c in select * from (values
  ('2026-10-31 20:00+09','2026-11-01 05:00+09','2026-10-31'),
  ('2026-12-31 23:30+09','2027-01-01 05:00+09','2026-12-31'),
  ('2027-01-01 08:00+09','2027-01-01 17:00+09','2027-01-01')
 ) x(start_at,end_at,work_day) loop
  insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,work_date)
   values(cid,wid,sid,'clock_in',c.start_at::timestamptz,'1999-01-01') returning id into start_id;
  insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,work_date,source_clock_in_id)
   values(cid,wid,sid,'clock_out',c.end_at::timestamptz,'1999-01-01',start_id) returning id into end_id;
  if not exists(select 1 from attendance_verifications where id=end_id and work_date=c.work_day::date and confirmed_at=c.end_at::timestamptz)
   then raise exception 'canonical date changed actual end'; end if;
  begin
   insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id)
    values(cid,wid,sid,'clock_out',c.end_at::timestamptz,start_id);
   raise exception 'duplicate end accepted';
  exception when unique_violation then null; end;
  begin
   insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id)
    values(cid,wid,sid,'clock_out',c.start_at::timestamptz-interval '1 minute',start_id);
   raise exception 'earlier end accepted';
  exception when raise_exception then if sqlerrm='earlier end accepted' then raise; end if; end;
 end loop;
 insert into attendance_verifications(company_id,worker_id,route_assignment_id,event_type,confirmed_at)
  values(cid,wid,rid,'clock_in','2027-01-02 20:00+09') returning id into start_id;
 insert into attendance_verifications(company_id,worker_id,route_assignment_id,event_type,confirmed_at,source_clock_in_id,photo_storage_path)
  values(cid,wid,rid,'clock_out','2027-01-03 05:00+09',start_id,'synthetic/photo') returning id into end_id;
 if not exists(select 1 from attendance_verifications where id=end_id and work_date='2027-01-02') then raise exception 'route overnight lost'; end if;
 begin
  insert into attendance_verifications(company_id,worker_id,route_assignment_id,event_type,confirmed_at)
   values(cid,wid,'10000000-0000-0000-0000-000000000006','clock_in',now());
  raise exception 'foreign route accepted';
 exception when insufficient_privilege then null; end;
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,route_assignment_id,event_type,confirmed_at)
   values(cid,wid,sid,rid,'clock_in',now());
  raise exception 'dual destination accepted';
 exception when insufficient_privilege then null; end;
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id)
   values(cid,wid,sid,'clock_out','2027-01-03 06:00+09',start_id);
  raise exception 'destination mismatch accepted';
 exception when raise_exception then if sqlerrm='destination mismatch accepted' then raise; end if; end;
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at)
   values(cid,'20000000-0000-0000-0000-000000000003',sid,'clock_in',now());
  raise exception 'manager foreign worker accepted';
 exception when insufficient_privilege then null; end;
 -- Multiple starts remain explicitly selectable; a later start cannot change
 -- the caller's selected source. Legacy unassigned ends remain ambiguous.
 insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at)
  values(cid,wid,sid,'clock_in','2027-01-10 08:00+09') returning id into start_id;
 insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at)
  values(cid,wid,sid,'clock_in','2027-01-10 09:00+09');
 insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id)
  values(cid,wid,sid,'clock_out','2027-01-10 17:00+09',start_id);
 insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at)
  values(cid,wid,sid,'clock_in','2027-02-01 20:00+09') returning id into start_id;
 insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at)
  values(cid,wid,sid,'clock_out','2027-02-02 05:00+09');
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id)
   values(cid,wid,sid,'clock_out','2027-02-02 06:00+09',start_id);
  raise exception 'legacy closed source accepted';
 exception when raise_exception then if sqlerrm='legacy closed source accepted' then raise; end if; end;
 perform set_config('test.blocked','true',false);
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at)
   values(cid,wid,sid,'clock_in',now());
  raise exception 'blocked account accepted';
 exception when insufficient_privilege then null; end;
 perform set_config('test.blocked','false',false);
end $$;
reset role;
-- Real RPCs: old NULL fallback, next-day photo attachment, exact shift deletion,
-- neighboring current-day evidence retained, and original permission checks.
do $$
declare
 cid uuid := '10000000-0000-0000-0000-000000000001';
 wid uuid := '10000000-0000-0000-0000-000000000003';
 sid uuid := '10000000-0000-0000-0000-000000000004';
 rid uuid := '10000000-0000-0000-0000-000000000005';
 report uuid; start_id uuid; n integer;
begin
 if not exists(select 1 from daily_report_clocked_in_destinations('2026-09-01') where worker_id=wid) then raise exception 'old NULL date missing'; end if;
 select id into start_id from attendance_verifications where worker_id=wid and work_date is null and event_type='clock_in';
 insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id)
  values(cid,wid,sid,'clock_out','2026-09-01 17:00+09',start_id);
 insert into daily_reports(company_id,site_id,report_date) values(cid,sid,'2026-09-02') returning id into report;
 begin
  update attendance_verifications set daily_report_id=report where id=start_id;
  raise exception 'legacy parent date changed after closure';
 exception when raise_exception then if sqlerrm='legacy parent date changed after closure' then raise; end if; end;
 if not exists(select 1 from daily_report_clocked_in_destinations('2026-12-31') where worker_id=wid) then raise exception 'canonical destination missing'; end if;
 insert into daily_reports(company_id,route_assignment_id,report_date) values(cid,rid,'2027-01-02') returning id into report;
 n:=private.link_daily_report_attendance_evidence(report);
 if n<>1 or not exists(select 1 from attendance_verifications where photo_storage_path='synthetic/photo' and daily_report_id=report and work_date='2027-01-02') then raise exception 'next-day photo link failed'; end if;
 if exists(select 1 from attendance_verifications where event_type='clock_in' and daily_report_id=report) then raise exception 'nonphoto changed'; end if;
 -- Existing administrator RPC privilege context: no new direct UPDATE grants.
 begin
  update daily_reports set report_date=report_date+1 where id=report;
  raise exception 'canonical report date changed';
 exception when raise_exception then if sqlerrm='canonical report date changed' then raise; end if; end;
 begin
  update daily_reports set site_id=sid where id=report;
  raise exception 'canonical report site changed';
 exception when raise_exception then if sqlerrm='canonical report site changed' then raise; end if; end;
 begin
  update daily_reports set route_assignment_id=null where id=report;
  raise exception 'canonical report route changed';
 exception when raise_exception then if sqlerrm='canonical report route changed' then raise; end if; end;
 begin
  update daily_reports set company_id='20000000-0000-0000-0000-000000000001' where id=report;
  raise exception 'canonical report company changed';
 exception when raise_exception then if sqlerrm='canonical report company changed' then raise; end if; end;
 update daily_reports set work_description='synthetic updated comment',status='signed',signer_name='fixture',signature_json='{}' where id=report;
 if not exists(select 1 from daily_reports where id=report and work_description='synthetic updated comment' and status='signed' and signer_name='fixture') then raise exception 'report content edits blocked'; end if;
 select id into start_id from attendance_verifications where worker_id=wid and work_date='2026-12-31' and event_type='clock_in';
 begin
  update attendance_verifications set confirmed_at=confirmed_at+interval '1 minute' where id=start_id;
  raise exception 'source timestamp rewritten';
 exception when raise_exception then if sqlerrm='source timestamp rewritten' then raise; end if; end;
 begin
  update attendance_verifications set daily_report_id=report where id=start_id;
  raise exception 'wrong report accepted';
 exception when raise_exception then if sqlerrm='wrong report accepted' then raise; end if; end;
 perform force_manage_attendance('delete',jsonb_build_array(jsonb_build_object('worker_id',wid,'site_id',sid,'date','2026-12-31')));
 if exists(select 1 from attendance_verifications where worker_id=wid and work_date='2026-12-31') then raise exception 'shift pair not deleted'; end if;
 if (select count(*) from attendance_verifications where worker_id=wid and work_date='2027-01-01')<>2 then raise exception 'next day shift removed'; end if;
 if (select amount from payroll_history where id=1)<>123456 then raise exception 'financial history changed'; end if;
end $$;

-- Yesterday's explicit overnight end must not block a new GPS shift today.
delete from public.attendance_verifications where company_id='10000000-0000-0000-0000-000000000001';
update public.sites set latitude=35,longitude=139 where id='10000000-0000-0000-0000-000000000004';
do $$
declare
 cid uuid := '10000000-0000-0000-0000-000000000001';
 wid uuid := '10000000-0000-0000-0000-000000000003';
 sid uuid := '10000000-0000-0000-0000-000000000004';
 day date := (now() at time zone 'Asia/Tokyo')::date;
 start_id uuid; result jsonb;
begin
 insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at)
  values(cid,wid,sid,'clock_in',((day-1)::text||' 20:00')::timestamp at time zone 'Asia/Tokyo') returning id into start_id;
 insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id)
  values(cid,wid,sid,'clock_out',(day::text||' 05:00')::timestamp at time zone 'Asia/Tokyo',start_id);
 insert into gps_auto_attendance_schedules(company_id,worker_id,enabled,site_id,timezone,weekdays,local_time,radius_m)
  values(cid,wid,true,sid,'Asia/Tokyo',array[1,2,3,4,5,6,7]::smallint[],(now() at time zone 'Asia/Tokyo')::time,300);
 insert into work_vehicle_route_selections(company_id,worker_id,work_date,vehicle_id)
  values(cid,wid,day,'10000000-0000-0000-0000-000000000007');
 result:=private.attempt_gps_auto_attendance(35,139,5);
 if result->>'status'<>'clocked_in' then raise exception 'overnight end blocked GPS today: %',result; end if;
 if not exists(select 1 from attendance_verifications where id=(result->>'attendance_id')::uuid and work_date=day) then raise exception 'GPS work date absent'; end if;
 if not exists(select 1 from attendance_verifications where id=(result->>'attendance_id')::uuid and vehicle_id='10000000-0000-0000-0000-000000000007') then raise exception 'GPS vehicle snapshot absent'; end if;
 start_id:=(result->>'attendance_id')::uuid;
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id)
   values(cid,wid,sid,'clock_out',now()+interval '1 hour',start_id);
  raise exception 'clock out lost start vehicle';
 exception when raise_exception then if sqlerrm='clock out lost start vehicle' then raise; end if; end;
 begin
  update attendance_verifications set vehicle_id=null where id=start_id;
  raise exception 'start vehicle mutated';
 exception when raise_exception then if sqlerrm='start vehicle mutated' then raise; end if; end;
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,vehicle_id)
   values(cid,wid,sid,'clock_in',now(),'20000000-0000-0000-0000-000000000007');
  raise exception 'foreign vehicle accepted';
 exception when raise_exception then if sqlerrm='foreign vehicle accepted' then raise; end if; end;
 insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id,vehicle_id)
  values(cid,wid,sid,'clock_out',now()+interval '1 hour',start_id,'10000000-0000-0000-0000-000000000007');
 -- Existing deletion contract clears both snapshots without rewriting shift dates.
 delete from vehicles where id='10000000-0000-0000-0000-000000000007';
 if exists(select 1 from attendance_verifications where source_clock_in_id=start_id and vehicle_id is not null) then raise exception 'vehicle deletion FK changed'; end if;
 update gps_auto_attendance_schedules set last_attempt_date=null;
 result:=private.attempt_gps_auto_attendance(35,139,5);
 if result->>'status'<>'already_recorded' then raise exception 'GPS duplicate start allowed'; end if;
end $$;
-- Preserve editing behavior for reports containing only pre-migration evidence.
insert into daily_reports(id,company_id,site_id,report_date) values
 ('10000000-0000-0000-0000-000000000009','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000004','2025-01-01');
alter table attendance_verifications disable trigger attendance_shift_evidence_guard;
insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,daily_report_id)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','clock_in','2025-01-01 08:00+09','10000000-0000-0000-0000-000000000009');
alter table attendance_verifications enable trigger attendance_shift_evidence_guard;
update daily_reports set report_date='2025-01-02' where id='10000000-0000-0000-0000-000000000009';
do $$ begin
 if not exists(select 1 from daily_reports where id='10000000-0000-0000-0000-000000000009' and report_date='2025-01-02') then
  raise exception 'legacy-only report editing blocked'; end if;
 if exists(select 1 from attendance_verifications where daily_report_id='10000000-0000-0000-0000-000000000009' and work_date is not null) then
  raise exception 'legacy evidence backfilled'; end if;
end $$;
