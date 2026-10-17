-- ISOLATED DESIGN ONLY. Requires PR829 baseline. No production policy/gate.
-- Reproduce fixed UUID replay after management has deleted the original row.
do $$ declare rid uuid; original public.attendance_verifications%rowtype; begin
 rid:=private.retention_fixture_seed('2030-04-01');
 select * into original from public.attendance_verifications where daily_report_id=rid and event_type='clock_in';
 perform private.retention_fixture_manage('2030-04-01','delete');
 original.daily_report_id:=null;
 insert into public.attendance_verifications select (original).*;
 if not exists(select 1 from public.attendance_verifications where id=original.id) then raise exception 'deleted UUID replay gap no longer reproduced'; end if;
 delete from public.attendance_verifications where id=original.id;
end $$;

-- Experimental archive-aware UUID tombstone; direct INSERT model only.
create function private.retention_fixture_reject_archived_uuid() returns trigger language plpgsql as $$ begin
 if exists(select 1 from private.retention_fixture_archive where id=new.id) then raise exception 'archived capture UUID cannot be reused' using errcode='23505'; end if;
 return new;
end $$;
create trigger retention_fixture_archived_uuid before insert on public.attendance_verifications for each row execute function private.retention_fixture_reject_archived_uuid();
do $$ declare original public.attendance_verifications%rowtype; changed boolean; begin
 select (jsonb_populate_record(null::public.attendance_verifications,evidence)).* into original from private.retention_fixture_archive where (evidence->>'work_date')::date='2030-04-01' and evidence->>'event_type'='clock_in';
 original.daily_report_id:=null;
 foreach changed in array array[false,true] loop
 if changed then original.note:='different retry payload'; end if;
 begin
  insert into public.attendance_verifications select (original).*;
  raise exception 'archive UUID was accepted';
 exception when unique_violation then
  if SQLERRM<>'archived capture UUID cannot be reused' then raise; end if;
 end;
 end loop;
end $$;

-- Synthetic child has the same parent cascade direction as route_journey_captures.
-- Does not install production route RPCs, storage, RLS or enable their rollout.
create table private.retention_fixture_journey(id uuid primary key,source_clock_in_id uuid references public.attendance_verifications(id) on delete cascade,created_by uuid,daily_report_id uuid references public.daily_reports(id) on delete set null,payload jsonb);
create table private.retention_fixture_journey_archive(id uuid primary key,original jsonb not null,changed_by uuid not null);
create function private.retention_fixture_save_children() returns trigger language plpgsql as $$ begin
 insert into private.retention_fixture_journey_archive select j.id,to_jsonb(j),auth.uid() from private.retention_fixture_journey j where j.source_clock_in_id=old.id on conflict(id) do nothing;
 return old;
end $$;
create trigger retention_fixture_save_children before delete on public.attendance_verifications for each row execute function private.retention_fixture_save_children();
do $$ declare rid uuid; sid uuid; expected jsonb; capturer uuid:='10000000-0000-0000-0000-000000000099'; administrator uuid:='10000000-0000-0000-0000-000000000002'; begin
 rid:=private.retention_fixture_seed('2030-04-02');
 select id into sid from public.attendance_verifications where daily_report_id=rid and event_type='clock_in';
 insert into private.retention_fixture_journey values('20000000-0000-0000-0000-000000000001',sid,capturer,rid,'{"photo_storage_path":"synthetic/mid-route.jpg","gps_capture_status":"failed"}');
 select to_jsonb(j) into expected from private.retention_fixture_journey j where source_clock_in_id=sid;
 perform private.retention_fixture_manage('2030-04-02','delete');
 if exists(select 1 from private.retention_fixture_journey where source_clock_in_id=sid) then raise exception 'child cascade did not occur'; end if;
 if not exists(select 1 from private.retention_fixture_journey_archive where original=expected and changed_by=administrator and (original->>'created_by')::uuid=capturer and (original->>'daily_report_id')::uuid=rid) then raise exception 'cascade snapshot or actual actor lost'; end if;
end $$;
