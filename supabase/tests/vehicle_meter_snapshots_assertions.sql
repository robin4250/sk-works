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
insert into vehicles(id,company_id,is_active) values
 ('10000000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000001',true),
 ('10000000-0000-0000-0000-000000000008','10000000-0000-0000-0000-000000000001',false);

insert into daily_reports(id,company_id,site_id,report_date,status) values
 ('10000000-0000-0000-0000-000000000030','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000004','2026-10-31','draft');
insert into daily_report_workers(report_id,worker_id) values
 ('10000000-0000-0000-0000-000000000030','10000000-0000-0000-0000-000000000003');
select set_config('test.actor','10000000-0000-0000-0000-000000000002',false);
set role authenticated;
-- Unchanged public signature and OFF semantics.
select public.save_daily_report_vehicle_usage('10000000-0000-0000-0000-000000000030',
 '10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000007',null,1010);
reset role;
do $$ begin
 if (select odometer_km from vehicles where id='10000000-0000-0000-0000-000000000007')<>1010
   or exists(select 1 from vehicle_meter_events) then raise exception 'OFF legacy behavior changed'; end if;
end $$;
insert into private.vehicle_usage_rollout values('10000000-0000-0000-0000-000000000001',true);
set role authenticated;
insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at)
 values('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_in','2026-10-31 20:00+09');
do $$ begin
 begin
  perform public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000051','NaN');
  raise exception 'nonfinite OCR value accepted';
 exception when raise_exception then if sqlerrm<>'メーター値と移動距離は0以上・小数1桁の数値を入力してください' then raise; end if; end;
 begin
  perform public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000051',1110.12);
  raise exception 'OCR value silently rounded';
 exception when raise_exception then if sqlerrm<>'メーター値と移動距離は0以上・小数1桁の数値を入力してください' then raise; end if; end;
 begin
  perform public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000051',1110);
  raise exception 'meter saved before checkout';
 exception when raise_exception then if sqlerrm<>'退勤後に最終メーターを登録してください' then raise; end if; end;
 begin
  perform public.save_daily_report_vehicle_usage('10000000-0000-0000-0000-000000000030',
   '10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000007',null,1110);
  raise exception 'old RPC bypassed meter snapshots';
 exception when raise_exception then if sqlerrm<>'車両メーターは運転手本人の登録画面から保存してください' then raise; end if; end;
end $$;
insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at,source_clock_in_id)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_out','2026-11-01 05:00+09','10000000-0000-0000-0000-000000000041');
select public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000051',1110);
do $$ begin
 if not exists(select 1 from vehicle_meter_events where previous_km=1010 and current_km=1110 and distance_km=100
   and work_date='2026-10-31' and not baseline_decreased) then raise exception 'immutable month-boundary delta missing'; end if;
 begin
  update vehicle_meter_events set current_km=900; raise exception 'event editable';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('test.actor','10000000-0000-0000-0000-000000000012',false);
do $$ begin
 if exists(select 1 from vehicle_meter_events) then raise exception 'other driver event exposed'; end if;
 begin
  perform public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000051',1110);
  raise exception 'other driver recorded meter';
 exception when raise_exception then if sqlerrm<>'車両の運転手本人だけがメーターを登録できます' then raise; end if; end;
end $$;
insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at)
 values('10000000-0000-0000-0000-000000000042','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_in','2026-11-01 08:00+09');
insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at,source_clock_in_id)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_out','2026-11-01 17:00+09','10000000-0000-0000-0000-000000000042');
do $$ begin
 begin
  perform public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000042','10000000-0000-0000-0000-000000000052',50);
  raise exception 'decrease inferred negative distance';
 exception when raise_exception then if sqlerrm<>'メーター数値が減っています。その日の移動距離を手入力してください' then raise; end if; end;
end $$;
select public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000042','10000000-0000-0000-0000-000000000052',50,20);
select public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000042','10000000-0000-0000-0000-000000000052',50,20);
do $$ begin
 if not exists(select 1 from vehicle_meter_events where previous_km=1110 and current_km=50 and distance_km=20 and baseline_decreased)
 then raise exception 'manual decreased snapshot missing'; end if;
 begin
  select * from private.vehicle_meter_notice_outbox; raise exception 'outbox exposed';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
 if (select odometer_km from vehicles where id='10000000-0000-0000-0000-000000000007')<>50 then raise exception 'new baseline not saved'; end if;
 if (select count(*) from private.vehicle_meter_notice_outbox)<>1 then raise exception 'warning duplicated or missing'; end if;
end $$;
select set_config('test.actor','10000000-0000-0000-0000-000000000002',false);
set role authenticated;
-- Old report resave returns the immutable event even after another driver.
select public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000051',1110);
do $$ begin
 begin
  perform public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000051',1200);
  raise exception 'old event changed';
 exception when raise_exception then if sqlerrm<>'登録済みのメーター変更は管理者へ修正を申請してください' then raise; end if; end;
 begin
  perform public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000053',1110);
  raise exception 'fresh operation bypassed report idempotency';
 exception when raise_exception then if sqlerrm<>'登録済みのメーター変更は管理者へ修正を申請してください' then raise; end if; end;
end $$;
insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at)
 values('10000000-0000-0000-0000-000000000043','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_in','2026-11-02 08:00+09');
insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at,source_clock_in_id)
 values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_out','2026-11-02 17:00+09','10000000-0000-0000-0000-000000000043');
select set_config('test.actor','10000000-0000-0000-0000-000000000012',false);
insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,confirmed_at)
 values('10000000-0000-0000-0000-000000000044','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007','clock_in','2026-11-03 08:00+09');
select set_config('test.actor','10000000-0000-0000-0000-000000000002',false);
do $$ begin
 begin
  perform public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000043','10000000-0000-0000-0000-000000000053',60);
  raise exception 'late old firstreading rewound later claim';
 exception when raise_exception then if sqlerrm<>'後続の車両利用または基準値変更があります。管理者へ修正を申請してください' then raise; end if; end;
end $$;
select set_config('test.actor','10000000-0000-0000-0000-000000000022',false);
do $$ begin
 if (select count(*) from vehicle_meter_events)<>2 then raise exception 'existing vehicle manager read unavailable'; end if;
 begin
  perform public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000044','10000000-0000-0000-0000-000000000054',60);
  raise exception 'manager recorded other driver meter';
 exception when raise_exception then if sqlerrm<>'車両の運転手本人だけがメーターを登録できます' then raise; end if; end;
end $$;
select set_config('test.blocked','true',false);
do $$ begin
 if exists(select 1 from vehicle_meter_events) then raise exception 'blocked manager read events'; end if;
 begin
  perform public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000044','10000000-0000-0000-0000-000000000054',60);
  raise exception 'blocked RPC accepted';
 exception when raise_exception then if sqlerrm<>'ログインが必要です' then raise; end if; end;
end $$;
select set_config('test.blocked','false',false);
reset role;
do $$ begin
 if (select odometer_km from vehicles where id='10000000-0000-0000-0000-000000000007')<>50 then raise exception 'old retry rewound current vehicle'; end if;
 if (select count(*) from vehicle_meter_events)<>2 then raise exception 'failed write leaked event'; end if;
 if (select count(*) from private.vehicle_meter_notice_outbox)<>1 then raise exception 'failed write leaked warning'; end if;
 if has_function_privilege('authenticated','private.record_vehicle_driver_meter(uuid,uuid,numeric,numeric)','EXECUTE')
   or has_function_privilege('authenticated','private.save_daily_report_vehicle_usage_before_meter_snapshots(uuid,uuid,uuid,uuid,numeric)','EXECUTE')
   or has_function_privilege('anon','public.record_vehicle_driver_meter(uuid,uuid,numeric,numeric)','EXECUTE') then raise exception 'private or anonymous RPC exposed'; end if;
end $$;
