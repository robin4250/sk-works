-- Synthetic only. No migration or production retention policy is introduced.
-- Baseline proves the current gap before installing the experimental archive.
insert into public.companies values('10000000-0000-0000-0000-000000000001');
insert into public.company_members values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','admin');
insert into public.workers(id,company_id,status,user_id,name) values('10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','active','10000000-0000-0000-0000-000000000002','synthetic worker');
insert into public.sites(id,company_id,name) values('10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','synthetic site');
insert into private.attendance_capture_rollouts values('10000000-0000-0000-0000-000000000001',true);
select set_config('test.actor','10000000-0000-0000-0000-000000000002',false);

create temporary table retention_expected(id uuid primary key,evidence jsonb,report jsonb);
create function private.retention_fixture_seed(day date) returns uuid language plpgsql as $$
declare rid uuid; sid uuid; cid uuid := '10000000-0000-0000-0000-000000000001';
wid uuid := '10000000-0000-0000-0000-000000000003'; site uuid := '10000000-0000-0000-0000-000000000004';
begin
 insert into public.daily_reports(company_id,site_id,report_date,status,work_description) values(cid,site,day,'draft','original report') returning id into rid;
 insert into public.daily_report_workers(report_id,worker_id) values(rid,wid);
 insert into public.attendance_entries(company_id,worker_id,work_date,site_id,base_man_days,source_report_id) values(cid,wid,day,site,1,rid);
 insert into public.attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,proximity_status,daily_report_id,capture_contract_version,gps_capture_status,photo_capture_status,photo_storage_path,photo_observed_at,photo_captured_at)
 values(cid,wid,site,'clock_in','location_photo',(day::timestamp+interval '20 hours') at time zone 'Asia/Tokyo','not_checked',rid,1,'failed','uploaded','synthetic/'||day||'/in.jpg',(day::timestamp+interval '20 hours') at time zone 'Asia/Tokyo',(day::timestamp+interval '19 hours 59 minutes') at time zone 'Asia/Tokyo') returning id into sid;
 insert into public.attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,proximity_status,daily_report_id,source_clock_in_id,capture_contract_version,gps_capture_status,photo_capture_status,photo_observed_at)
 values(cid,wid,site,'clock_out','location_photo',((day+1)::timestamp+interval '5 hours') at time zone 'Asia/Tokyo','not_checked',rid,sid,1,'missing','upload_failed',((day+1)::timestamp+interval '5 hours') at time zone 'Asia/Tokyo');
 insert into retention_expected select a.id,to_jsonb(a),to_jsonb(d) from public.attendance_verifications a join public.daily_reports d on d.id=a.daily_report_id where d.id=rid;
 return rid;
end $$;

create function private.retention_fixture_manage(day date, mode text) returns void language plpgsql as $$
begin
 perform public.force_manage_attendance(case when mode='delete' then 'delete' else 'upsert' end,
 jsonb_build_array(jsonb_build_object('worker_id','10000000-0000-0000-0000-000000000003','site_id','10000000-0000-0000-0000-000000000004','date',day,'mode',case when mode='delete' then 'off' else mode end,'clock_in','08:00','clock_out','17:00','man_days',1)));
end $$;

do $$ declare mode text; day date := '2030-01-01'; rid uuid; begin
 foreach mode in array array['work','paid_leave','off','delete'] loop
  rid := private.retention_fixture_seed(day);
  perform private.retention_fixture_manage(day,mode);
  if exists(select 1 from public.attendance_verifications a join retention_expected e using(id) where (e.evidence->>'work_date')::date=day) then raise exception 'baseline unexpectedly retained original capture for %',mode; end if;
  if mode='work' and (select count(*) from public.attendance_verifications where work_date=day and verification_mode='manual')<>2 then raise exception 'work correction stopped functioning'; end if;
  if mode='paid_leave' and not exists(select 1 from public.paid_leave_requests where leave_date=day and status='approved') then raise exception 'paid leave stopped functioning'; end if;
  day:=day+1;
 end loop;
 rid := private.retention_fixture_seed(day);
 delete from public.daily_reports where id=rid;
 if (select count(*) from public.attendance_verifications where work_date=day and daily_report_id is null)<>2 then raise exception 'baseline report unlink path not reproduced'; end if;
end $$;

-- EXPERIMENTAL FIXTURE ONLY: first immutable capture snapshot without cascading
-- FKs. This establishes requirements; it does not decide company/account expiry.
create table private.retention_fixture_archive(id uuid primary key,evidence jsonb not null,report jsonb);
create function private.retention_fixture_archive_capture() returns trigger language plpgsql as $$
begin
 if OLD.capture_contract_version=1 then
  insert into private.retention_fixture_archive select OLD.id,to_jsonb(OLD),(select to_jsonb(d) from public.daily_reports d where d.id=OLD.daily_report_id) on conflict(id) do nothing;
 end if;
 return OLD;
end $$;
create trigger retention_fixture_capture_delete before delete on public.attendance_verifications for each row execute function private.retention_fixture_archive_capture();
create function private.retention_fixture_archive_report() returns trigger language plpgsql as $$
begin
 insert into private.retention_fixture_archive select a.id,to_jsonb(a),to_jsonb(OLD) from public.attendance_verifications a where a.daily_report_id=OLD.id and a.capture_contract_version=1 on conflict(id) do nothing;
 return OLD;
end $$;
create trigger retention_fixture_report_delete before delete on public.daily_reports for each row execute function private.retention_fixture_archive_report();

do $$ declare mode text; day date := '2030-02-01'; rid uuid; begin
 foreach mode in array array['work','paid_leave','off','delete','report_delete'] loop
  rid := private.retention_fixture_seed(day);
  if mode='report_delete' then delete from public.daily_reports where id=rid; else perform private.retention_fixture_manage(day,mode); end if;
  if (select count(*) from private.retention_fixture_archive a join retention_expected e using(id) where (e.evidence->>'work_date')::date=day and a.evidence=e.evidence and a.report=e.report)<>2 then raise exception 'original capture/report not preserved for %',mode; end if;
  if mode='work' and (select count(*) from public.attendance_verifications where work_date=day and verification_mode='manual')<>2 then raise exception 'archive blocked corrected shift'; end if;
  if mode='paid_leave' and not exists(select 1 from public.paid_leave_requests where leave_date=day and status='approved') then raise exception 'archive blocked paid leave'; end if;
  if mode='report_delete' then
   -- Repeated deletion must not overwrite original report identity with NULL.
   delete from public.attendance_verifications where work_date=day;
   if (select count(*) from private.retention_fixture_archive a join retention_expected e using(id) where (e.evidence->>'work_date')::date=day and a.evidence=e.evidence and a.report=e.report)<>2 then raise exception 'first original snapshot overwritten'; end if;
  end if;
  day:=day+1;
 end loop;
end $$;

create function private.retention_fixture_fail_archive() returns trigger language plpgsql as $$ begin raise exception 'synthetic archive unavailable'; end $$;
create trigger retention_fixture_archive_failure before insert on private.retention_fixture_archive for each row execute function private.retention_fixture_fail_archive();
do $$ declare rid uuid; begin
 rid:=private.retention_fixture_seed('2030-03-01');
 begin perform private.retention_fixture_manage('2030-03-01','paid_leave'); raise exception 'failure not propagated'; exception when raise_exception then if SQLERRM<>'synthetic archive unavailable' then raise; end if; end;
 if (select count(*) from public.attendance_verifications where work_date='2030-03-01' and capture_contract_version=1)<>2 or not exists(select 1 from public.daily_reports where id=rid) or exists(select 1 from public.paid_leave_requests where leave_date='2030-03-01') then raise exception 'failed archive partially committed management'; end if;
end $$;
drop trigger retention_fixture_archive_failure on private.retention_fixture_archive;

begin;
select private.retention_fixture_manage('2030-03-01','paid_leave');
rollback;
do $$ begin
 if (select count(*) from public.attendance_verifications where work_date='2030-03-01' and capture_contract_version=1)<>2 or exists(select 1 from private.retention_fixture_archive where (evidence->>'work_date')::date='2030-03-01') or exists(select 1 from public.paid_leave_requests where leave_date='2030-03-01') then raise exception 'rollback did not preserve original and discard archive/leave'; end if;
end $$;
