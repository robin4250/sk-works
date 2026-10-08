insert into companies values('10000000-0000-0000-0000-000000000001');
insert into company_members values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000011','member'),('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000012','member');
insert into workers(id,company_id,status,user_id,name) values
('10000000-0000-0000-0000-000000000021','10000000-0000-0000-0000-000000000001','active','10000000-0000-0000-0000-000000000011','one'),
('10000000-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000001','active','10000000-0000-0000-0000-000000000012','two');
insert into sites(id,company_id) values('10000000-0000-0000-0000-000000000031','10000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000032','10000000-0000-0000-0000-000000000001');
insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,verification_mode,confirmed_at) values
('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000021','10000000-0000-0000-0000-000000000031','clock_in','manual','2026-01-31 20:00+09'),
('10000000-0000-0000-0000-000000000042','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000031','clock_in','manual','2026-01-31 20:30+09'),
('10000000-0000-0000-0000-000000000043','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000032','clock_in','manual','2026-02-01 20:30+09');
insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,source_clock_in_id) values
('10000000-0000-0000-0000-000000000044','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000031','clock_out','manual','2026-01-31 23:00+09','10000000-0000-0000-0000-000000000042');
select set_config('test.actor','10000000-0000-0000-0000-000000000011',false);
do $$ begin
 begin perform public.group_checkout_candidates('10000000-0000-0000-0000-000000000041'); raise exception 'gate unexpectedly enabled';
 exception when raise_exception then if sqlerrm='gate unexpectedly enabled' then raise; end if; end;
 if exists(select 1 from attendance_verifications where evidence_origin is not null) then raise exception 'old rows modified'; end if;
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,source_clock_in_id,created_by,proxy_actor_user_id)
  values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000021','10000000-0000-0000-0000-000000000031','clock_out','manual',now(),'10000000-0000-0000-0000-000000000041',auth.uid(),auth.uid());
  raise exception 'null origin with proxy actor allowed';
 exception when check_violation then null; end;

end $$;
insert into private.group_checkout_rollout values('10000000-0000-0000-0000-000000000001',true);
set role authenticated;
do $$ declare r jsonb; again jsonb; begin
 r:=public.group_checkout_candidates('10000000-0000-0000-0000-000000000041');
 if jsonb_array_length(r)<>2 then raise exception 'wrong roster: %',r; end if;
 begin perform public.commit_group_checkout('10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000043'::uuid],'10000000-0000-0000-0000-000000000051'); raise exception 'foreign site allowed';
 exception when raise_exception then if sqlerrm='foreign site allowed' then raise; end if; end;
 r:=public.commit_group_checkout('10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000041'::uuid,'10000000-0000-0000-0000-000000000042'::uuid],'10000000-0000-0000-0000-000000000052');
 again:=public.commit_group_checkout('10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000042'::uuid,'10000000-0000-0000-0000-000000000041'::uuid],'10000000-0000-0000-0000-000000000052');
 if r<>again then raise exception 'retry changed results'; end if;
 begin perform public.group_checkout_candidates('10000000-0000-0000-0000-000000000042'); raise exception 'other worker anchor allowed';
 exception when raise_exception then if sqlerrm='other worker anchor allowed' then raise; end if; end;
 begin
  perform public.commit_group_checkout('10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000041'::uuid],'10000000-0000-0000-0000-000000000052');
  raise exception 'reused token changed selection';
 exception when raise_exception then if sqlerrm='reused token changed selection' then raise; end if; end;
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,source_clock_in_id,created_by)
  values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000032','clock_out','manual',now(),'10000000-0000-0000-0000-000000000043',auth.uid());
  raise exception 'other worker direct insert allowed';
 exception when insufficient_privilege then null;
 when raise_exception then if sqlerrm='other worker direct insert allowed' then raise; end if; end;
 begin
  insert into attendance_verifications(company_id,worker_id,site_id,event_type,verification_mode,confirmed_at,source_clock_in_id,created_by,evidence_origin,proxy_actor_user_id)
  values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000032','clock_out','manual',now(),'10000000-0000-0000-0000-000000000043',auth.uid(),'team_proxy',auth.uid());
  raise exception 'direct proxy allowed';
 exception when raise_exception then if sqlerrm='direct proxy allowed' then raise; end if; end;
end $$;
reset role;
do $$ begin
 if (select count(*) from attendance_verifications where source_clock_in_id='10000000-0000-0000-0000-000000000041')<>1 then raise exception 'duplicate checkout'; end if;
 if not exists(select 1 from attendance_verifications where source_clock_in_id='10000000-0000-0000-0000-000000000041' and work_date='2026-01-31' and evidence_origin='team_proxy' and latitude is null and photo_storage_path is null and proxy_actor_user_id='10000000-0000-0000-0000-000000000011') then raise exception 'proxy provenance missing'; end if;
 if not exists(select 1 from attendance_verifications where id='10000000-0000-0000-0000-000000000044' and confirmed_at='2026-01-31 23:00+09' and evidence_origin is null) then raise exception 'early leave changed'; end if;
 begin update attendance_verifications set evidence_origin=null,proxy_actor_user_id=null where evidence_origin='team_proxy'; raise exception 'origin rewritten';
 exception when raise_exception then if sqlerrm='origin rewritten' then raise; end if; end;
end $$;
-- A different actual member, even one who left early, may perform the same group action.
select set_config('test.actor','10000000-0000-0000-0000-000000000012',false);
set role authenticated;
do $$ declare r jsonb; begin
 r:=public.commit_group_checkout('10000000-0000-0000-0000-000000000042',array['10000000-0000-0000-0000-000000000041'::uuid,'10000000-0000-0000-0000-000000000042'::uuid],'10000000-0000-0000-0000-000000000053');
 if jsonb_array_length(r)<>2 then raise exception 'different member denied'; end if;
end $$;
reset role;
select set_config('test.actor','10000000-0000-0000-0000-000000000011',false);
select set_config('test.blocked','true',false);
set role authenticated;
do $$ begin
 begin perform public.group_checkout_candidates('10000000-0000-0000-0000-000000000041'); raise exception 'blocked allowed';
 exception when raise_exception then if sqlerrm='blocked allowed' then raise; end if; end;
end $$;
reset role;
