-- Synthetic fixture: default OFF, missing evidence, preserved overnight source,
-- immutable captured metadata, foreign worker and account access rejection.
grant update on public.attendance_verifications to authenticated;
set role authenticated;
do $$ begin
 if (public.get_attendance_capture_capability('10000000-0000-0000-0000-000000000001')->>'capture_enabled')::boolean then raise exception 'default capability is ON'; end if;
 begin perform public.get_attendance_capture_capability('20000000-0000-0000-0000-000000000001'); raise exception 'foreign capability leaked'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ declare blocked boolean:=false; begin
 begin
 insert into public.attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,proximity_status,capture_contract_version,gps_capture_status,photo_capture_status)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','clock_in','location_photo','2028-10-31 20:00+09','not_checked',1,'failed','missing');
 exception when raise_exception then blocked:=true; end;
 if not blocked then raise exception 'OFF gate accepted capture'; end if;
end $$;
insert into private.attendance_capture_rollouts values('10000000-0000-0000-0000-000000000001',true);
set role authenticated;
do $$ declare start_id uuid; end_id uuid; begin
 insert into public.attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,proximity_status,capture_contract_version,gps_capture_status,photo_capture_status)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','clock_in','location_photo','2028-10-31 20:00+09','not_checked',1,'failed','missing') returning id into start_id;
 insert into public.attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,proximity_status,capture_contract_version,gps_capture_status,photo_capture_status,source_clock_in_id,photo_observed_at)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','clock_out','location_photo','2028-11-01 05:00+09','not_checked',1,'missing','upload_failed',start_id,'2028-11-01 04:59+09') returning id into end_id;
 if not exists(select 1 from public.attendance_verifications where id=end_id and work_date='2028-10-31' and verification_mode='location_photo' and photo_capture_status='upload_failed') then raise exception 'capture lost source/month or requested mode'; end if;
 begin
 insert into public.attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,proximity_status,capture_contract_version,gps_capture_status,photo_capture_status)
 values('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','clock_in','location_photo',now(),'not_checked',1,'failed','missing');
 raise exception 'foreign worker accepted'; exception when insufficient_privilege then null; end;
 begin
 insert into public.attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,proximity_status,gps_capture_status,photo_capture_status)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','clock_in','location_photo',now(),'not_checked','failed','missing');
 raise exception 'NULL version bypass'; exception when check_violation then null; end;
end $$;
reset role;
insert into public.daily_reports(id,company_id,site_id,report_date) values('80000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000004','2028-11-02');
create policy fixture_capture_update on public.attendance_verifications for update to authenticated
 using (exists(select 1 from public.workers w where w.id=worker_id and w.user_id=auth.uid()))
 with check (exists(select 1 from public.workers w where w.id=worker_id and w.user_id=auth.uid()));
set role authenticated;
do $$ declare captured_id uuid; begin
 insert into public.attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,proximity_status,capture_contract_version,gps_capture_status,photo_capture_status,latitude,longitude,accuracy_m,gps_captured_at,photo_captured_at,photo_observed_at,captured_address,photo_storage_path)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','clock_in','location_photo','2028-11-02 08:00+09','near_site',1,'acquired','uploaded',35.0,139.0,5,'2028-11-02 07:59:58+09','2028-11-02 07:59:59+09','2028-11-02 08:00+09','fixture actual address','fixture/capture.jpg') returning id into captured_id;
 update public.attendance_verifications set daily_report_id='80000000-0000-0000-0000-000000000001' where id=captured_id;
 if not exists(select 1 from public.attendance_verifications where id=captured_id and daily_report_id='80000000-0000-0000-0000-000000000001' and captured_address='fixture actual address') then raise exception 'report linkage lost captured evidence'; end if;
 begin
 update public.attendance_verifications set captured_address='invented' where id=captured_id;
 raise exception 'captured address edit accepted'; exception when raise_exception then
 if SQLERRM<>'captured attendance evidence is immutable' then raise; end if; end;
 begin
 update public.attendance_verifications set capture_contract_version=null,gps_capture_status=null,photo_capture_status=null,gps_captured_at=null,photo_captured_at=null,photo_observed_at=null,captured_address=null where id=captured_id;
 raise exception 'capture contract erased'; exception when raise_exception then
 if SQLERRM<>'captured attendance evidence is immutable' then raise; end if; end;
 begin
 update public.attendance_verifications set photo_observed_at=photo_observed_at+interval '1 minute' where id=captured_id;
 raise exception 'observation time edit accepted'; exception when raise_exception then
 if SQLERRM<>'captured attendance evidence is immutable' then raise; end if; end;
 insert into public.attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,proximity_status,capture_contract_version,gps_capture_status,photo_capture_status,photo_observed_at,photo_storage_path)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','clock_in','location_photo','2028-11-03 08:00+09','not_checked',1,'missing','uploaded','2028-11-03 07:59:59+09','fixture/unknown-time.jpg');
 if not exists(select 1 from public.attendance_verifications where photo_storage_path='fixture/unknown-time.jpg' and photo_captured_at is null and photo_observed_at='2028-11-03 07:59:59+09') then raise exception 'unknown shutter time was fabricated'; end if;
 begin
 update public.attendance_verifications set confirmed_at=confirmed_at+interval '1 minute' where id=captured_id;
 raise exception 'real time edit accepted'; exception when raise_exception then
 if SQLERRM<>'attendance evidence chronology is immutable' then raise; end if; end;
 perform set_config('test.blocked','true',false);
 begin perform public.get_attendance_capture_capability('10000000-0000-0000-0000-000000000001'); raise exception 'blocked capability accepted'; exception when insufficient_privilege then null; end;
 begin
 insert into public.attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,proximity_status,capture_contract_version,gps_capture_status,photo_capture_status)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','clock_in','location_photo',now(),'not_checked',1,'failed','missing');
 raise exception 'blocked account accepted'; exception when insufficient_privilege then null; end;
 perform set_config('test.blocked','false',false);
end $$;
reset role;
