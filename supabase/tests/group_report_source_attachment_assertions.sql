-- Reuses actual staged group checkout fixture: source 041 has a NULL-photo
-- server proxy checkout; source 042 has original personal early departure.
insert into companies values('20000000-0000-0000-0000-000000000001');
insert into workers(id,company_id,status,user_id,name) values
('10000000-0000-0000-0000-000000000023','10000000-0000-0000-0000-000000000001','active','10000000-0000-0000-0000-000000000013','not yet checked out'),
('20000000-0000-0000-0000-000000000021','20000000-0000-0000-0000-000000000001','active','20000000-0000-0000-0000-000000000011','foreign');
insert into sites(id,company_id) values('20000000-0000-0000-0000-000000000031','20000000-0000-0000-0000-000000000001');
insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,verification_mode,confirmed_at) values
('10000000-0000-0000-0000-000000000045','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000023','10000000-0000-0000-0000-000000000031','clock_in','manual','2026-01-31 21:00+09'),
('20000000-0000-0000-0000-000000000041','20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000021','20000000-0000-0000-0000-000000000031','clock_in','manual','2026-01-31 21:00+09');
insert into daily_reports(id,company_id,site_id,report_date,status,created_by,updated_by) values
('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000031','2026-01-31','draft','10000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000011'),
('10000000-0000-0000-0000-000000000062','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000031','2026-01-31','draft','10000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000011');
insert into daily_report_workers(report_id,worker_id) values
('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000021'),
('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000022'),
('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000023'),
('10000000-0000-0000-0000-000000000062','10000000-0000-0000-0000-000000000021'),
('10000000-0000-0000-0000-000000000062','10000000-0000-0000-0000-000000000022');
create temp table evidence_before as select id,to_jsonb(a)-'daily_report_id' evidence from attendance_verifications a;
-- Test-only rejection helper intentionally invoker: actual authenticated ACLs
-- and the public wrapper are exercised, rather than owner-only function calls.
create function public.fixture_expect_attachment_rejected(p_sql text) returns void
language plpgsql security invoker set search_path='' as $$
begin
  begin execute p_sql;
  exception when others then return;
  end;
  raise exception 'unexpected attachment success: %',p_sql;
end $$;
grant execute on function public.fixture_expect_attachment_rejected(text) to authenticated;
set role authenticated;
select fixture_expect_attachment_rejected($q$update public.attendance_verifications set daily_report_id='10000000-0000-0000-0000-000000000061' where id='10000000-0000-0000-0000-000000000042'$q$);
select fixture_expect_attachment_rejected($q$select public.attach_group_report_sources('10000000-0000-0000-0000-000000000099','10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000042'::uuid])$q$);
select fixture_expect_attachment_rejected($q$select public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000042',array['10000000-0000-0000-0000-000000000041'::uuid])$q$);
select fixture_expect_attachment_rejected($q$select public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000043'::uuid])$q$);
select fixture_expect_attachment_rejected($q$select public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000041'::uuid,'10000000-0000-0000-0000-000000000041'::uuid])$q$);
select fixture_expect_attachment_rejected($q$select public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000041',array[null::uuid])$q$);
select fixture_expect_attachment_rejected($q$select public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000045'::uuid])$q$);
select fixture_expect_attachment_rejected($q$select public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000041',array['20000000-0000-0000-0000-000000000041'::uuid])$q$);
reset role;
-- Missing saved member, report author, wrong month, wrong site, foreign company,
-- signed status and timestamp each independently reject before any write.
do $$ declare statement text; begin
  foreach statement in array array[
    $q$delete from daily_report_workers where report_id='10000000-0000-0000-0000-000000000061' and worker_id='10000000-0000-0000-0000-000000000022'$q$,
    $q$delete from daily_report_workers where report_id='10000000-0000-0000-0000-000000000061' and worker_id='10000000-0000-0000-0000-000000000021'$q$,
    $q$update daily_reports set created_by='10000000-0000-0000-0000-000000000012',updated_by='10000000-0000-0000-0000-000000000012' where id='10000000-0000-0000-0000-000000000061'$q$,
    $q$update daily_reports set report_date='2026-02-01' where id='10000000-0000-0000-0000-000000000061'$q$,
    $q$update daily_reports set site_id='10000000-0000-0000-0000-000000000032' where id='10000000-0000-0000-0000-000000000061'$q$,
    $q$update daily_reports set company_id='20000000-0000-0000-0000-000000000001' where id='10000000-0000-0000-0000-000000000061'$q$,
    $q$update daily_reports set status='signed' where id='10000000-0000-0000-0000-000000000061'$q$,
    $q$update daily_reports set signed_at=now() where id='10000000-0000-0000-0000-000000000061'$q$
  ] loop
    begin
      execute statement;
      execute 'set local role authenticated';
      perform public.fixture_expect_attachment_rejected($q$select public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000042'::uuid])$q$);
      execute 'reset role';
      raise exception using errcode='ZX001',message='rollback fixture variation';
    exception when sqlstate 'ZX001' then null; end;
  end loop;
end $$;
-- All rejected calls are atomic; source evidence remains unlinked.
do $$ begin
  if exists(select 1 from attendance_verifications where daily_report_id is not null) then raise exception 'rejection changed evidence'; end if;
end $$;
set role authenticated;
do $$ declare r jsonb; again jsonb; begin
  r:=public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000042'::uuid,'10000000-0000-0000-0000-000000000041'::uuid]);
  again:=public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000041'::uuid,'10000000-0000-0000-0000-000000000042'::uuid]);
  if r<>again or r->>'daily_report_id'<>'10000000-0000-0000-0000-000000000061' or jsonb_array_length(r->'source_clock_in_ids')<>2 then raise exception 'retry contract changed'; end if;
  perform public.fixture_expect_attachment_rejected($q$select public.attach_group_report_sources('10000000-0000-0000-0000-000000000062','10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000041'::uuid])$q$);
end $$;
reset role;
do $$ begin
  if (select count(*) from attendance_verifications where daily_report_id='10000000-0000-0000-0000-000000000061')<>4 then raise exception 'source and original/proxy outs not linked'; end if;
  if exists(select 1 from attendance_verifications a join evidence_before b using(id) where to_jsonb(a)-'daily_report_id'<>b.evidence) then raise exception 'original evidence changed'; end if;
end $$;
update daily_reports set status='signed',signed_at=now() where id='10000000-0000-0000-0000-000000000061';
-- A fixture trigger proves a fully linked signed retry issues zero UPDATEs.
create function public.fixture_forbid_evidence_update() returns trigger language plpgsql as $$ begin raise exception 'unexpected evidence UPDATE'; end $$;
create trigger fixture_no_retry_update before update on attendance_verifications for each row execute function fixture_forbid_evidence_update();
set role authenticated;
select public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000041'::uuid,'10000000-0000-0000-0000-000000000042'::uuid]);
reset role;
select set_config('test.blocked','true',false);
set role authenticated;
select fixture_expect_attachment_rejected($q$select public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000041'::uuid])$q$);
reset role;
select set_config('test.blocked','false',false);
select set_config('test.actor','',false);
set role authenticated;
select fixture_expect_attachment_rejected($q$select public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000041'::uuid])$q$);
reset role;
do $$ begin
  if has_function_privilege('anon','public.attach_group_report_sources(uuid,uuid,uuid[])','EXECUTE')
     or has_function_privilege('anon','private.attach_group_report_sources(uuid,uuid,uuid[])','EXECUTE') then raise exception 'anonymous execution granted'; end if;
end $$;
update private.group_checkout_rollout set enabled=false;
select set_config('test.actor','10000000-0000-0000-0000-000000000011',false);
set role authenticated;
select fixture_expect_attachment_rejected($q$select public.attach_group_report_sources('10000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000041',array['10000000-0000-0000-0000-000000000041'::uuid])$q$);
reset role;
