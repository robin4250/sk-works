-- Operator imports sanitized synthetic records. No automatic decoy -> production connection.
create table private.security_incident_records (
 incident_id uuid not null, record_version integer not null check(record_version between 1 and 16), primary key(incident_id,record_version), company_id uuid not null references public.companies(id),
 recipient_user_id uuid not null references auth.users(id), correlation_id uuid not null,
 record jsonb not null, source text not null default 'synthetic_fixture' check(source='synthetic_fixture'),
 saved_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null default clock_timestamp()+interval '7 days'
);
create index security_incident_recipient_time on private.security_incident_records(recipient_user_id,company_id,saved_at desc);
create table private.security_incident_notification_outbox (
 incident_id uuid primary key, record_version integer not null default 1 check(record_version=1),
 foreign key(incident_id,record_version) references private.security_incident_records(incident_id,record_version) on delete cascade,
 recipient_user_id uuid not null references auth.users(id), notification_id uuid not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table private.security_incident_records enable row level security;
alter table private.security_incident_notification_outbox enable row level security;
revoke all on private.security_incident_records,private.security_incident_notification_outbox from public,anon,authenticated,service_role;
create function private.security_incident_actor_company() returns uuid language plpgsql stable security definer set search_path='' as $$
declare cid uuid;n integer;
begin
 if auth.uid() is null or private.account_access_allowed() is not true or public.is_current_user_master_admin() is not true then raise exception 'security record unavailable';end if;
 select count(*),(array_agg(company_id))[1] into n,cid from public.company_members where user_id=auth.uid();
 if n<>1 then raise exception 'security record unavailable';end if;return cid;
end $$;
create function private.save_security_incident_record(p_record jsonb,p_record_version integer) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid;iid uuid;corr uuid;existing private.security_incident_records%rowtype;e jsonb;dt timestamptz;wf timestamptz;wt timestamptz;et timestamptz;previous timestamptz;n integer:=0;notification uuid;max_version integer;
begin
 cid:=private.security_incident_actor_company();
 if p_record_version is null or p_record_version not between 1 and 16 then raise exception 'invalid record version';end if;
 if p_record is null or jsonb_typeof(p_record)<>'object' or octet_length(p_record::text)>65536 or
 (select array_agg(k order by k) from jsonb_object_keys(p_record) k) is distinct from array['collection_status','correlation_id','detected_at','event_count','events','first_seen','incident_id','last_seen','missing_after','missing_before','source_tracking','status','window_from','window_to']::text[] then raise exception 'invalid security record';end if;
 if not (p_record ?& array['incident_id','correlation_id','detected_at','window_from','window_to','status','collection_status','source_tracking','missing_before','missing_after','events','event_count','first_seen','last_seen']) or exists(select 1 from jsonb_each(p_record) where value='null'::jsonb and key not in ('first_seen','last_seen')) then raise exception 'missing security fields';end if;
 if exists(select 1 from jsonb_each(p_record) where key in ('detected_at','window_from','window_to','first_seen','last_seen') and value<>'null'::jsonb and (jsonb_typeof(value)<>'string' or value#>>'{}' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')) or jsonb_typeof(p_record->'event_count')<>'number' or p_record->>'event_count' !~ '^(0|[1-9][0-9]*)$' then raise exception 'invalid metadata types';end if;
 if p_record->>'incident_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or p_record->>'correlation_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'invalid security identifier';end if;
 iid:=(p_record->>'incident_id')::uuid;corr:=(p_record->>'correlation_id')::uuid;
 dt:=(p_record->>'detected_at')::timestamptz;wf:=(p_record->>'window_from')::timestamptz;wt:=(p_record->>'window_to')::timestamptz;
 if iid is null or corr is null or not isfinite(dt) or not isfinite(wf) or not isfinite(wt) or wf>dt or dt>wt or wt-wf>interval '20 minutes' or wt>clock_timestamp() or dt<clock_timestamp()-interval '7 days' or
 p_record->>'status' is distinct from 'detected' or p_record->>'collection_status' not in ('complete','partial') or p_record->>'source_tracking' not in ('unavailable','synthetic_pseudonym') or
 jsonb_typeof(p_record->'missing_before')<>'boolean' or p_record->'missing_after' is distinct from 'false'::jsonb or
 (p_record->>'collection_status'='complete' and p_record->'missing_before' is distinct from 'false'::jsonb) or
 jsonb_typeof(p_record->'events')<>'array' or jsonb_array_length(p_record->'events') not between 0 and 128 then raise exception 'invalid security record';end if;
 for e in select value from jsonb_array_elements(p_record->'events') loop
  n:=n+1;
  if exists(select 1 from jsonb_each(e) where value='null'::jsonb and key<>'generation') then raise exception 'missing event fields';end if;
  if jsonb_typeof(e)<>'object' or (select array_agg(k order by k) from jsonb_object_keys(e) k) is distinct from array['at','generation','kind','sequence']::text[] or
   e->>'kind' not in ('current_lure_touched','retired_lure_touched') or (e->>'sequence')::integer<>n or
   (e->'generation'<>'null'::jsonb and ((e->>'generation')::integer not between 1 and 1000000)) then raise exception 'invalid security event';end if;
  if jsonb_typeof(e->'at')<>'string' or e->>'at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$' or jsonb_typeof(e->'sequence')<>'number' or e->>'sequence' !~ '^[1-9][0-9]*$' or (e->'generation'<>'null'::jsonb and (jsonb_typeof(e->'generation')<>'number' or e->>'generation' !~ '^[1-9][0-9]*$')) then raise exception 'invalid event metadata types';end if;
  et:=(e->>'at')::timestamptz;
  if not isfinite(et) or et<wf or et>wt or (previous is not null and et<previous) then raise exception 'invalid event order';end if;previous:=et;
 end loop;
 if n=0 and p_record->'missing_before' is distinct from 'true'::jsonb then raise exception 'empty coverage must be explicit';end if;
 if (p_record->>'event_count')::integer<>n or (p_record->>'first_seen')::timestamptz is distinct from (p_record->'events'->0->>'at')::timestamptz or (p_record->>'last_seen')::timestamptz is distinct from previous then raise exception 'invalid event summary';end if;
 -- Company serialization provides a bounded per-owner store and avoids duplicate notification races.
 perform 1 from public.companies where id=cid for update;
 select * into existing from private.security_incident_records where incident_id=iid and record_version=p_record_version;
 if found then
  if existing.company_id<>cid or existing.recipient_user_id<>auth.uid() or existing.record is distinct from p_record then raise exception 'security record conflict';end if;return iid;
 end if;
 select max(record_version) into max_version from private.security_incident_records where incident_id=iid;
 if coalesce(max_version,0)+1<>p_record_version then raise exception 'security record version conflict';end if;
 if max_version is not null and not exists(select 1 from private.security_incident_records where incident_id=iid and company_id=cid and recipient_user_id=auth.uid() and correlation_id=corr and record->>'detected_at'=p_record->>'detected_at' and record->>'window_from'=p_record->>'window_from' and record->>'window_to'=p_record->>'window_to') then raise exception 'security record conflict';end if;
 delete from private.security_incident_records where company_id=cid and recipient_user_id=auth.uid() and expires_at<=clock_timestamp();
 if (select count(distinct incident_id) from private.security_incident_records where company_id=cid and recipient_user_id=auth.uid())>=100 and max_version is null then raise exception 'security record capacity';end if;
 insert into private.security_incident_records(incident_id,record_version,company_id,recipient_user_id,correlation_id,record) values(iid,p_record_version,cid,auth.uid(),corr,p_record);
 if p_record_version=1 then
 notification:=private.enqueue_notification(cid,auth.uid(),'security_incident','セキュリティ記録を保存しました','検知記録です。攻撃確定とは限りません。','master_security_incident',iid);
 insert into private.security_incident_notification_outbox(incident_id,recipient_user_id,notification_id) values(iid,auth.uid(),notification);
 end if;
 return iid;
exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format or numeric_value_out_of_range then
 raise exception 'invalid security record' using errcode='22023';
end $$;
create function private.read_security_incident_records() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin
 cid:=private.security_incident_actor_company();
 return jsonb_build_object('version',1,'incidents',coalesce((select jsonb_agg(record||jsonb_build_object('record_version',record_version,'saved_at',to_char(saved_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'source_provenance','synthetic_fixture','correlation_confidence',case when record->>'source_tracking'='unavailable' then 'unavailable' else 'synthetic_source_only' end,'reason_code','decoy_lure_touched','timezone','UTC','audit',(select jsonb_agg(jsonb_build_object('action','imported','at',to_char(a.saved_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'operator','self_master','record_version',a.record_version) order by a.record_version) from private.security_incident_records a where a.incident_id=x.incident_id and a.company_id=cid and a.recipient_user_id=auth.uid())) order by saved_at desc,incident_id) from (select distinct on(incident_id) * from private.security_incident_records where company_id=cid and recipient_user_id=auth.uid() and expires_at>now() order by incident_id,record_version desc)x),'[]'::jsonb));
end $$;
create function public.save_master_security_incident(p_record jsonb,p_record_version integer default 1) returns uuid language sql security invoker set search_path='' as $$select private.save_security_incident_record(p_record,p_record_version)$$;
create function public.master_security_incidents() returns jsonb language sql stable security invoker set search_path='' as $$select private.read_security_incident_records()$$;
revoke all on function private.security_incident_actor_company(),private.save_security_incident_record(jsonb,integer),private.read_security_incident_records(),public.save_master_security_incident(jsonb,integer),public.master_security_incidents() from public,anon,authenticated,service_role;
grant usage on schema private to authenticated;
grant execute on function private.save_security_incident_record(jsonb,integer),private.read_security_incident_records(),public.save_master_security_incident(jsonb,integer),public.master_security_incidents() to authenticated;

