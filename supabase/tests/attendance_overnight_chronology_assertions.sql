-- Run only in isolated fixture through tool/verify_attendance_overnight.mjs.
do $$
declare
  cid uuid := '00000000-0000-0000-0000-000000000001';
  actor uuid := '00000000-0000-0000-0000-000000000002';
  worker uuid := '00000000-0000-0000-0000-000000000003';
  site uuid := '00000000-0000-0000-0000-000000000004';
  c record; items jsonb; actual timestamptz; saved_report uuid; n integer;
begin
  insert into company_members values(cid,actor,'admin');
  insert into workers values(worker,cid,'active');
  insert into sites values(site,cid);
  perform set_config('test.actor',actor::text,false);
  for c in select * from (values
    ('2026-10-08','08:00','17:00','2026-10-08 17:00'),
    ('2026-10-08','20:00','05:00','2026-10-09 05:00'),
    ('2026-12-31','23:30','00:15','2027-01-01 00:15'),
    ('2026-10-31','20:00','05:00','2026-11-01 05:00'),
    ('2026-10-08','08:00','08:00','2026-10-08 08:00'),
    ('2026-10-08',null,'05:00','2026-10-08 05:00')
  ) cases(work_date,clock_in,clock_out,expected) loop
    items := jsonb_build_array(jsonb_build_object('worker_id',worker,'site_id',site,'date',c.work_date,'clock_in',c.clock_in,'clock_out',c.clock_out));
    n := public.force_manage_attendance('upsert',items);
    if n <> 1 then raise exception 'incorrect returned count'; end if;
    select confirmed_at,daily_report_id into actual,saved_report from attendance_verifications
      where worker_id=worker and event_type='clock_out' and daily_report_id in
        (select id from daily_reports where report_date=c.work_date::date);
    if actual is distinct from (c.expected::timestamp at time zone 'Asia/Tokyo') or saved_report is null then
      raise exception 'stored chronology/report link mismatch: %',c;
    end if;
    perform public.force_manage_attendance('upsert',items);
    select count(*) into n from attendance_verifications where worker_id=worker and daily_report_id in
      (select id from daily_reports where report_date=c.work_date::date) and event_type='clock_out';
    if n<>1 then raise exception 'repeat update duplicated next-day end'; end if;
  end loop;
  -- Editing the next day must not remove the preceding report's overnight end.
  items := jsonb_build_array(jsonb_build_object('worker_id',worker,'site_id',site,'date','2026-11-01','clock_in','08:00','clock_out','17:00'));
  perform public.force_manage_attendance('upsert',items);
  if not exists(select 1 from attendance_verifications av join daily_reports dr on dr.id=av.daily_report_id
      where dr.report_date='2026-10-31' and av.event_type='clock_out') then raise exception 'previous shift lost'; end if;
  perform public.force_manage_attendance('delete',jsonb_build_array(jsonb_build_object('worker_id',worker,'site_id',site,'date','2026-10-31')));
  if exists(select 1 from attendance_verifications where confirmed_at=('2026-11-01 05:00'::timestamp at time zone 'Asia/Tokyo')) then
    raise exception 'delete left next-day end'; end if;
  perform set_config('test.actor','',false);
  begin
    perform public.force_manage_attendance('upsert',items);
    raise exception 'unexpected anonymous success';
  exception when others then
    if sqlerrm <> 'authentication required' then raise; end if;
  end;
  perform set_config('test.actor',actor::text,false);
  update company_members set role='viewer';
  begin
    perform public.force_manage_attendance('upsert',items);
    raise exception 'unexpected viewer success';
  exception when others then
    if sqlerrm <> 'attendance management permission required' then raise; end if;
  end;
  update company_members set role='admin';
  update workers set company_id=gen_random_uuid();
  begin
    perform public.force_manage_attendance('upsert',items);
    raise exception 'unexpected cross-company success';
  exception when others then
    if sqlerrm <> 'worker does not belong to company' then raise; end if;
  end;
end $$;
