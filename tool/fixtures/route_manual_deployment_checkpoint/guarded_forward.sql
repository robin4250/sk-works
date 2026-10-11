-- Read-only preflight checkpoint from 2026-10-11. Code definitions only; NOT a DB/Storage data backup.
-- Run inside the same transaction as the four replacements. Failure must abort it.
do $guard$
declare e record; actual record;
begin
 for e in select * from (values
('get_attendance_capture_capability(uuid)','ad05d93e98fa01fec4b73751d19cac5e','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',false),
('private.route_journey_workspace(uuid)','3bc36781f4f4716df62bc0648edb68cb','postgres','{postgres=X/postgres,authenticated=X/postgres}',true),
('private.save_route_journey_capture(uuid,uuid,uuid,text,jsonb)','439dafeb66eff9c4b6dda3fe2f0ba23b','postgres','{postgres=X/postgres,authenticated=X/postgres}',true),
('save_route_journey_capture(uuid,uuid,uuid,text,jsonb)','d190f61868b295506663555f0e3d4ee7','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',false),
('private.link_route_journey_report(uuid)','121d63199cc8c0ade0495437c68aeae3','postgres','{postgres=X/postgres,authenticated=X/postgres}',true),
('link_route_journey_report(uuid)','ae0437417700a40eb2b07b0f3ab2d934','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',false),
('private.route_journey_report_evidence(uuid)','1cf379b5634e903aad777a3c0d00a260','postgres','{postgres=X/postgres,authenticated=X/postgres}',true),
('route_journey_report_evidence(uuid)','0f0ca7610f73e52cc556a3e7d94e0756','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',false),
('route_journey_visit_workspace(uuid)','8985ad58e31d885f575aa4b59a9fe68b','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',false),
('private.save_route_journey_visit(uuid,uuid,uuid,text,jsonb,text,uuid)','578af0005f38d867289605406593d540','postgres','{postgres=X/postgres,authenticated=X/postgres}',true),
('save_route_journey_visit(uuid,uuid,uuid,text,jsonb,text,uuid)','b4582818aff8739490b4558c4fbbc566','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',false),
('private.route_journey_live_visit_workspace(uuid)','7e94935b8f03bdd0a7b576629472e35e','postgres','{postgres=X/postgres}',true),
('private.route_journey_visit_workspace(uuid)','94eea78d815ca627f32df579517391fa','postgres','{postgres=X/postgres,authenticated=X/postgres}',true)
 ) expected(signature,definition_md5,owner_name,acl_text,security_definer) loop
  select md5(pg_get_functiondef(p.oid)) definition_md5,pg_get_userbyid(p.proowner) owner_name,p.proacl::text acl_text,p.prosecdef security_definer
  into actual from pg_proc p where p.oid=to_regprocedure(e.signature);
  if not found or row(actual.definition_md5,actual.owner_name,actual.acl_text,actual.security_definer)
    is distinct from row(e.definition_md5,e.owner_name,e.acl_text,e.security_definer) then
    raise exception 'route manual prerequisite drift: %',e.signature using errcode='55000';
  end if;
 end loop;
 if not exists(select 1 from storage.buckets where id='attendance-route-evidence' and not public) then
  raise exception 'private route evidence bucket required' using errcode='55000';
 end if;
 if not exists(select 1 from pg_trigger where tgrelid='public.attendance_verifications'::regclass and tgname='route_journey_visit_before_clock_out' and tgenabled='O' and tgfoid=to_regprocedure('private.route_journey_visit_before_clock_out()')) then
  raise exception 'route clock-out lifecycle trigger required' using errcode='55000';
 end if;
 if not exists(select 1 from pg_trigger where tgrelid='public.attendance_verifications'::regclass and tgname='route_visit_archive_parent' and tgenabled='O' and pg_get_triggerdef(oid)='CREATE TRIGGER route_visit_archive_parent BEFORE DELETE ON public.attendance_verifications FOR EACH ROW EXECUTE FUNCTION private.archive_route_journey_visit_change()') then raise exception 'route archive lifecycle trigger drift: route_visit_archive_parent' using errcode='55000'; end if;
 if not exists(select 1 from pg_trigger where tgrelid='public.attendance_verifications'::regclass and tgname='route_visit_source_tombstone' and tgenabled='O' and pg_get_triggerdef(oid)='CREATE TRIGGER route_visit_source_tombstone BEFORE INSERT ON public.attendance_verifications FOR EACH ROW EXECUTE FUNCTION private.route_visit_reject_archived_id()') then raise exception 'route archive lifecycle trigger drift: route_visit_source_tombstone' using errcode='55000'; end if;
 if not exists(select 1 from pg_trigger where tgrelid='public.daily_reports'::regclass and tgname='route_visit_archive_report' and tgenabled='O' and pg_get_triggerdef(oid)='CREATE TRIGGER route_visit_archive_report BEFORE DELETE ON public.daily_reports FOR EACH ROW EXECUTE FUNCTION private.archive_route_journey_visit_change()') then raise exception 'route archive lifecycle trigger drift: route_visit_archive_report' using errcode='55000'; end if;
 if not exists(select 1 from pg_trigger where tgrelid='private.route_journey_captures'::regclass and tgname='route_visit_archive_capture' and tgenabled='O' and pg_get_triggerdef(oid)='CREATE TRIGGER route_visit_archive_capture BEFORE DELETE ON private.route_journey_captures FOR EACH ROW EXECUTE FUNCTION private.archive_route_journey_visit_change()') then raise exception 'route archive lifecycle trigger drift: route_visit_archive_capture' using errcode='55000'; end if;
 if not exists(select 1 from pg_trigger where tgrelid='private.route_journey_captures'::regclass and tgname='route_visit_archive_unlink' and tgenabled='O' and pg_get_triggerdef(oid)='CREATE TRIGGER route_visit_archive_unlink BEFORE UPDATE OF daily_report_id ON private.route_journey_captures FOR EACH ROW WHEN (((old.daily_report_id IS NOT NULL) AND (old.daily_report_id IS DISTINCT FROM new.daily_report_id))) EXECUTE FUNCTION private.archive_route_journey_visit_change()') then raise exception 'route archive lifecycle trigger drift: route_visit_archive_unlink' using errcode='55000'; end if;
 if not exists(select 1 from pg_trigger where tgrelid='private.route_journey_captures'::regclass and tgname='route_visit_capture_tombstone' and tgenabled='O' and pg_get_triggerdef(oid)='CREATE TRIGGER route_visit_capture_tombstone BEFORE INSERT ON private.route_journey_captures FOR EACH ROW EXECUTE FUNCTION private.route_visit_reject_archived_id()') then raise exception 'route archive lifecycle trigger drift: route_visit_capture_tombstone' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_rollouts' and column_name='company_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_rollouts.company_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_rollouts' and column_name='enabled' and data_type='boolean') then raise exception 'route column prerequisite drift: route_journey_rollouts.enabled' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_captures.id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='company_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_captures.company_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='source_clock_in_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_captures.source_clock_in_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='worker_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_captures.worker_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='route_assignment_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_captures.route_assignment_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='route_stop_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_captures.route_stop_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='stop_order' and data_type='integer') then raise exception 'route column prerequisite drift: route_journey_captures.stop_order' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='stop_label' and data_type='text') then raise exception 'route column prerequisite drift: route_journey_captures.stop_label' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='work_date' and data_type='date') then raise exception 'route column prerequisite drift: route_journey_captures.work_date' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='origin_kind' and data_type='text') then raise exception 'route column prerequisite drift: route_journey_captures.origin_kind' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='created_by' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_captures.created_by' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='recorded_at' and data_type='timestamp with time zone') then raise exception 'route column prerequisite drift: route_journey_captures.recorded_at' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='payload' and data_type='jsonb') then raise exception 'route column prerequisite drift: route_journey_captures.payload' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_captures' and column_name='daily_report_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_captures.daily_report_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_events' and column_name='capture_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_visit_events.capture_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_events' and column_name='source_clock_in_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_visit_events.source_clock_in_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_events' and column_name='route_stop_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_visit_events.route_stop_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_events' and column_name='kind' and data_type='text') then raise exception 'route column prerequisite drift: route_journey_visit_events.kind' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_events' and column_name='start_capture_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_visit_events.start_capture_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_archive' and column_name='id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_visit_archive.id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_archive' and column_name='company_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_visit_archive.company_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_archive' and column_name='source_clock_in_id' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_visit_archive.source_clock_in_id' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_archive' and column_name='created_by' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_visit_archive.created_by' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_archive' and column_name='raw_capture' and data_type='jsonb') then raise exception 'route column prerequisite drift: route_journey_visit_archive.raw_capture' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_archive' and column_name='visit_event' and data_type='jsonb') then raise exception 'route column prerequisite drift: route_journey_visit_archive.visit_event' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_archive' and column_name='source_snapshot' and data_type='jsonb') then raise exception 'route column prerequisite drift: route_journey_visit_archive.source_snapshot' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_archive' and column_name='report_snapshot' and data_type='jsonb') then raise exception 'route column prerequisite drift: route_journey_visit_archive.report_snapshot' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_archive' and column_name='changed_by' and data_type='uuid') then raise exception 'route column prerequisite drift: route_journey_visit_archive.changed_by' using errcode='55000'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='private' and table_name='route_journey_visit_archive' and column_name='archived_at' and data_type='timestamp with time zone') then raise exception 'route column prerequisite drift: route_journey_visit_archive.archived_at' using errcode='55000'; end if;
 if not exists(select 1 from pg_class where oid='private.route_journey_visit_events'::regclass and relrowsecurity and relacl::text='{postgres=arwdDxtm/postgres}') or not exists(select 1 from pg_class where oid='private.route_journey_visit_archive'::regclass and relrowsecurity and relacl::text='{postgres=arwdDxtm/postgres}') then
  raise exception 'private route event/archive access drift' using errcode='55000';
 end if;
 if (select count(*) from private.route_journey_rollouts)<>1 or (select count(*) from private.route_journey_rollouts where enabled)<>1 then raise exception 'route rollout configuration changed' using errcode='55000'; end if;
end $guard$;


-- Preserve existing records, private authorization and company rollout gates.
-- Manual visits use the same idempotent lifecycle with time-only metadata.
create or replace function private.route_journey_workspace(p_source_clock_in_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.attendance_verifications%rowtype; enabled boolean:=false; stops jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select a.* into s from public.attendance_verifications a join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
 where a.id=p_source_clock_in_id and a.event_type='clock_in' and a.site_id is null and a.route_assignment_id is not null
 and a.work_date is not null and w.user_id=auth.uid() and w.status='active'
 and exists(select 1 from public.company_members where company_id=a.company_id and user_id=auth.uid());
 if not found then raise exception 'actual personal route start required' using errcode='42501'; end if;
 enabled:=(s.verification_mode='manual' or (s.verification_mode='location_photo' and s.capture_contract_version=1
 and coalesce((public.get_attendance_capture_capability(s.company_id)->>'capture_enabled')::boolean,false)))
 and exists(select 1 from private.route_journey_rollouts r where r.company_id=s.company_id and r.enabled)
 and to_regprocedure('public.save_route_journey_capture(uuid,uuid,uuid,text,jsonb)') is not null
 and to_regprocedure('public.link_route_journey_report(uuid)') is not null
 and to_regprocedure('public.route_journey_report_evidence(uuid)') is not null
 and exists(select 1 from storage.buckets where id='attendance-route-evidence' and not public);
 select coalesce(jsonb_agg(jsonb_build_object('id',rs.id,'stop_order',rs.stop_order,'label',coalesce(rs.source_label,site.name,rs.address,'現場')) order by rs.stop_order,rs.id),'[]'::jsonb)
 into stops from public.route_stops rs left join public.sites site on site.id=rs.site_id where rs.route_assignment_id=s.route_assignment_id;
 return jsonb_build_object('version',1,'enabled',enabled,'source_clock_in_id',s.id,'company_id',s.company_id,'worker_id',s.worker_id,
 'verification_mode',s.verification_mode,'route_assignment_id',s.route_assignment_id,'work_date',s.work_date,'stops',case when enabled then stops else '[]'::jsonb end,
 'is_open',not exists(select 1 from public.attendance_verifications where source_clock_in_id=s.id and event_type='clock_out'),
 'origin_kind',(select origin_kind from private.route_journey_captures where source_clock_in_id=s.id order by recorded_at,id limit 1));
end $$;

create or replace function private.save_route_journey_capture(p_id uuid,p_source_clock_in_id uuid,p_route_stop_id uuid,p_origin_kind text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
 if s.verification_mode='manual' and (gps<>'missing' or photo<>'missing') then raise exception 'manual route visits require time only'; end if;
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
 values(p_id,s.company_id,s.id,s.worker_id,s.route_assignment_id,stop.id,stop.stop_order,coalesce(stop.source_label,(select name from public.sites where id=stop.site_id),stop.address,'現場'),s.work_date,p_origin_kind,auth.uid(),p_payload) returning * into old;
 return to_jsonb(old);
end $$;

create or replace function private.route_journey_live_visit_workspace(p_source_clock_in_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare ws jsonb; visits jsonb;
begin
 ws:=private.route_journey_workspace(p_source_clock_in_id);
 select coalesce(jsonb_agg(jsonb_build_object(
  'start_capture_id',s.capture_id,'route_stop_id',s.route_stop_id,
  'stop_label',c.stop_label,'work_date',c.work_date,
  'started_at',coalesce((c.payload->>'attempted_at')::timestamptz,c.recorded_at),
  'ended_at',coalesce((ec.payload->>'attempted_at')::timestamptz,ec.recorded_at),
  'end_capture_id',e.capture_id) order by c.recorded_at,c.id),'[]'::jsonb)
 into visits from private.route_journey_visit_events s
 join private.route_journey_captures c on c.id=s.capture_id
 left join private.route_journey_visit_events e on e.start_capture_id=s.capture_id and e.kind='end'
 left join private.route_journey_captures ec on ec.id=e.capture_id
 where s.source_clock_in_id=p_source_clock_in_id and s.kind='start';
 return ws||jsonb_build_object('visit_contract_version',1,'visits',visits);
end $$;

create or replace function private.route_journey_report_evidence(p_report_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.daily_reports%rowtype; result jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501'; end if;
 select * into d from public.daily_reports where id=p_report_id;
 if not found or not exists(select 1 from public.company_members where company_id=d.company_id and user_id=auth.uid()) then raise exception 'report unavailable' using errcode='42501'; end if;
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('worker_name',w.name,'visit_kind',e.kind,'start_capture_id',e.start_capture_id,'verification_mode',a.verification_mode) order by c.recorded_at,c.id),'[]'::jsonb) into result
 from private.route_journey_captures c join public.workers w on w.id=c.worker_id left join private.route_journey_visit_events e on e.capture_id=c.id join public.attendance_verifications a on a.id=c.source_clock_in_id where c.daily_report_id=d.id and (w.user_id=auth.uid() or private.has_company_feature(w.company_id,'can_manage_attendance'));
 return result;
end $$;
