-- REVIEW ONLY. Requires staged operation_reauthentication_proofs.sql first.
-- New scope defaults OFF. No production apply or enforcement approval.
begin;
do $$ begin
 if to_regprocedure('private.consume_reauthentication_proof(text,jsonb,text)') is null
  or to_regprocedure('public.set_master_device_locked(uuid,boolean)') is null then
  raise sqlstate '55000' using message='master_device_lock_prerequisite_missing';
 end if;
end $$;
create table private.master_device_lock_rollout (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false
);
insert into private.master_device_lock_rollout(singleton) values(true);
alter table private.master_device_lock_rollout enable row level security;
revoke all on private.master_device_lock_rollout from public,anon,authenticated;

create or replace function private.reauthentication_scope(p_operation text) returns text
language sql immutable set search_path='' as $$
 select case p_operation when 'secondary_password.replace' then 'secondary_password'
  when 'master.feature.set' then 'master_feature'
  when 'master.security_incidents.read' then 'master_security'
  when 'master.security_collector.read' then 'master_security'
  when 'master.device.lock' then 'master_device_lock' end
$$;
create or replace function private.reauthentication_required(p_scope text) returns boolean
language plpgsql security definer set search_path='' as $$
declare required boolean;
begin
 if p_scope='master_device_lock' then
  select enabled into required from private.master_device_lock_rollout where singleton for share;
 else
  select enabled into required from private.reauthentication_rollout where scope=p_scope for share;
 end if;
 if not found then raise sqlstate '42501' using message='reauthentication_unavailable'; end if;
 return required;
end $$;

create function public.master_device_lock_capability() returns jsonb
language plpgsql security definer set search_path='' as $$
declare enabled boolean;
begin
 if auth.uid() is null or not private.account_access_allowed() or not public.is_current_user_master_admin() then
  raise sqlstate '42501' using message='master_administrator_access_required';
 end if;
 -- Discovery is advisory: issue/consume hold the gate lock again at operation.
 select r.enabled into enabled from private.master_device_lock_rollout r where singleton;
 if not found then raise sqlstate '42501' using message='reauthentication_unavailable'; end if;
 return jsonb_build_object('protocol','sko-master-device-lock-v1','enabled',enabled);
end $$;
revoke all on function public.master_device_lock_capability() from public,anon;
grant execute on function public.master_device_lock_capability() to authenticated;

create function public.set_master_device_locked_with_proof(p_device_id uuid,p_locked boolean,p_proof text)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); device private.master_devices%rowtype;
begin
 if p_device_id is null or p_locked is null then raise sqlstate '22023' using message='master_device_lock_invalid'; end if;
 perform private.consume_reauthentication_proof('master.device.lock',jsonb_build_object('device_id',p_device_id,'locked',p_locked),p_proof);
 select * into device from private.master_devices where id=p_device_id and master_user_id=actor for update;
 if not found or device.revoked_at is not null then raise sqlstate '42501' using message='master_device_lock_unavailable'; end if;
 update private.master_devices set is_locked=p_locked where id=p_device_id;
 insert into private.master_admin_audit_log(actor_user_id,action,target_user_id,details)
 values(actor,case when p_locked then 'master_device_lock' else 'master_device_unlock' end,actor,
  jsonb_build_object('device_id',p_device_id,'device_name',device.device_name));
end $$;
revoke all on function public.set_master_device_locked_with_proof(uuid,boolean,text) from public,anon;
grant execute on function public.set_master_device_locked_with_proof(uuid,boolean,text) to authenticated;

-- Same business operation/audit as the original RPC, with only the default-OFF
-- gate added before its existing device row lock. Bootstrap/recovery unchanged.
create or replace function public.set_master_device_locked(p_device_id uuid,p_locked boolean)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); device private.master_devices%rowtype;
begin
 if actor is null or not private.account_access_allowed() or not public.is_current_user_master_admin() then
  raise sqlstate '42501' using message='master_administrator_access_required';
 end if;
 if private.reauthentication_required('master_device_lock') then raise sqlstate '42501' using message='reauthentication_required'; end if;
 select * into device from private.master_devices where id=p_device_id and master_user_id=actor for update;
 if not found then raise exception 'master device not found'; end if;
 if device.revoked_at is not null then raise exception 'revoked master device cannot be changed'; end if;
 update private.master_devices set is_locked=p_locked where id=p_device_id;
 insert into private.master_admin_audit_log(actor_user_id,action,target_user_id,details)
 values(actor,case when p_locked then 'master_device_lock' else 'master_device_unlock' end,actor,
  jsonb_build_object('device_id',p_device_id,'device_name',device.device_name));
end $$;

create or replace function public.issue_reauthentication_proof(
 p_actor uuid,p_session uuid,p_operation text,p_target jsonb,p_proof_hash text
) returns timestamptz language plpgsql security definer set search_path='' as $$
declare expiry timestamptz; issued timestamptz;
begin
 if coalesce(auth.role(),'') <> 'service_role' or p_actor is null or p_session is null
  or p_proof_hash is null or p_proof_hash !~ '^[0-9a-f]{64}$'
  or private.reauthentication_scope(p_operation) is null
  or not private.reauthentication_required(private.reauthentication_scope(p_operation)) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 if p_operation='secondary_password.replace' and p_target<>jsonb_build_object('user_id',p_actor) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 elsif p_operation='master.feature.set' and (
  jsonb_typeof(p_target)<>'object' or p_target<>jsonb_build_object('feature_key',p_target->'feature_key','enabled',p_target->'enabled')
  or coalesce(p_target->>'feature_key','') not in ('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop')
  or coalesce(jsonb_typeof(p_target->'enabled'),'')<>'boolean') then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 elsif p_operation='master.device.lock' and (
  jsonb_typeof(p_target)<>'object' or p_target<>jsonb_build_object('device_id',p_target->'device_id','locked',p_target->'locked')
  or coalesce(p_target->>'device_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(jsonb_typeof(p_target->'locked'),'')<>'boolean') then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 elsif p_operation='master.security_incidents.read' and p_target<>'{"scope":"platform"}'::jsonb then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 elsif p_operation='master.security_collector.read' and p_target<>'{"scope":"decoy_collector"}'::jsonb then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 if p_target is null or (p_operation like 'master.%' and not exists(
  select 1 from private.master_admins where user_id=p_actor and enabled)) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 if p_operation='master.device.lock' and not exists(select 1 from private.master_devices
  where id=(p_target->>'device_id')::uuid and master_user_id=p_actor and revoked_at is null) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 -- Same deletion barrier as the existing Data API account hook; fail closed.
 if not pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(p_actor)) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 if exists(select 1 from private.account_deletion_access_restrictions where user_id=p_actor) then
  raise sqlstate '42501' using message='reauthentication_unavailable';
 end if;
 perform 1 from auth.sessions where id=p_session and user_id=p_actor
  and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_unavailable'; end if;
 issued:=clock_timestamp(); expiry:=issued+interval '120 seconds';
 insert into private.reauthentication_proofs(proof_hash,actor_id,session_id,operation,target,issued_at,expires_at)
 values(p_proof_hash,p_actor,p_session,p_operation,p_target,issued,expiry);
 return expiry;
end $$;
revoke all on function public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text) to service_role;


commit;
