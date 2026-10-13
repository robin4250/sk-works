-- All ON gate rows below exist only in an isolated synthetic database.
set role authenticated;
do $$ declare r jsonb; begin
 r:=public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001');
 if r->>'group_checkout_enabled'<>'true' or r->>'vehicle_usage_enabled'<>'true'
    or r->>'vehicle_meter_enabled'<>'true' then raise exception 'actual ON contract mismatch: %',r; end if;
 if exists(select 1 from attendance_verifications) or exists(select 1 from vehicle_usage_claims)
    or exists(select 1 from vehicle_meter_events) then raise exception 'capability read mutated business records'; end if;
 begin perform 1 from private.group_checkout_rollout; raise exception 'actual private gate exposed'; exception when insufficient_privilege then null; end;
 begin perform public.get_attendance_rollout_capabilities('20000000-0000-0000-0000-000000000001'); raise exception 'foreign company capability exposed'; exception when insufficient_privilege then null; end;
end $$;
insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,verification_mode,confirmed_at,created_by)
values('10000000-0000-0000-0000-000000000051','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000021','10000000-0000-0000-0000-000000000031','10000000-0000-0000-0000-000000000041','clock_in','manual',now()-interval '1 hour',auth.uid());
do $$ declare candidates jsonb; result jsonb; begin
 candidates:=public.group_checkout_candidates('10000000-0000-0000-0000-000000000051');
 if jsonb_array_length(candidates)<>1 then raise exception 'actual roster contract unavailable'; end if;
 result:=public.commit_group_checkout('10000000-0000-0000-0000-000000000051',array['10000000-0000-0000-0000-000000000051'::uuid],'10000000-0000-0000-0000-000000000061');
 if jsonb_array_length(result)<>1 then raise exception 'actual scoped checkout unavailable'; end if;
 perform public.record_vehicle_driver_meter('10000000-0000-0000-0000-000000000051','10000000-0000-0000-0000-000000000071',1002.5,null);
 if not exists(select 1 from vehicle_usage_claims where source_clock_in_id='10000000-0000-0000-0000-000000000051' and ended_at is not null) then raise exception 'real vehicle claim not released'; end if;
 if (select count(*) from vehicle_meter_events)<>1 then raise exception 'real meter event missing'; end if;
end $$;
reset role;
-- Simulated successful report save, then the actual scoped attach RPC.
insert into daily_reports(id,company_id,site_id,report_date,status,created_by,updated_by)
select '10000000-0000-0000-0000-000000000081',company_id,site_id,work_date,'draft',auth.uid(),auth.uid()
from attendance_verifications where id='10000000-0000-0000-0000-000000000051';
insert into daily_report_workers(report_id,worker_id) values('10000000-0000-0000-0000-000000000081','10000000-0000-0000-0000-000000000021');
create temp table actual_evidence_before_attachment as select id,to_jsonb(a)-'daily_report_id' evidence from attendance_verifications a;
set role authenticated;
do $$ declare r jsonb; again jsonb; begin
 r:=public.attach_group_report_sources('10000000-0000-0000-0000-000000000081','10000000-0000-0000-0000-000000000051',array['10000000-0000-0000-0000-000000000051'::uuid]);
 again:=public.attach_group_report_sources('10000000-0000-0000-0000-000000000081','10000000-0000-0000-0000-000000000051',array['10000000-0000-0000-0000-000000000051'::uuid]);
 if r<>again or r->>'daily_report_id'<>'10000000-0000-0000-0000-000000000081' then raise exception 'actual report attachment result mismatch'; end if;
 r:=public.get_report_vehicle_meter_context('10000000-0000-0000-0000-000000000081');
 if jsonb_array_length(r)<>1 or r->0->>'event_id'<>'10000000-0000-0000-0000-000000000071' then raise exception 'actual vehicle report context mismatch'; end if;
 perform public.attach_vehicle_meter_to_report('10000000-0000-0000-0000-000000000081','10000000-0000-0000-0000-000000000051');
 perform public.attach_vehicle_meter_to_report('10000000-0000-0000-0000-000000000081','10000000-0000-0000-0000-000000000051');
 if not exists(select 1 from daily_report_workers where report_id='10000000-0000-0000-0000-000000000081'
   and vehicle_meter_event_id='10000000-0000-0000-0000-000000000071' and previous_odometer_km=1000 and odometer_km=1002.5 and trip_distance_km=2.5) then raise exception 'actual committed report meter snapshot mismatch'; end if;

end $$;
reset role;
do $$ begin
 if (select count(*) from attendance_verifications where daily_report_id='10000000-0000-0000-0000-000000000081')<>2 then raise exception 'actual group source/out not linked'; end if;
 if exists(select 1 from attendance_verifications a join actual_evidence_before_attachment b using(id) where to_jsonb(a)-'daily_report_id'<>b.evidence) then raise exception 'combined claim/meter/proxy original evidence changed'; end if;
end $$;
set role authenticated;
select set_config('test.blocked','true',false);
do $$ begin
 begin perform public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001'); raise exception 'blocked account read actual gates'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('test.blocked','false',false);
-- Complete closure permits the existing rollout guard to return to OFF.
update private.vehicle_usage_rollout set enabled=false;
update private.group_checkout_rollout set enabled=false;
set role authenticated;
do $$ declare r jsonb; begin
 r:=public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001');
 if r->>'group_checkout_enabled'<>'false' or r->>'vehicle_usage_enabled'<>'false' or r->>'vehicle_meter_enabled'<>'false' then raise exception 'actual post-fixture OFF contract mismatch'; end if;
end $$;
reset role;
