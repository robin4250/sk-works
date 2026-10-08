-- Staged OFF: no publication until the UI final-save call and target route exist.
create table private.source_notification_rollouts(company_id uuid primary key references public.companies(id) on delete cascade, enabled boolean not null default false);
create table private.vehicle_notification_assignees(vehicle_id uuid primary key references public.vehicles(id) on delete cascade, company_id uuid not null references public.companies(id) on delete cascade, user_ids uuid[] not null check(cardinality(user_ids) between 1 and 3));
create table private.source_notification_receipts(notification_id uuid primary key references public.app_notifications(id) on delete cascade, company_id uuid not null, event_key text not null, source_id uuid not null, recipient_user_id uuid not null, work_date date not null, unique(event_key,source_id,recipient_user_id));
alter table private.source_notification_rollouts enable row level security;
alter table private.vehicle_notification_assignees enable row level security;
alter table private.source_notification_receipts enable row level security;
revoke all on private.source_notification_rollouts,private.vehicle_notification_assignees,private.source_notification_receipts from public,anon,authenticated;

create function private.set_vehicle_notification_assignees(p_vehicle_id uuid,p_user_ids uuid[]) returns void language plpgsql security definer set search_path='' as $$
declare c uuid;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select company_id into c from public.vehicles where id=p_vehicle_id for no key update;
 if c is null or not exists(select 1 from public.company_members where company_id=c and user_id=auth.uid() and role::text in ('owner','admin')) then raise exception 'vehicle administrator required' using errcode='42501'; end if;
 if cardinality(p_user_ids) is null or cardinality(p_user_ids) not between 1 and 3 or array_position(p_user_ids,null) is not null or (select count(distinct x) from unnest(p_user_ids)x)<>cardinality(p_user_ids) then raise exception 'select 1 to 3 distinct vehicle assignees'; end if;
 if exists(select 1 from unnest(p_user_ids)x where not exists(select 1 from public.company_members where company_id=c and user_id=x)) then raise exception 'assignee must belong to vehicle company' using errcode='42501'; end if;
 insert into private.vehicle_notification_assignees values(p_vehicle_id,c,p_user_ids) on conflict(vehicle_id) do update set user_ids=excluded.user_ids;
end $$;
create function public.set_vehicle_notification_assignees(p_vehicle_id uuid,p_user_ids uuid[]) returns void language sql security invoker set search_path='' as $$ select private.set_vehicle_notification_assignees(p_vehicle_id,p_user_ids) $$;
revoke all on function private.set_vehicle_notification_assignees(uuid,uuid[]), public.set_vehicle_notification_assignees(uuid,uuid[]) from public,anon;
grant execute on function private.set_vehicle_notification_assignees(uuid,uuid[]), public.set_vehicle_notification_assignees(uuid,uuid[]) to authenticated;

create function private.publish_saved_group_report_notifications(p_report_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare d public.daily_reports%rowtype; r record; n uuid; count_sent integer:=0; actor_name text;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into d from public.daily_reports where id=p_report_id for update;
 if not found or d.updated_by is distinct from auth.uid() or not exists(select 1 from public.company_members where company_id=d.company_id and user_id=auth.uid()) then raise exception 'saved report author required' using errcode='42501'; end if;
 if not exists(select 1 from private.source_notification_rollouts where company_id=d.company_id and enabled) then return 0; end if;
 if d.site_id is null or d.route_assignment_id is not null then raise exception 'site group report required'; end if;
 select w.name into actor_name from public.workers w join public.attendance_verifications s on s.worker_id=w.id where w.company_id=d.company_id and w.user_id=auth.uid() and w.status='active' and s.company_id=d.company_id and s.daily_report_id=d.id and s.event_type='clock_in' and s.work_date=d.report_date and s.site_id=d.site_id and exists(select 1 from public.daily_report_workers where report_id=d.id and worker_id=w.id) limit 1;
 if actor_name is null then raise exception 'actual participating report author required' using errcode='42501'; end if;
 -- Every saved roster row needs its attached original source and matching out.
 if not exists(select 1 from public.daily_report_workers where report_id=d.id) or exists(select 1 from public.daily_report_workers rw where rw.report_id=d.id and not exists(select 1 from public.attendance_verifications s join public.attendance_verifications o on o.source_clock_in_id=s.id and o.event_type='clock_out' where s.daily_report_id=d.id and o.daily_report_id=d.id and s.event_type='clock_in' and s.worker_id=rw.worker_id and s.company_id=d.company_id and s.site_id=d.site_id and s.route_assignment_id is null and s.work_date=d.report_date and row(o.company_id,o.worker_id,o.site_id,o.route_assignment_id,o.work_date) is not distinct from row(s.company_id,s.worker_id,s.site_id,s.route_assignment_id,s.work_date))) then raise exception 'report roster evidence incomplete'; end if;
 for r in select distinct w.user_id from public.daily_report_workers rw join public.workers w on w.id=rw.worker_id join public.company_members cm on cm.company_id=d.company_id and cm.user_id=w.user_id where rw.report_id=d.id and w.company_id=d.company_id and w.status='active' and w.user_id<>auth.uid() loop
  if not exists(select 1 from private.source_notification_receipts where event_key='group_report_saved' and source_id=d.id and recipient_user_id=r.user_id) then
   n:=private.enqueue_notification(d.company_id,r.user_id,'info',actor_name||'さんが日報登録しました。確認しますか？',to_char(d.report_date,'YYYY-MM-DD')||' の日報','group_report_saved',d.id);
   insert into private.source_notification_receipts values(n,d.company_id,'group_report_saved',d.id,r.user_id,d.report_date);
   count_sent:=count_sent+1;
  end if;
 end loop;
 return count_sent;
end $$;
create function public.publish_saved_group_report_notifications(p_report_id uuid) returns integer language sql security invoker set search_path='' as $$ select private.publish_saved_group_report_notifications(p_report_id) $$;
revoke all on function private.publish_saved_group_report_notifications(uuid),public.publish_saved_group_report_notifications(uuid) from public,anon;
grant execute on function private.publish_saved_group_report_notifications(uuid),public.publish_saved_group_report_notifications(uuid) to authenticated;

-- Transactional trigger only consumes a genuine personal clock-in. No recipient
-- provided by a client, no inferred manager, and no external mail delivery.
create function private.notify_vehicle_driver_started() returns trigger language plpgsql security definer set search_path='' as $$
declare r uuid; n uuid; v public.vehicles%rowtype; driver_name text; valid_claim boolean:=false;
begin
 if new.event_type<>'clock_in' or new.vehicle_id is null or new.work_date is null then return new; end if;
 if not exists(select 1 from private.source_notification_rollouts where company_id=new.company_id and enabled) then return new; end if;
 select w.name into driver_name from public.workers w join public.company_members cm on cm.company_id=w.company_id and cm.user_id=w.user_id where w.id=new.worker_id and w.company_id=new.company_id and w.user_id=auth.uid() and w.status='active';
 if driver_name is null or not private.account_access_allowed() then return new; end if;
 if to_regclass('public.vehicle_usage_claims') is null then return new; end if;
 execute 'select exists(select 1 from public.vehicle_usage_claims where source_clock_in_id=$1 and company_id=$2 and vehicle_id=$3 and driver_worker_id=$4 and work_date=$5)' into valid_claim using new.id,new.company_id,new.vehicle_id,new.worker_id,new.work_date;
 if not valid_claim then return new; end if;
 select * into v from public.vehicles where id=new.vehicle_id and company_id=new.company_id;
 if not found then return new; end if;
 for r in select distinct x from private.vehicle_notification_assignees a cross join lateral unnest(a.user_ids)x join public.company_members cm on cm.company_id=a.company_id and cm.user_id=x where a.vehicle_id=v.id and a.company_id=v.company_id loop
  if not exists(select 1 from private.source_notification_receipts where event_key='vehicle_driver_started' and source_id=new.id and recipient_user_id=r) then
   n:=private.enqueue_notification(new.company_id,r,'info',driver_name||'さんが'||coalesce(nullif(v.registration_number,''),v.display_name)||'の利用を開始しました',to_char(new.work_date,'YYYY-MM-DD'),'vehicle_driver_started',new.id);
   insert into private.source_notification_receipts values(n,new.company_id,'vehicle_driver_started',new.id,r,new.work_date);
  end if;
 end loop;
 return new;
end $$;
revoke all on function private.notify_vehicle_driver_started() from public,anon,authenticated;
create constraint trigger source_vehicle_started_notification after insert on public.attendance_verifications deferrable initially deferred for each row execute function private.notify_vehicle_driver_started();

-- Recipient-only target lookup; read_at is deliberately not business completion.
create function private.get_source_notification_target(p_notification_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r private.source_notification_receipts%rowtype;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into r from private.source_notification_receipts where notification_id=p_notification_id and recipient_user_id=auth.uid();
 if not found or not exists(select 1 from public.company_members where company_id=r.company_id and user_id=auth.uid()) then raise exception 'notification target unavailable' using errcode='42501'; end if;
 return jsonb_build_object('company_id',r.company_id,'event_key',r.event_key,'source_id',r.source_id,'work_date',r.work_date);
end $$;
create function public.get_source_notification_target(p_notification_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.get_source_notification_target(p_notification_id)$$;
revoke all on function private.get_source_notification_target(uuid),public.get_source_notification_target(uuid) from public,anon;
grant execute on function private.get_source_notification_target(uuid),public.get_source_notification_target(uuid) to authenticated;
