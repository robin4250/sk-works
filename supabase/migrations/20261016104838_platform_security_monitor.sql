-- Staged default-OFF foundation. No production apply is authorized by this file.
-- Requires authentication lane private.consume_reauthentication_proof(text,jsonb,text).
create table private.platform_monitor_control (
 singleton boolean primary key default true check(singleton), enabled boolean not null default false
);
insert into private.platform_monitor_control(singleton) values(true);
create table private.platform_monitor_windows (
 source text not null check(source in ('edge_logs','postgres_logs','auth_audit_logs')),
 window_from timestamptz not null, window_to timestamptz not null,
 key_epoch integer not null check(key_epoch between 1 and 1000000),
 coverage text not null check(coverage in ('bounded_query','capacity_limited')),
 event_count integer not null check(event_count between 0 and 1000),
 batch_digest text not null,
 saved_at timestamptz not null default clock_timestamp(),
 primary key(source,window_from,window_to,key_epoch),
 check(window_to>window_from and window_to-window_from<=interval '15 minutes')
);
create table private.platform_monitor_events (
 source text not null, key_epoch integer not null,
 event_key text not null check(event_key ~ '^[0-9a-f]{64}$'),
 occurred_at timestamptz not null,
 result text not null check(result in ('unknown','http_success','unauthenticated','forbidden','rate_limited','server_error','permission_denied')),
 target_key text check(target_key ~ '^[0-9a-f]{64}$'),
 source_key text check(source_key is null),
 source_tracking text not null check(source_tracking='unavailable'),
 saved_at timestamptz not null default clock_timestamp(),
 primary key(source,key_epoch,event_key)
);
create index platform_monitor_events_date_idx on private.platform_monitor_events(occurred_at desc);
alter table private.platform_monitor_control enable row level security;
alter table private.platform_monitor_windows enable row level security;
alter table private.platform_monitor_events enable row level security;
revoke all on private.platform_monitor_control, private.platform_monitor_windows, private.platform_monitor_events from public,anon,authenticated,service_role;

create function private.ingest_platform_monitor_batch(p_batch jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare s text; wf timestamptz; wt timestamptz; epoch integer; coverage text; e jsonb; at_time timestamptz; old private.platform_monitor_events%rowtype; old_window private.platform_monitor_windows%rowtype; n integer:=0;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'platform monitoring unavailable' using errcode='42501';end if;
 -- Serialize toggle, retention and capacity in the same transaction, never business rows.
 perform 1 from private.platform_monitor_control where singleton and enabled for update;
 if not found then raise exception 'platform monitoring disabled' using errcode='55000';end if;
 if p_batch is null or jsonb_typeof(p_batch)<>'object' or octet_length(p_batch::text)>262144 or
 (select array_agg(k order by k) from jsonb_object_keys(p_batch) k) is distinct from array['coverage','events','key_epoch','source','window_from','window_to']::text[] then raise exception 'invalid platform batch';end if;
 if jsonb_typeof(p_batch->'source')<>'string' or jsonb_typeof(p_batch->'window_from')<>'string' or jsonb_typeof(p_batch->'window_to')<>'string' or jsonb_typeof(p_batch->'coverage')<>'string' or jsonb_typeof(p_batch->'key_epoch')<>'number' or p_batch->>'key_epoch' !~ '^[1-9][0-9]{0,6}$' or jsonb_typeof(p_batch->'events')<>'array' then raise exception 'invalid platform batch';end if;
 s:=p_batch->>'source';wf:=(p_batch->>'window_from')::timestamptz;wt:=(p_batch->>'window_to')::timestamptz;epoch:=(p_batch->>'key_epoch')::integer;coverage:=p_batch->>'coverage';
 if s not in ('edge_logs','postgres_logs','auth_audit_logs') or epoch not between 1 and 1000000 or coverage not in ('bounded_query','capacity_limited') or not isfinite(wf) or not isfinite(wt) or wt<=wf or wt-wf>interval '15 minutes' or wt>clock_timestamp() or wf<clock_timestamp()-interval '7 days' or jsonb_array_length(p_batch->'events')>1000 then raise exception 'invalid platform batch';end if;
 -- Reject duplicate IDs and exact conflicting replays, including omitted/extra events.
 if (select count(distinct value->>'event_key') from jsonb_array_elements(p_batch->'events'))<>jsonb_array_length(p_batch->'events') then raise exception 'invalid platform batch';end if;
 select * into old_window from private.platform_monitor_windows where source=s and window_from=wf and window_to=wt and key_epoch=epoch;
 if found and (old_window.coverage<>coverage or old_window.event_count<>jsonb_array_length(p_batch->'events') or old_window.batch_digest<>encode(sha256(convert_to(p_batch::text,'UTF8')),'hex')) then raise exception 'platform batch conflict' using errcode='40001';end if;
 for e in select value from jsonb_array_elements(p_batch->'events') loop
  if jsonb_typeof(e)<>'object' or (select array_agg(k order by k) from jsonb_object_keys(e) k) is distinct from array['event_key','occurred_at','result','source_key','source_tracking','target_key']::text[] or jsonb_typeof(e->'event_key')<>'string' or e->>'event_key' !~ '^[0-9a-f]{64}$' or jsonb_typeof(e->'occurred_at')<>'string' or jsonb_typeof(e->'result')<>'string' or e->>'result' not in ('unknown','http_success','unauthenticated','forbidden','rate_limited','server_error','permission_denied') or (e->'target_key'<>'null'::jsonb and (jsonb_typeof(e->'target_key')<>'string' or e->>'target_key' !~ '^[0-9a-f]{64}$')) or e->'source_key' is distinct from 'null'::jsonb or e->>'source_tracking' is distinct from 'unavailable' then raise exception 'invalid platform event';end if;
  at_time:=(e->>'occurred_at')::timestamptz;
  if not isfinite(at_time) or at_time<wf or at_time>=wt or (s='auth_audit_logs' and (e->>'result'<>'unknown' or e->'target_key'<>'null'::jsonb)) or (s='postgres_logs' and (e->>'result' not in ('unknown','permission_denied') or e->'target_key'<>'null'::jsonb)) or (s='edge_logs' and e->>'result'='permission_denied') then raise exception 'invalid platform event';end if;
  select * into old from private.platform_monitor_events where source=s and key_epoch=epoch and event_key=e->>'event_key';
  if found then
   if old.occurred_at<>at_time or old.result<>e->>'result' or old.target_key is distinct from e->>'target_key' then raise exception 'platform event conflict' using errcode='40001';end if;
  else
   if old_window.source is not null then raise exception 'platform batch conflict' using errcode='40001';end if;
   insert into private.platform_monitor_events(source,key_epoch,event_key,occurred_at,result,target_key,source_key,source_tracking) values(s,epoch,e->>'event_key',at_time,e->>'result',e->>'target_key',null,'unavailable');
  end if;
  n:=n+1;
 end loop;
 -- Expiry is explicit, old windows are never reported as continuous coverage.
 delete from private.platform_monitor_events where occurred_at<clock_timestamp()-interval '7 days';
 delete from private.platform_monitor_windows where window_to<clock_timestamp()-interval '7 days';
 if (select count(*) from private.platform_monitor_events)>10000 or (select count(*) from private.platform_monitor_windows)>1000 then raise exception 'platform capacity exhausted' using errcode='54000';end if;
 insert into private.platform_monitor_windows(source,window_from,window_to,key_epoch,coverage,event_count,batch_digest) values(s,wf,wt,epoch,coverage,n,encode(sha256(convert_to(p_batch::text,'UTF8')),'hex')) on conflict do nothing;
 return n;
exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format or numeric_value_out_of_range then raise exception 'invalid platform batch' using errcode='22023';
end $$;
revoke all on function private.ingest_platform_monitor_batch(jsonb) from public,anon,authenticated,service_role;
grant execute on function private.ingest_platform_monitor_batch(jsonb) to service_role;
create function public.service_ingest_platform_monitor(p_batch jsonb) returns integer language sql set search_path='' as $$select private.ingest_platform_monitor_batch(p_batch)$$;
revoke all on function public.service_ingest_platform_monitor(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.service_ingest_platform_monitor(jsonb) to service_role;

create function private.read_platform_monitor(p_proof text) returns jsonb language plpgsql security definer set search_path='' as $$
declare report jsonb;
begin
 if auth.uid() is null or private.account_access_allowed() is not true or public.is_current_user_master_admin() is not true then raise exception 'platform monitoring unavailable' using errcode='42501';end if;
 perform 1 from private.platform_monitor_control where singleton and enabled for share;
 if not found then raise exception 'platform monitoring disabled' using errcode='55000';end if;
 -- No company_id parameter: platform-wide service evidence is never attributed
 -- to a tenant inferred from a path/JWT/body. Only enabled platform master reads.
 perform private.consume_reauthentication_proof('master.security_incidents.read','{"scope":"platform"}'::jsonb,p_proof);
 select jsonb_build_object('version',1,'source_provenance','supabase_platform_logs','scope','platform_operator','retention_days',7,'coverage','bounded_queries_not_continuous_monitoring',
 'events',coalesce((select jsonb_agg(x) from (select source,key_epoch,event_key,occurred_at,result,target_key,source_key,source_tracking from private.platform_monitor_events where occurred_at>=clock_timestamp()-interval '7 days' order by occurred_at desc,source,event_key limit 100)x),'[]'::jsonb),
 'windows',coalesce((select jsonb_agg(x) from (select source,window_from,window_to,key_epoch,coverage,event_count from private.platform_monitor_windows where window_to>=clock_timestamp()-interval '7 days' order by window_to desc,source limit 100)x),'[]'::jsonb)) into report;
 return report;
end $$;
revoke all on function private.read_platform_monitor(text) from public,anon,authenticated,service_role;
grant execute on function private.read_platform_monitor(text) to authenticated;
create function public.master_platform_security_monitor(p_proof text) returns jsonb language sql set search_path='' as $$select private.read_platform_monitor(p_proof)$$;
revoke all on function public.master_platform_security_monitor(text) from public,anon,authenticated,service_role;
grant execute on function public.master_platform_security_monitor(text) to authenticated;
-- Intentionally no rollout setter, cron, ingress, notification, synthetic changes,
-- Management API token provisioning, direct grants, or existing table/function rewrites.
