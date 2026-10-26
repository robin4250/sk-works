-- Service-role RPC is available only to the trusted collector, never the decoy.
-- Registry is empty at installation. Root provisions separate collector keys later.
create table private.security_collector_keys(
 collector_id uuid not null,key_version integer not null check(key_version between 1 and 1000000),
 hmac_key bytea not null check(octet_length(hmac_key)=32),
 enabled boolean not null default false,revoked_at timestamptz,
 valid_from timestamptz not null,valid_until timestamptz not null,
 primary key(collector_id,key_version),
 check(isfinite(valid_from) and isfinite(valid_until) and valid_until>valid_from and valid_until<=valid_from+interval '180 days'),
 check(revoked_at is null or (isfinite(revoked_at) and not enabled))
);
create unique index security_collector_one_active_key on private.security_collector_keys(collector_id) where enabled and revoked_at is null;
create table private.security_collector_evidence(
 event_id uuid primary key references private.security_collector_events(event_id),
 collector_id uuid not null,key_version integer not null,
 transport_timestamp bigint not null check(transport_timestamp between 1000000000000 and 9999999999999),
 original_body bytea not null check(octet_length(original_body) between 1 and 1024),
 signature bytea not null check(octet_length(signature)=32),
 canonical_sha256 text not null check(canonical_sha256 ~ '^[0-9a-f]{64}$'),
 foreign key(collector_id,key_version) references private.security_collector_keys(collector_id,key_version)
);
create table private.security_collector_retention_audit(
 audit_id bigint generated always as identity primary key,
 ran_at timestamptz not null default clock_timestamp(),
 event_cutoff timestamptz not null,events_removed bigint not null check(events_removed>=0),
 reads_removed bigint not null check(reads_removed>=0),keys_removed bigint not null check(keys_removed>=0),retention_audits_removed bigint not null check(retention_audits_removed>=0),expired_event_set_sha256 text not null check(expired_event_set_sha256 ~ '^[0-9a-f]{64}$')
);
alter table private.security_collector_keys enable row level security;
alter table private.security_collector_evidence enable row level security;
alter table private.security_collector_retention_audit enable row level security;
revoke all on private.security_collector_keys,private.security_collector_evidence,private.security_collector_retention_audit from public,anon,authenticated,service_role;
revoke all on sequence private.security_collector_retention_audit_audit_id_seq from public,anon,authenticated,service_role;

create function private.collector_mac_equal(a bytea,b bytea) returns boolean language plpgsql immutable set search_path='' as $$
declare mismatch integer:=0;i integer;
begin
 if a is null or b is null or octet_length(a)<>32 or octet_length(b)<>32 then return false;end if;
 for i in 0..31 loop mismatch:=mismatch | (get_byte(a,i) # get_byte(b,i));end loop;
 return mismatch=0;
end $$;
revoke all on function private.collector_mac_equal(bytea,bytea) from public,anon,authenticated,service_role;

create function private.collector_event_metadata(e private.security_collector_events) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('event_id',e.event_id,'collector_id',e.collector_id,'occurred_at',to_char(e.occurred_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'event_kind',e.event_kind,'generation',e.generation,'correlation_key',e.correlation_key,'key_epoch',to_char(e.key_epoch,'YYYY-MM-DD'))
$$;
revoke all on function private.collector_event_metadata(private.security_collector_events) from public,anon,authenticated,service_role;

create function private.verify_collector_event_evidence(eid uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare e private.security_collector_events%rowtype;x private.security_collector_evidence%rowtype;k bytea;payload jsonb;expected bytea;
begin
 select * into e from private.security_collector_events where event_id=eid;if not found then return false;end if;
 select * into x from private.security_collector_evidence where event_id=eid;if not found then return false;end if;
 select hmac_key into k from private.security_collector_keys where collector_id=x.collector_id and key_version=x.key_version;if not found then return false;end if;
 payload:=convert_from(x.original_body,'UTF8')::jsonb;
 expected:=extensions.hmac(convert_to('sko-collector-v2'||chr(10)||x.collector_id::text||chr(10)||x.key_version::text||chr(10)||x.transport_timestamp::text||chr(10),'UTF8')||x.original_body,k,'sha256');
 -- Revoking an old key stops new ingress, not verification of its old evidence.
 return x.collector_id=e.collector_id and payload=private.collector_event_metadata(e)
  and x.canonical_sha256=encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex')
  and private.collector_mac_equal(expected,x.signature);
exception when others then return false;
end $$;
revoke all on function private.verify_collector_event_evidence(uuid) from public,anon,authenticated,service_role;

create function public.ingest_signed_security_collector_event(p_envelope jsonb) returns uuid language plpgsql volatile security definer set search_path='' set lock_timeout='1s' set statement_timeout='5s' as $$
declare cid uuid;version integer;stamp bigint;now_ms bigint;raw bytea;payload jsonb;original_json json;
 key_row private.security_collector_keys%rowtype;expected bytea;supplied bytea;eid uuid;recorded private.security_collector_evidence%rowtype;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'collector_unavailable' using errcode='42501';end if;
 perform 1 from private.security_collector_control where singleton and ingest_enabled for share;
 if not found then raise exception 'collector_unavailable' using errcode='55000';end if;
 if p_envelope is null or jsonb_typeof(p_envelope)<>'object' or octet_length(p_envelope::text)>2048
  or (select array_agg(k order by k) from jsonb_object_keys(p_envelope)k) is distinct from array['body_base64','collector_id','key_version','signature','timestamp']::text[]
  or jsonb_typeof(p_envelope->'collector_id') is distinct from 'string'
  or coalesce(p_envelope->>'collector_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or jsonb_typeof(p_envelope->'key_version') is distinct from 'number' or coalesce(p_envelope->>'key_version','') !~ '^[1-9][0-9]{0,6}$'
  or jsonb_typeof(p_envelope->'timestamp') is distinct from 'number' or coalesce(p_envelope->>'timestamp','') !~ '^[0-9]{13}$'
  or jsonb_typeof(p_envelope->'body_base64') is distinct from 'string' or coalesce(p_envelope->>'body_base64','') !~ '^[A-Za-z0-9+/]+={0,2}$'
  or length(p_envelope->>'body_base64')>1368 or length(p_envelope->>'body_base64')%4<>0
  or jsonb_typeof(p_envelope->'signature') is distinct from 'string' or coalesce(p_envelope->>'signature','') !~ '^[0-9a-f]{64}$'
 then raise exception 'collector_invalid_envelope' using errcode='22023';end if;
 cid:=(p_envelope->>'collector_id')::uuid;version:=(p_envelope->>'key_version')::integer;stamp:=(p_envelope->>'timestamp')::bigint;
 now_ms:=floor(extract(epoch from clock_timestamp())*1000)::bigint;
 if abs(now_ms-stamp)>60000 then raise exception 'collector_unavailable' using errcode='42501';end if;
 select * into key_row from private.security_collector_keys where collector_id=cid and key_version=version and enabled and revoked_at is null and valid_from<=clock_timestamp() and valid_until>clock_timestamp() for share;
 if not found then raise exception 'collector_unavailable' using errcode='42501';end if;
 raw:=decode(p_envelope->>'body_base64','base64');supplied:=decode(p_envelope->>'signature','hex');
 if octet_length(raw) not between 1 and 1024 or replace(encode(raw,'base64'),chr(10),'')<>p_envelope->>'body_base64' then raise exception 'collector_invalid_envelope' using errcode='22023';end if;
 expected:=extensions.hmac(convert_to('sko-collector-v2'||chr(10)||cid::text||chr(10)||version::text||chr(10)||stamp::text||chr(10),'UTF8')||raw,key_row.hmac_key,'sha256');
 if not private.collector_mac_equal(expected,supplied) then raise exception 'collector_unavailable' using errcode='42501';end if;
 original_json:=convert_from(raw,'UTF8')::json;
 if json_typeof(original_json) is distinct from 'object' or (select count(*) from json_each(original_json))<>7 then raise exception 'collector_invalid_metadata' using errcode='22023';end if;
 payload:=original_json::jsonb;
 if payload->>'collector_id' is distinct from cid::text then raise exception 'collector_invalid_metadata' using errcode='22023';end if;
 -- The existing unchanged strict seven-field validator owns idempotence/conflicts.
 eid:=private.ingest_security_collector_event(payload);
 insert into private.security_collector_evidence(event_id,collector_id,key_version,transport_timestamp,original_body,signature,canonical_sha256)
 values(eid,cid,version,stamp,raw,supplied,encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex')) on conflict(event_id) do nothing;
 select * into strict recorded from private.security_collector_evidence where event_id=eid;
 if recorded.canonical_sha256<>encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex') or not private.verify_collector_event_evidence(eid) then raise exception 'collector_evidence_conflict' using errcode='23505';end if;
 return eid;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or character_not_in_repertoire or untranslatable_character then
 raise exception 'collector_invalid_metadata' using errcode='22023';
end $$;
revoke all on function public.ingest_signed_security_collector_event(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.ingest_signed_security_collector_event(jsonb) to service_role;

-- Fixed owner-only expiry; no caller-selected deletion window or business tables.
create function private.purge_expired_security_collector_events() returns jsonb language plpgsql volatile security definer set search_path='' set lock_timeout='1s' set statement_timeout='5s' as $$
declare cutoff timestamptz:=clock_timestamp()-interval '7 days';removed bigint;reads_removed bigint;keys_removed bigint;audits_removed bigint;digest text;ids uuid[];
begin
 lock table private.security_collector_events,private.security_collector_evidence,private.security_collector_read_audit in share row exclusive mode;
 select coalesce(array_agg(event_id),'{}'::uuid[]) into ids from(select event_id from private.security_collector_events where received_at<cutoff order by received_at,event_id limit 1000)s;
 select encode(extensions.digest(convert_to(coalesce(string_agg(e.event_id::text||':'||coalesce(x.canonical_sha256,'evidence_missing'),',' order by e.event_id),''),'UTF8'),'sha256'),'hex') into digest
 from private.security_collector_events e left join private.security_collector_evidence x on x.event_id=e.event_id where e.event_id=any(ids);
 delete from private.security_collector_events e left join private.security_collector_evidence x on x.event_id=e.event_id where e.event_id=any(ids);
 delete from private.security_collector_events where event_id=any(ids);get diagnostics removed=row_count;
 delete from private.security_collector_read_audit where audit_id in(select audit_id from private.security_collector_read_audit where read_at<clock_timestamp()-interval '90 days' order by audit_id limit 1000);get diagnostics reads_removed=row_count;
 delete from private.security_collector_keys k where(k.collector_id,k.key_version)in(select collector_id,key_version from private.security_collector_keys old where((revoked_at is not null and revoked_at<cutoff)or valid_until<cutoff)and not exists(select 1 from private.security_collector_evidence e where e.collector_id=old.collector_id and e.key_version=old.key_version)order by collector_id,key_version limit 1000);get diagnostics keys_removed=row_count;
 delete from private.security_collector_retention_audit where audit_id in(select audit_id from private.security_collector_retention_audit where ran_at<clock_timestamp()-interval '365 days' order by audit_id limit 1000);get diagnostics audits_removed=row_count;
 insert into private.security_collector_retention_audit(event_cutoff,events_removed,reads_removed,keys_removed,retention_audits_removed,expired_event_set_sha256)values(cutoff,removed,reads_removed,keys_removed,audits_removed,digest);
 return jsonb_build_object('events_removed',removed,'reads_removed',reads_removed,'keys_removed',keys_removed,'retention_audits_removed',audits_removed,'event_cutoff',cutoff,'batch_limit',1000);
end $$;
revoke all on function private.purge_expired_security_collector_events() from public,anon,authenticated,service_role;
