-- Extend successful clock-in inbox delivery without changing RLS, recipients,
-- attendance evidence, historical notifications or operating-system push.
do $$begin
 if md5(pg_get_functiondef('private.notify_management_of_attendance_location()'::regprocedure)) <> '6566efb2487379a0b039da81e776c1bb' then
  raise exception 'attendance management notification definition drift: inspect before applying';
 end if;
 if not exists(select 1 from pg_trigger where tgrelid='public.attendance_verifications'::regclass
   and tgname='notify_management_of_attendance_location'
   and pg_get_triggerdef(oid)='CREATE TRIGGER notify_management_of_attendance_location AFTER INSERT ON public.attendance_verifications FOR EACH ROW EXECUTE FUNCTION private.notify_management_of_attendance_location()') then
  raise exception 'attendance management notification trigger drift: inspect before applying';
 end if;
end $$;

-- An evidence ID can notify each existing recipient only once. Keep receipts
-- independently of inbox deletion so retry cannot re-create a read notice.
create table private.attendance_clock_in_notification_receipts (
 company_id uuid not null,
 source_id uuid not null,
 recipient_user_id uuid not null,
 created_at timestamptz not null default now(),
 primary key(company_id,source_id,recipient_user_id)
);
revoke all on private.attendance_clock_in_notification_receipts from public,anon,authenticated;

create or replace function private.notify_management_of_attendance_location()
returns trigger language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
 v_worker_name text;
 v_site_name text;
 v_route_name text;
 v_recipient record;
 v_recorded boolean;
begin
 if new.event_type='clock_in' then
  select name into v_worker_name from public.workers where id=new.worker_id and company_id=new.company_id;
  select name into v_site_name from public.sites where id=new.site_id and company_id=new.company_id;
  select route_name into v_route_name from public.route_assignments where id=new.route_assignment_id and company_id=new.company_id;
  for v_recipient in select distinct cm.user_id from public.company_members cm
   where cm.company_id=new.company_id and cm.role::text in ('owner','admin','manager') loop
   v_recorded:=null;
   insert into private.attendance_clock_in_notification_receipts(company_id,source_id,recipient_user_id)
    values(new.company_id,new.id,v_recipient.user_id) on conflict do nothing returning true into v_recorded;
   if v_recorded then
    perform private.enqueue_notification(new.company_id,v_recipient.user_id,'attendance','出勤しました',
     coalesce(v_worker_name,'社員')||'さんが出勤しました。 記録時刻: '||
     to_char(new.confirmed_at at time zone 'Asia/Tokyo','YYYY-MM-DD HH24:MI')||'。'||
     case when coalesce(v_route_name,'')<>'' then ' ルート: '||v_route_name||'。'
          when coalesce(v_site_name,'')<>'' then ' 現場: '||v_site_name||'。' else '' end,
     'attendance_today',new.id);
   end if;
  end loop;
  return new;
 end if;
 -- Preserve the existing GPS clock-out location notice.
 if new.latitude is null or new.longitude is null then return new;end if;
 select w.name into v_worker_name from public.workers w where w.id=new.worker_id;
 select s.name into v_site_name from public.sites s where s.id=new.site_id;
 for v_recipient in select cm.user_id from public.company_members cm
  where cm.company_id=new.company_id and cm.role::text in ('owner','admin','manager') loop
  perform private.enqueue_notification(new.company_id,v_recipient.user_id,'attendance','最新の打刻位置',
   coalesce(v_worker_name,'社員')||'さんが'||case when new.event_type='clock_out' then '退勤' else '出勤' end||'しました。'||
   case when coalesce(v_site_name,'')<>'' then ' 現場: '||v_site_name||'。' else '。' end||
   ' 現場マップで最新の打刻位置を確認できます。','site_map',new.id);
 end loop;
 return new;
end $$;
