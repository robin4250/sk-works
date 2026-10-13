-- Staged OFF. Separate immutable evidence: never invent attendance events.
create table private.route_journey_rollouts (
 company_id uuid primary key references public.companies(id) on delete cascade,
 enabled boolean not null default false
);
create table private.route_journey_captures (
 id uuid primary key, company_id uuid not null references public.companies(id) on delete cascade,
 source_clock_in_id uuid not null references public.attendance_verifications(id) on delete cascade,
 worker_id uuid not null references public.workers(id) on delete cascade,
 route_assignment_id uuid not null, route_stop_id uuid not null, stop_order integer not null,
 stop_label text not null, work_date date not null, origin_kind text not null check(origin_kind in ('company','direct')),
 created_by uuid not null, recorded_at timestamptz not null default clock_timestamp(),
 payload jsonb not null, daily_report_id uuid references public.daily_reports(id) on delete set null
);
create unique index route_journey_captures_photo on private.route_journey_captures((payload->>'photo_storage_path')) where payload->>'photo_storage_path' is not null;
create index route_journey_captures_source on private.route_journey_captures(source_clock_in_id,recorded_at);
alter table private.route_journey_rollouts enable row level security;
alter table private.route_journey_captures enable row level security;
revoke all on private.route_journey_rollouts,private.route_journey_captures from public,anon,authenticated;
create function private.route_journey_raw_immutable() returns trigger language plpgsql set search_path='' as $$
begin
 if (to_jsonb(new)-'daily_report_id') is distinct from (to_jsonb(old)-'daily_report_id') then
  raise exception 'route journey raw evidence immutable' using errcode='42501';
 end if;
 return new;
end $$;
create trigger route_journey_raw_immutable before update on private.route_journey_captures for each row execute function private.route_journey_raw_immutable();

create function private.route_journey_workspace(p_source_clock_in_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.attendance_verifications%rowtype; enabled boolean:=false; stops jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select a.* into s from public.attendance_verifications a join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
 where a.id=p_source_clock_in_id and a.event_type='clock_in' and a.site_id is null and a.route_assignment_id is not null
 and a.work_date is not null and w.user_id=auth.uid() and w.status='active'
 and exists(select 1 from public.company_members where company_id=a.company_id and user_id=auth.uid());
 if not found then raise exception 'actual personal route start required' using errcode='42501'; end if;
 enabled:=s.verification_mode='location_photo' and s.capture_contract_version=1
 and exists(select 1 from private.route_journey_rollouts r where r.company_id=s.company_id and r.enabled)
 and coalesce((public.get_attendance_capture_capability(s.company_id)->>'capture_enabled')::boolean,false)
 and to_regprocedure('public.save_route_journey_capture(uuid,uuid,uuid,text,jsonb)') is not null
 and to_regprocedure('public.link_route_journey_report(uuid)') is not null
 and to_regprocedure('public.route_journey_report_evidence(uuid)') is not null
 and exists(select 1 from storage.buckets where id='attendance-route-evidence' and not public);
 select coalesce(jsonb_agg(jsonb_build_object('id',rs.id,'stop_order',rs.stop_order,'label',coalesce(rs.source_label,site.name,rs.address,'現場')) order by rs.stop_order,rs.id),'[]'::jsonb)
 into stops from public.route_stops rs left join public.sites site on site.id=rs.site_id where rs.route_assignment_id=s.route_assignment_id;
 return jsonb_build_object('version',1,'enabled',enabled,'source_clock_in_id',s.id,'company_id',s.company_id,'worker_id',s.worker_id,
 'route_assignment_id',s.route_assignment_id,'work_date',s.work_date,'stops',case when enabled then stops else '[]'::jsonb end,
 'is_open',not exists(select 1 from public.attendance_verifications where source_clock_in_id=s.id and event_type='clock_out'),
 'origin_kind',(select origin_kind from private.route_journey_captures where source_clock_in_id=s.id order by recorded_at,id limit 1));
end $$;
create function public.route_journey_workspace(p_source_clock_in_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.route_journey_workspace(p_source_clock_in_id) $$;

create function private.route_journey_capture_exact(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select to_jsonb(c) into result from private.route_journey_captures c where c.id=p_id and c.created_by=auth.uid()
 and exists(select 1 from public.company_members where company_id=c.company_id and user_id=auth.uid());
 return result;
end $$;
create function public.route_journey_capture_exact(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.route_journey_capture_exact(p_id) $$;

create function private.save_route_journey_capture(p_id uuid,p_source_clock_in_id uuid,p_route_stop_id uuid,p_origin_kind text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.attendance_verifications%rowtype; old private.route_journey_captures%rowtype; stop public.route_stops%rowtype; gps text; photo text; origin text; lat numeric; lon numeric; accuracy numeric; path text;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into old from private.route_journey_captures where id=p_id;
 if found then
  if old.created_by is distinct from auth.uid() or old.source_clock_in_id is distinct from p_source_clock_in_id or old.route_stop_id is distinct from p_route_stop_id or old.origin_kind is distinct from p_origin_kind or old.payload is distinct from p_payload or not exists(select 1 from public.company_members where company_id=old.company_id and user_id=auth.uid()) then raise exception 'fixed route capture mismatch' using errcode='23505'; end if;
  return to_jsonb(old);
 end if;
 select * into s from public.attendance_verifications where id=p_source_clock_in_id;
 if not found then raise exception 'route source not found'; end if;
 perform 1 from public.companies where id=s.company_id for key share;
 select * into s from public.attendance_verifications where id=p_source_clock_in_id for update;
 if not found or not coalesce((private.route_journey_workspace(s.id)->>'enabled')::boolean,false) then raise exception 'route journey capture disabled'; end if;
 if exists(select 1 from public.attendance_verifications where source_clock_in_id=s.id and event_type='clock_out') then raise exception 'route shift already closed'; end if;
 select * into stop from public.route_stops where id=p_route_stop_id and route_assignment_id=s.route_assignment_id;
 if not found then raise exception 'actual route stop required'; end if;
 if p_origin_kind is null or p_origin_kind not in ('company','direct') then raise exception 'select company departure or direct travel'; end if;
 select origin_kind into origin from private.route_journey_captures where source_clock_in_id=s.id order by recorded_at,id limit 1;
 if origin is not null and origin<>p_origin_kind then raise exception 'saved journey origin immutable'; end if;
 if p_id is null or jsonb_typeof(p_payload) is distinct from 'object' or p_payload->>'capture_contract_version' is distinct from '1' or exists(select 1 from jsonb_object_keys(p_payload) k where k not in ('capture_contract_version','gps_capture_status','photo_capture_status','gps_captured_at','photo_captured_at','photo_observed_at','captured_address','latitude','longitude','accuracy_m','photo_storage_path','attempted_at')) then raise exception 'invalid route capture payload'; end if;
 if exists(select 1 from jsonb_each(p_payload) e where
  (e.key in ('gps_captured_at','photo_captured_at','photo_observed_at','captured_address','photo_storage_path','attempted_at') and jsonb_typeof(e.value) not in ('string','null')) or
  (e.key in ('latitude','longitude','accuracy_m','capture_contract_version') and jsonb_typeof(e.value) not in ('number','null'))) then raise exception 'raw capture types invalid'; end if;
 gps:=p_payload->>'gps_capture_status'; photo:=p_payload->>'photo_capture_status'; path:=p_payload->>'photo_storage_path';
 if gps is null or gps not in ('acquired','failed','missing') or photo is null or photo not in ('uploaded','upload_failed','failed','missing') then raise exception 'invalid capture state'; end if;
 lat:=(p_payload->>'latitude')::numeric; lon:=(p_payload->>'longitude')::numeric; accuracy:=(p_payload->>'accuracy_m')::numeric;
 if lat::text in ('NaN','Infinity','-Infinity') or lon::text in ('NaN','Infinity','-Infinity') or accuracy::text in ('NaN','Infinity','-Infinity') or accuracy<0 then raise exception 'finite nonnegative GPS accuracy required'; end if;
 if gps='acquired' then
  if lat is null or lon is null or lat not between -90 and 90 or lon not between -180 and 180 or p_payload->>'gps_captured_at' is null then raise exception 'actual GPS sample required'; end if;
 else
  if lat is not null or lon is not null or p_payload->>'gps_captured_at' is not null or p_payload->>'captured_address' is not null or p_payload->>'accuracy_m' is not null then raise exception 'failed GPS cannot invent evidence'; end if;
 end if;
 if photo='uploaded' then
  if path is null or path not like s.company_id::text||'/attendance/'||s.route_assignment_id::text||'/'||s.worker_id::text||'/'||s.id::text||'/%' then raise exception 'own route photo required'; end if;
   if not exists(select 1 from storage.objects where bucket_id='attendance-route-evidence' and name=path) then raise exception 'uploaded route photo not found'; end if;
 elsif path is not null then raise exception 'failed photo cannot claim upload'; end if;
 if photo in ('uploaded','upload_failed') and p_payload->>'photo_observed_at' is null then raise exception 'camera observation required'; end if;
 if photo in ('failed','missing') and (p_payload->>'photo_captured_at' is not null or p_payload->>'photo_observed_at' is not null) then raise exception 'missing photo cannot invent time'; end if;
 if exists(select 1 from jsonb_each_text(p_payload) e where e.key in ('gps_captured_at','photo_captured_at','photo_observed_at','attempted_at') and e.value is not null and not isfinite(e.value::timestamptz)) then raise exception 'finite capture time required'; end if;
 if p_payload->>'attempted_at' is null then raise exception 'attempt time required'; end if;
 perform (p_payload->>'attempted_at')::timestamptz;
 insert into private.route_journey_captures(id,company_id,source_clock_in_id,worker_id,route_assignment_id,route_stop_id,stop_order,stop_label,work_date,origin_kind,created_by,payload)
 values(p_id,s.company_id,s.id,s.worker_id,s.route_assignment_id,stop.id,stop.stop_order,coalesce(stop.source_label,stop.address,'現場'),s.work_date,p_origin_kind,auth.uid(),p_payload) returning * into old;
 return to_jsonb(old);
end $$;
create function public.save_route_journey_capture(p_id uuid,p_source_clock_in_id uuid,p_route_stop_id uuid,p_origin_kind text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.save_route_journey_capture(p_id,p_source_clock_in_id,p_route_stop_id,p_origin_kind,p_payload) $$;

create function private.link_route_journey_report(p_report_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare d public.daily_reports%rowtype; n integer;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into d from public.daily_reports where id=p_report_id for update;
 if not found or d.route_assignment_id is null or d.site_id is not null or d.updated_by is distinct from auth.uid() or d.status='signed' or not exists(select 1 from public.company_members where company_id=d.company_id and user_id=auth.uid()) then raise exception 'saved editable report author required' using errcode='42501'; end if;
 if not exists(select 1 from private.route_journey_rollouts r where r.company_id=d.company_id and r.enabled) then return 0; end if;
 update private.route_journey_captures c set daily_report_id=d.id where c.company_id=d.company_id and c.route_assignment_id=d.route_assignment_id and c.work_date=d.report_date and (c.daily_report_id is null or c.daily_report_id=d.id)
 and exists(select 1 from public.daily_report_workers rw where rw.report_id=d.id and rw.worker_id=c.worker_id)
 and exists(select 1 from public.attendance_verifications a where a.id=c.source_clock_in_id and a.daily_report_id=d.id);
 get diagnostics n=row_count; return n;
end $$;
create function public.link_route_journey_report(p_report_id uuid) returns integer language sql security invoker set search_path='' as $$select private.link_route_journey_report(p_report_id)$$;
create function private.route_journey_report_evidence(p_report_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.daily_reports%rowtype; result jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into d from public.daily_reports where id=p_report_id;
 if not found or not exists(select 1 from public.company_members where company_id=d.company_id and user_id=auth.uid()) then raise exception 'report unavailable' using errcode='42501'; end if;
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('worker_name',w.name) order by c.recorded_at,c.id),'[]'::jsonb) into result
 from private.route_journey_captures c join public.workers w on w.id=c.worker_id where c.daily_report_id=d.id and (w.user_id=auth.uid() or private.has_company_feature(w.company_id,'can_manage_attendance'));
 return result;
end $$;
create function public.route_journey_report_evidence(p_report_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.route_journey_report_evidence(p_report_id)$$;

-- Independent bucket avoids the legacy attendance orphan-deletion policy.
insert into storage.buckets(id,name,public) values('attendance-route-evidence','attendance-route-evidence',false);
create function private.route_journey_photo_insert_allowed(p_path text) returns boolean language plpgsql security definer set search_path='' as $$
declare source_id uuid; ws jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then return false; end if;
 begin source_id:=split_part(p_path,'/',5)::uuid; exception when invalid_text_representation then return false; end;
 begin ws:=private.route_journey_workspace(source_id); exception when others then return false; end;
 return ws->>'enabled'='true' and split_part(p_path,'/',1)=ws->>'company_id' and split_part(p_path,'/',2)='attendance'
 and split_part(p_path,'/',3)=ws->>'route_assignment_id' and split_part(p_path,'/',4)=ws->>'worker_id'
 and split_part(p_path,'/',6)<>'' and not exists(select 1 from public.attendance_verifications where source_clock_in_id=source_id and event_type='clock_out');
end $$;
revoke all on function private.route_journey_photo_insert_allowed(text) from public,anon;
grant execute on function private.route_journey_photo_insert_allowed(text) to authenticated;
create policy route_journey_photo_insert on storage.objects for insert to authenticated with check(bucket_id='attendance-route-evidence' and private.route_journey_photo_insert_allowed(name));
create policy route_journey_photo_read on storage.objects for select to authenticated using(bucket_id='attendance-route-evidence' and private.account_access_allowed() and exists(select 1 from public.workers w join public.company_members cm on cm.company_id=w.company_id and cm.user_id=auth.uid() where w.id::text=split_part(storage.objects.name,'/',4) and w.company_id::text=split_part(storage.objects.name,'/',1) and (w.user_id=auth.uid() or private.has_company_feature(w.company_id,'can_manage_attendance'))));
-- No UPDATE/DELETE policy for this evidence bucket.
revoke all on function private.route_journey_workspace(uuid),public.route_journey_workspace(uuid) from public,anon;
grant execute on function private.route_journey_workspace(uuid),public.route_journey_workspace(uuid) to authenticated;
revoke all on function private.route_journey_capture_exact(uuid),public.route_journey_capture_exact(uuid) from public,anon;
grant execute on function private.route_journey_capture_exact(uuid),public.route_journey_capture_exact(uuid) to authenticated;
revoke all on function private.save_route_journey_capture(uuid,uuid,uuid,text,jsonb),public.save_route_journey_capture(uuid,uuid,uuid,text,jsonb) from public,anon;
grant execute on function private.save_route_journey_capture(uuid,uuid,uuid,text,jsonb),public.save_route_journey_capture(uuid,uuid,uuid,text,jsonb) to authenticated;
revoke all on function private.link_route_journey_report(uuid),public.link_route_journey_report(uuid) from public,anon;
grant execute on function private.link_route_journey_report(uuid),public.link_route_journey_report(uuid) to authenticated;
revoke all on function private.route_journey_report_evidence(uuid),public.route_journey_report_evidence(uuid) from public,anon;
grant execute on function private.route_journey_report_evidence(uuid),public.route_journey_report_evidence(uuid) to authenticated;
revoke all on function private.route_journey_raw_immutable() from public,anon,authenticated;
