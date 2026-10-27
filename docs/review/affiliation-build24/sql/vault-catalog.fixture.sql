-- Isolated candidate, not a migration. Master guard PR1483 is a prerequisite.
-- No executable write grants to application roles or service_role.
begin;
create schema personal_vault24_candidate;
revoke all on schema personal_vault24_candidate from public,anon,authenticated,service_role;
create table personal_vault24_candidate.manifests(
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete restrict,
 source_company_id uuid not null, source_worker_id uuid not null,
 transition_request_id uuid not null, snapshot_hash text not null check(snapshot_hash ~ '^[a-f0-9]{64}$'),
 manifest_hash text not null check(manifest_hash ~ '^[a-f0-9]{64}$'),
 expected_count integer not null check(expected_count between 1 and 10000),
 status text not null default 'pending' check(status in ('pending','complete')),
 created_at timestamptz not null default now(),completed_at timestamptz,
 unique(owner_id,transition_request_id),
 check((status='complete')=(completed_at is not null))
);
create table personal_vault24_candidate.items(
 manifest_id uuid not null references personal_vault24_candidate.manifests(id) on delete restrict,
 artifact_key text not null check(artifact_key ~ '^[a-f0-9]{64}$'),
 kind text not null check(kind in ('own_attendance','own_payroll')),
 source_id uuid not null, source_revision text not null,
 snapshot_hash text not null check(snapshot_hash ~ '^[a-f0-9]{64}$'),
 object_path text not null check(object_path ~ '^personal-vault/[a-f0-9-]+/[a-f0-9]{64}\.pdf$'),
 object_version text not null check(length(object_version) between 1 and 256),
 pdf_hash text not null check(pdf_hash ~ '^[a-f0-9]{64}$'), byte_length bigint not null check(byte_length between 1 and 52428800),
 primary key(manifest_id,artifact_key),unique(manifest_id,kind,source_id)
);
alter table personal_vault24_candidate.manifests enable row level security;
alter table personal_vault24_candidate.items enable row level security;
revoke all on all tables in schema personal_vault24_candidate from public,anon,authenticated,service_role;

create function personal_vault24_candidate.assert_owner(p personal_vault24_candidate.manifests)
returns void language plpgsql security invoker set search_path='' as $$
begin
 perform private.require_reauthentication_session();
 if auth.uid() is null or auth.uid() is distinct from p.owner_id then raise exception 'vault_owner_rejected' using errcode='42501';end if;
end $$;

-- Called only by trusted source-inventory exporter; never client-supplied inventory.
create function personal_vault24_candidate.start_manifest(
 mid uuid,cid uuid,wid uuid,rid uuid,snapshot text,manifest text,n integer)
returns uuid language plpgsql security invoker set search_path='' as $$
declare old personal_vault24_candidate.manifests; actor uuid:=auth.uid();
begin
 perform private.require_lifecycle_features(array['personal_pdf_vault']);
 perform private.require_reauthentication_session();
 if actor is null then raise exception 'vault_owner_rejected' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||rid::text,0));
 select * into old from personal_vault24_candidate.manifests where owner_id=actor and transition_request_id=rid for update;
 if found then
  if (old.source_company_id,old.source_worker_id,old.snapshot_hash,old.manifest_hash,old.expected_count) is distinct from (cid,wid,snapshot,manifest,n) then raise exception 'vault_retry_conflict';end if;
  return old.id;
 end if;
 insert into personal_vault24_candidate.manifests(id,owner_id,source_company_id,source_worker_id,transition_request_id,snapshot_hash,manifest_hash,expected_count)
 values(mid,actor,cid,wid,rid,snapshot,manifest,n);return mid;
end $$;

-- Trusted inspector supplies a verified immutable PDF receipt. It must authenticate
-- owner and verify source inventory/bytes before calling; no external EXECUTE grant.
create function personal_vault24_candidate.record_item(mid uuid,artifact text,k text,sid uuid,rev text,sh text,path text,version text,ph text,bytes bigint)
returns void language plpgsql security invoker set search_path='' as $$
declare m personal_vault24_candidate.manifests;old personal_vault24_candidate.items;
begin
 perform private.require_lifecycle_features(array['personal_pdf_vault']);
 select * into m from personal_vault24_candidate.manifests where id=mid for update;
 if not found then raise exception 'vault_not_found';end if;
 perform personal_vault24_candidate.assert_owner(m);
 select * into old from personal_vault24_candidate.items where manifest_id=mid and artifact_key=artifact;
 if found then
  if (old.kind,old.source_id,old.source_revision,old.snapshot_hash,old.object_path,old.object_version,old.pdf_hash,old.byte_length) is distinct from (k,sid,rev,sh,path,version,ph,bytes) then raise exception 'vault_receipt_conflict';end if;
  return;
 end if;
 if m.status<>'pending' then raise exception 'vault_immutable';end if;
 if path is distinct from 'personal-vault/'||m.owner_id::text||'/'||artifact||'.pdf' then raise exception 'vault_path_rejected';end if;
 insert into personal_vault24_candidate.items values(mid,artifact,k,sid,rev,sh,path,version,ph,bytes);
end $$;

create function personal_vault24_candidate.seal_manifest(mid uuid,expected_keys text[])
returns void language plpgsql security invoker set search_path='' as $$
declare m personal_vault24_candidate.manifests;actual text[];expected text[];
begin
 perform private.require_lifecycle_features(array['personal_pdf_vault']);
 select * into m from personal_vault24_candidate.manifests where id=mid for update;
 if not found then raise exception 'vault_not_found';end if;
 perform personal_vault24_candidate.assert_owner(m);
 select array_agg(artifact_key order by artifact_key) into actual from personal_vault24_candidate.items where manifest_id=mid;
 select array_agg(x order by x) into expected from unnest(expected_keys)x;
 if cardinality(expected_keys) is distinct from m.expected_count or actual is distinct from expected then raise exception 'vault_incomplete';end if;
 update personal_vault24_candidate.manifests set status='complete',completed_at=coalesce(completed_at,now()) where id=mid;
end $$;

create function personal_vault24_candidate.assert_transition_ready(mid uuid,owner_id uuid,cid uuid,wid uuid,rid uuid,sh text)
returns void language plpgsql security invoker set search_path='' as $$
declare m personal_vault24_candidate.manifests;
begin
 perform private.require_lifecycle_features(array['personal_pdf_vault']);
 select * into m from personal_vault24_candidate.manifests where id=mid for update;
 if not found then raise exception 'vault_not_found';end if;
 perform personal_vault24_candidate.assert_owner(m);
 if m.status<>'complete' or (m.owner_id,m.source_company_id,m.source_worker_id,m.transition_request_id,m.snapshot_hash) is distinct from (owner_id,cid,wid,rid,sh) then raise exception 'vault_transition_rejected';end if;
end $$;

-- Read RPC candidate: sessions are checked at each invocation and source-company
-- membership is deliberately not used after the person's verified departure.
create function personal_vault24_candidate.list_mine()
returns table(manifest_id uuid,source_company_id uuid,status text,completed_at timestamptz)
language plpgsql security definer set search_path='' as $$
begin
 perform private.require_reauthentication_session();
 if auth.uid() is null then raise exception 'vault_owner_rejected' using errcode='42501';end if;
 return query select m.id,m.source_company_id,m.status,m.completed_at from personal_vault24_candidate.manifests m where m.owner_id=auth.uid() order by m.created_at,m.id;
end $$;
create function personal_vault24_candidate.item_for_owner(mid uuid,artifact text)
returns table(object_path text,object_version text,pdf_hash text,byte_length bigint)
language plpgsql security definer set search_path='' as $$
declare m personal_vault24_candidate.manifests;
begin
 select * into m from personal_vault24_candidate.manifests where id=mid;
 if not found then raise exception 'vault_not_found';end if;
 perform personal_vault24_candidate.assert_owner(m);
 if m.status<>'complete' then raise exception 'vault_not_complete';end if;
 return query select i.object_path,i.object_version,i.pdf_hash,i.byte_length from personal_vault24_candidate.items i where i.manifest_id=mid and i.artifact_key=artifact;
end $$;
revoke all on all functions in schema personal_vault24_candidate from public,anon,authenticated,service_role;
-- No schema usage or RPC exposure yet. Root must separately review authenticated
-- EXECUTE on read-only APIs and immutable Storage download ownership/expiry.
commit;
