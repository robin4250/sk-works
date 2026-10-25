-- REVIEW ONLY. Default OFF. Do not apply/enable before Edge+client rollout review.
begin;
create table private.reauthentication_rollout (
  scope text primary key check (scope in ('secondary_password','master_feature','master_security')),
  enabled boolean not null default false
);
insert into private.reauthentication_rollout(scope) values ('secondary_password'),('master_feature'),('master_security');
alter table private.reauthentication_rollout enable row level security;
revoke all on private.reauthentication_rollout from public,anon,authenticated;

create table private.reauthentication_proofs (
  proof_hash text primary key check (proof_hash ~ '^[0-9a-f]{64}$'),
  actor_id uuid not null,
  session_id uuid not null,
  operation text not null,
  target jsonb not null,
  issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  secondary_credential_fingerprint text,
  check (expires_at > issued_at and expires_at <= issued_at + interval '120 seconds')
);
alter table private.reauthentication_proofs enable row level security;
revoke all on private.reauthentication_proofs from public,anon,authenticated;

create function private.reauthentication_scope(p_operation text) returns text
language sql immutable set search_path='' as $$
 select case p_operation when 'secondary_password.replace' then 'secondary_password'
  when 'secondary_password.change' then 'secondary_password'
  when 'master.feature.set' then 'master_feature'
  when 'master.security_incidents.read' then 'master_security' end
$$;
revoke all on function private.reauthentication_scope(text) from public,anon,authenticated;

create function private.reauthentication_required(p_scope text) returns boolean
language plpgsql security definer set search_path='' as $$
declare required boolean;
begin
 select enabled into required from private.reauthentication_rollout where scope=p_scope for share;
 if not found then raise sqlstate '42501' using message='reauthentication_unavailable'; end if;
 return required;
end $$;
revoke all on function private.reauthentication_required(text) from public,anon,authenticated;

-- Sensitive clients must present a live, non-anonymous, non-banned account/session.
-- JWT validity at the API gateway is not a post-signout guarantee.
create function private.require_reauthentication_session() returns uuid
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();sid uuid;
begin
 if actor is null or auth.jwt()->>'role' is distinct from 'authenticated'
  or coalesce(auth.jwt()->>'is_anonymous','false')<>'false'
  or not private.account_access_allowed() then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 begin sid:=(auth.jwt()->>'session_id')::uuid;
 exception when invalid_text_representation then raise sqlstate '42501' using message='reauthentication_required';end;
 if sid is null or not pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(actor)) then
  raise sqlstate '42501' using message='reauthentication_required';end if;
 perform 1 from auth.users where id=actor and not coalesce(is_anonymous,false)
  and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 perform 1 from auth.sessions where id=sid and user_id=actor
  and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 return sid;
end $$;
revoke all on function private.require_reauthentication_session() from public,anon,authenticated,service_role;

create function public.reauthentication_capabilities() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform private.require_reauthentication_session();
 return jsonb_build_object('protocol','sko-reauthentication-v1',
  'secondary_password',private.reauthentication_required('secondary_password'),
  'secondary_password_change_supported',private.reauthentication_required('secondary_password') and exists(select 1 from public.user_secondary_credentials where user_id=auth.uid()),
  'secondary_password_recovery_supported',private.reauthentication_required('secondary_password') and exists(select 1 from auth.users where id=auth.uid() and coalesce(encrypted_password,'')<>''),
  'master_feature',private.reauthentication_required('master_feature'),
  'master_security',private.reauthentication_required('master_security'));
end $$;
revoke all on function public.reauthentication_capabilities() from public,anon;
grant execute on function public.reauthentication_capabilities() to authenticated;

-- Only the credential-verifying Edge service may issue proofs. No user RPC
-- accepts a boolean, JWT refresh timestamp, client actor or biometric assertion.
create function private.issue_reauthentication_proof(
 p_actor uuid,p_session uuid,p_operation text,p_target jsonb,p_proof_hash text
) returns timestamptz language plpgsql security definer set search_path='' as $$
declare expiry timestamptz; issued timestamptz;fingerprint text;
begin
 if p_actor is null or p_session is null
  or p_proof_hash is null or p_proof_hash !~ '^[0-9a-f]{64}$'
  or private.reauthentication_scope(p_operation) is null
  or not private.reauthentication_required(private.reauthentication_scope(p_operation)) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 if p_operation in('secondary_password.replace','secondary_password.change') and p_target<>jsonb_build_object('user_id',p_actor) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 elsif p_operation='master.feature.set' and (
  jsonb_typeof(p_target)<>'object' or p_target<>jsonb_build_object('feature_key',p_target->'feature_key','enabled',p_target->'enabled')
  or coalesce(p_target->>'feature_key','') not in ('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop')
  or coalesce(jsonb_typeof(p_target->'enabled'),'')<>'boolean') then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 elsif p_operation='attendance.manage' and (
  not private.reauthentication_required('secondary_password') or
  p_target is null or jsonb_typeof(p_target)<>'object'
  or p_target<>jsonb_build_object('company_id',p_target->'company_id','action',p_target->'action','items_sha256',p_target->'items_sha256')
  or coalesce(p_target->>'action','') not in ('upsert','delete')
  or coalesce(p_target->>'items_sha256','') !~ '^[0-9a-f]{64}$'
  or (select count(*) from public.company_members where user_id=p_actor)<>1
  or not exists(select 1 from public.company_members where user_id=p_actor
   and company_id::text=p_target->>'company_id' and role::text in ('owner','admin','manager'))) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 elsif p_operation='master.security_incidents.read' and p_target<>'{"scope":"platform"}'::jsonb then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 if p_target is null or (p_operation like 'master.%' and not exists(
  select 1 from private.master_admins where user_id=p_actor and enabled)) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 -- Same deletion barrier as the existing Data API account hook; fail closed.
 if not pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(p_actor)) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 if exists(select 1 from private.account_deletion_access_restrictions where user_id=p_actor) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 perform 1 from auth.users where id=p_actor and not coalesce(is_anonymous,false)
  and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_unavailable';end if;
 perform 1 from auth.sessions where id=p_session and user_id=p_actor
  and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_unavailable'; end if;
 if p_operation in('secondary_password.change','attendance.manage') then
  select encode(extensions.digest(password_hash,'sha256'),'hex') into fingerprint
  from public.user_secondary_credentials where user_id=p_actor for share;
  if not found then raise sqlstate '42501' using message='reauthentication_unavailable';end if;
 end if;
 issued:=clock_timestamp(); expiry:=issued+interval '120 seconds';
 insert into private.reauthentication_proofs(proof_hash,actor_id,session_id,operation,target,issued_at,expires_at,secondary_credential_fingerprint)
 values(p_proof_hash,p_actor,p_session,p_operation,p_target,issued,expiry,fingerprint);
 return expiry;
end $$;
revoke all on function private.issue_reauthentication_proof(uuid,uuid,text,jsonb,text) from public,anon,authenticated,service_role;

create function public.issue_reauthentication_proof(
 p_actor uuid,p_session uuid,p_operation text,p_target jsonb,p_proof_hash text
) returns timestamptz language plpgsql security definer set search_path='' as $$begin
 if coalesce(auth.role(),'')<>'service_role' or p_operation in('secondary_password.change','attendance.manage') then
  raise sqlstate '42501' using message='reauthentication_unavailable';end if;
 return private.issue_reauthentication_proof(p_actor,p_session,p_operation,p_target,p_proof_hash);
end $$;
revoke all on function public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text) to service_role;

-- Verification, current credential fingerprint and issue are one transaction.
-- FALSE must return NULL, not raise: throwing would roll back failure counters.
create function public.issue_secondary_reauthentication_proof(
 p_operation text,p_target jsonb,p_proof_hash text,p_password text
) returns timestamptz language plpgsql security definer set search_path='' as $$
declare sid uuid;begin
 sid:=private.require_reauthentication_session();
 if p_operation is null or p_operation not in('secondary_password.change','attendance.manage')
  or p_password is null or length(p_password)>1024
  or not private.reauthentication_required(private.reauthentication_scope(p_operation)) then
  raise sqlstate '42501' using message='reauthentication_unavailable';end if;
 if public.verify_secondary_password(p_password) is distinct from true then return null;end if;
 return private.issue_reauthentication_proof(auth.uid(),sid,p_operation,p_target,p_proof_hash);
end $$;
revoke all on function public.issue_secondary_reauthentication_proof(text,jsonb,text,text) from public,anon,service_role;
grant execute on function public.issue_secondary_reauthentication_proof(text,jsonb,text,text) to authenticated;

create function private.consume_reauthentication_proof(p_operation text,p_target jsonb,p_proof text)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); v_session uuid; consumed text;fingerprint text;
begin
 if actor is null or not private.account_access_allowed() or p_proof is null or p_proof !~ '^[0-9a-f]{64}$'
  or private.reauthentication_scope(p_operation) is null
  or not private.reauthentication_required(private.reauthentication_scope(p_operation)) then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 v_session:=private.require_reauthentication_session();
 begin v_session:=(auth.jwt()->>'session_id')::uuid;
 exception when invalid_text_representation then raise sqlstate '42501' using message='reauthentication_required'; end;
 if v_session is null then raise sqlstate '42501' using message='reauthentication_required'; end if;
 if p_operation like 'master.%' and not public.is_current_user_master_admin() then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 if not pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(actor)) then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 if not private.account_access_allowed() then raise sqlstate '42501' using message='reauthentication_required'; end if;
 perform 1 from auth.sessions s where s.id=v_session and s.user_id=actor
  and (s.not_after is null or s.not_after>clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required'; end if;
 -- Credential changes use one lock order, including primary recovery.
 if p_operation in('secondary_password.replace','secondary_password.change') then
  perform pg_advisory_xact_lock(hashtextextended('sko-secondary-password:'||actor::text,0));
  perform 1 from public.user_secondary_credentials where user_id=actor for update;
 end if;
 if p_operation in('secondary_password.change','attendance.manage') then
  select encode(extensions.digest(password_hash,'sha256'),'hex') into fingerprint
  from public.user_secondary_credentials where user_id=actor for share;
  if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 end if;
 update private.reauthentication_proofs p set consumed_at=clock_timestamp()
 where p.proof_hash=encode(extensions.digest(p_proof,'sha256'),'hex')
  and p.actor_id=actor and p.session_id=v_session and p.operation=p_operation
  and p.target=p_target and p.secondary_credential_fingerprint is not distinct from fingerprint
  and p.consumed_at is null and p.expires_at>clock_timestamp()
 returning proof_hash into consumed;
 if consumed is null then raise sqlstate '42501' using message='reauthentication_required'; end if;
end $$;
revoke all on function private.consume_reauthentication_proof(text,jsonb,text) from public,anon,authenticated;

create function public.replace_secondary_password_with_proof(p_password text,p_proof text)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or p_password is null or length(p_password)<8 then
  raise sqlstate '22023' using message='secondary_password_invalid';
 end if;
 perform private.consume_reauthentication_proof('secondary_password.replace',jsonb_build_object('user_id',actor),p_proof);
 perform pg_advisory_xact_lock(hashtextextended('sko-secondary-password:'||actor::text,0));
 update public.user_secondary_credentials set
  password_hash=extensions.crypt(p_password,extensions.gen_salt('bf',12)),failed_attempts=0,locked_until=null,updated_at=now()
 where user_id=actor;
 if not found then raise sqlstate '42501' using message='secondary_password_not_configured'; end if;
end $$;
revoke all on function public.replace_secondary_password_with_proof(text,text) from public,anon;
grant execute on function public.replace_secondary_password_with_proof(text,text) to authenticated;

create function public.change_secondary_password_with_proof(p_password text,p_proof text)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or p_password is null or length(p_password)<8 then
  raise sqlstate '22023' using message='secondary_password_invalid';
 end if;
 perform private.consume_reauthentication_proof('secondary_password.change',jsonb_build_object('user_id',actor),p_proof);
 perform pg_advisory_xact_lock(hashtextextended('sko-secondary-password:'||actor::text,0));
 update public.user_secondary_credentials set
  password_hash=extensions.crypt(p_password,extensions.gen_salt('bf',12)),failed_attempts=0,locked_until=null,updated_at=now()
 where user_id=actor;
 if not found then raise sqlstate '42501' using message='secondary_password_not_configured'; end if;
end $$;
revoke all on function public.change_secondary_password_with_proof(text,text) from public,anon;
grant execute on function public.change_secondary_password_with_proof(text,text) to authenticated;

-- Legacy OFF behavior is preserved; ON allows first setup but forbids replacing
-- an existing credential through the old unproven RPC. No token/GUC bypass.
create or replace function public.set_secondary_password(p_password text)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); required boolean;
begin
 perform private.require_reauthentication_session();
 if p_password is null or length(p_password)<8 then raise sqlstate '22023' using message='secondary_password_invalid'; end if;
 required:=private.reauthentication_required('secondary_password');
 perform pg_advisory_xact_lock(hashtextextended('sko-secondary-password:'||actor::text,0));
 if required and exists(select 1 from public.user_secondary_credentials where user_id=actor) then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 insert into public.user_secondary_credentials(user_id,password_hash,failed_attempts,locked_until,updated_at)
 values(actor,extensions.crypt(p_password,extensions.gen_salt('bf',12)),0,null,now())
 on conflict(user_id) do update set password_hash=excluded.password_hash,failed_attempts=0,locked_until=null,updated_at=now();
end $$;

create function public.set_master_feature_enabled_with_proof(p_feature_key text,p_enabled boolean,p_proof text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.consume_reauthentication_proof('master.feature.set',jsonb_build_object('feature_key',p_feature_key,'enabled',p_enabled),p_proof);
 if p_feature_key not in ('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop') or p_enabled is null then
  raise sqlstate '22023' using message='unsupported_master_feature';
 end if;
 insert into private.master_feature_settings(feature_key,enabled,updated_at,updated_by)
 values(p_feature_key,p_enabled,now(),auth.uid()) on conflict(feature_key) do update
 set enabled=excluded.enabled,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
 return public.current_master_feature_flags();
end $$;
revoke all on function public.set_master_feature_enabled_with_proof(text,boolean,text) from public,anon;
grant execute on function public.set_master_feature_enabled_with_proof(text,boolean,text) to authenticated;

create or replace function public.set_master_feature_enabled(p_feature_key text,p_enabled boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.is_current_user_master_admin() or not private.account_access_allowed() then
  raise sqlstate '42501' using message='master_administrator_access_required';
 end if;
 if private.reauthentication_required('master_feature') then raise sqlstate '42501' using message='reauthentication_required'; end if;
 if p_feature_key is null or p_feature_key not in ('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop') then
  raise exception 'unsupported master feature';
 end if;
 insert into private.master_feature_settings(feature_key,enabled,updated_at,updated_by)
 values(p_feature_key,p_enabled,now(),auth.uid()) on conflict(feature_key) do update
 set enabled=excluded.enabled,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
 return public.current_master_feature_flags();
end $$;
commit;
