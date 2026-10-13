select set_config('test.actor','30000000-0000-0000-0000-000000000002',false);
select set_config('test.blocked','false',false);
insert into companies values('30000000-0000-0000-0000-000000000001');
insert into company_members values('30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002','owner');
insert into workers(id,company_id,status,user_id,name) values('30000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000001','active','30000000-0000-0000-0000-000000000002','chain worker');
insert into route_assignments values('30000000-0000-0000-0000-000000000004','30000000-0000-0000-0000-000000000001','chain route');
insert into route_stops(id,route_assignment_id,stop_order,source_label) values('30000000-0000-0000-0000-000000000005','30000000-0000-0000-0000-000000000004',1,'chain stop');
do $$begin
 if (public.get_attendance_capture_capability('30000000-0000-0000-0000-000000000001')->>'capture_enabled')::boolean then raise exception 'new company enabled implicitly'; end if;
end $$;
insert into private.attendance_capture_rollouts values('30000000-0000-0000-0000-000000000001',true);
insert into private.route_journey_rollouts values('30000000-0000-0000-0000-000000000001',true);
set role authenticated;
insert into attendance_verifications(id,company_id,worker_id,route_assignment_id,event_type,verification_mode,confirmed_at,proximity_status,capture_contract_version,gps_capture_status,photo_capture_status)
values('30000000-0000-0000-0000-000000000006','30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000004','clock_in','location_photo',clock_timestamp(),'not_checked',1,'failed','missing');
do $$declare p jsonb:=jsonb_build_object('capture_contract_version',1,'gps_capture_status','failed','photo_capture_status','failed','attempted_at',clock_timestamp()); saved jsonb; begin
 saved:=public.save_route_journey_visit('30000000-0000-0000-0000-000000000007','30000000-0000-0000-0000-000000000006','30000000-0000-0000-0000-000000000005','company',p,'start','30000000-0000-0000-0000-000000000007');
 if saved->>'visit_kind'<>'start' then raise exception 'start not saved'; end if;
 begin
  insert into attendance_verifications(company_id,worker_id,route_assignment_id,event_type,source_clock_in_id,verification_mode,confirmed_at,proximity_status,capture_contract_version,gps_capture_status,photo_capture_status)
  values('30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000004','clock_out','30000000-0000-0000-0000-000000000006','location_photo',clock_timestamp(),'not_checked',1,'failed','missing');
  raise exception 'open visit allowed clock-out';
 exception when raise_exception then if sqlerrm<>'finish current visit before clock-out' then raise; end if; end;
 perform public.save_route_journey_visit('30000000-0000-0000-0000-000000000008','30000000-0000-0000-0000-000000000006','30000000-0000-0000-0000-000000000005','company',p,'end','30000000-0000-0000-0000-000000000007');
 if not (public.route_journey_visit_workspace('30000000-0000-0000-0000-000000000006')->>'is_open')::boolean then raise exception 'visit end closed shift'; end if;
end $$;
insert into attendance_verifications(company_id,worker_id,route_assignment_id,event_type,source_clock_in_id,verification_mode,confirmed_at,proximity_status,capture_contract_version,gps_capture_status,photo_capture_status)
values('30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000004','clock_out','30000000-0000-0000-0000-000000000006','location_photo',clock_timestamp(),'not_checked',1,'failed','missing');
reset role;
delete from attendance_verifications where company_id='30000000-0000-0000-0000-000000000001';
set role authenticated;
do $$begin
 if public.route_journey_visit_exact('30000000-0000-0000-0000-000000000007')->>'archived'<>'true' then raise exception 'actual source deletion lost visit'; end if;
end $$;
reset role;
