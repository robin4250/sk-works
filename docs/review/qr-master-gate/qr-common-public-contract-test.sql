\set ON_ERROR_STOP on
-- Synthetic auth/proof boundary. Does not prove GoTrue/JWT or key ownership.
create schema private;
create schema auth;
do $$ begin
 if not exists(select from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select from pg_roles where rolname='authenticated') then create role authenticated; end if;
end $$;
create function auth.uid() returns uuid language sql as $$
 select nullif(current_setting('fixture.actor',true),'')::uuid
$$;
create function private.require_reauthentication_session() returns uuid
language plpgsql as $$ begin
 if current_setting('fixture.session',true) is distinct from 'live' or auth.uid() is null then
   raise sqlstate '42501' using message='invalid session';
 end if;
 return auth.uid();
end $$;
create function public.is_current_user_master_admin() returns boolean
language sql as $$ select current_setting('fixture.master',true)='yes' $$;
create table private.proof_fixture(used boolean not null default false);
insert into private.proof_fixture default values;
create function private.consume_reauthentication_proof(operation text,target jsonb,proof text)
returns void language plpgsql as $$ begin
 if operation is distinct from 'master.feature.set' or target is distinct from
   jsonb_build_object('feature_key','qr_attendance','enabled',proof='fixture-bound-proof')
   or proof is null or proof not in ('fixture-bound-proof','fixture-off-proof') or (select used from private.proof_fixture) then
   raise sqlstate '42501' using message='invalid proof';
 end if;
 update private.proof_fixture set used=true;
end $$;
create table private.master_feature_settings(feature_key text primary key constraint master_feature_settings_feature_key_check check(feature_key in ('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop')),
 enabled boolean not null,updated_at timestamptz,updated_by uuid);
insert into private.master_feature_settings values('vehicle_management',true,null,null);

create function private.account_access_allowed() returns boolean language sql as $$ select true $$;
create function private.reauthentication_required(text) returns boolean language sql as $$ select false $$;
create table private.master_admin_audit_log(actor_user_id uuid,action text,target_user_id uuid,details jsonb);
\ir qr-master-gate.sql.review-only
\ir qr-master-contract.sql.review-only
create or replace function public.current_master_feature_flags()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when auth.uid() is null then null
    else jsonb_build_object(
      'vehicle_management',
        coalesce((
          select mfs.enabled
          from private.master_feature_settings mfs
          where mfs.feature_key = 'vehicle_management'
        ), true),
      'route_assignment',
        coalesce((
          select mfs.enabled
          from private.master_feature_settings mfs
          where mfs.feature_key = 'route_assignment'
        ), true),
      'traffic_nearest_station', coalesce((select enabled from private.master_feature_settings where feature_key='traffic_nearest_station'),false),
      'traffic_train_transfer', coalesce((select enabled from private.master_feature_settings where feature_key='traffic_train_transfer'),false),
      'traffic_bus_stop', coalesce((select enabled from private.master_feature_settings where feature_key='traffic_bus_stop'),false)
    )
  end;
$$;

revoke all on function public.current_master_feature_flags() from public, anon;
grant execute on function public.current_master_feature_flags() to authenticated;

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

-- Synthetic issuer fixture: only tests patch scope, not real credential checks.
create function public.issue_reauthentication_proof(p_actor uuid,p_session uuid,p_operation text,p_target jsonb,p_proof_hash text)
returns timestamptz language plpgsql security definer set search_path='' as $$
begin
 if p_operation<>'master.feature.set' or coalesce(p_target->>'feature_key','') not in ('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop') then raise sqlstate '42501'; end if;
 return clock_timestamp();
end $$;
revoke all on function public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text) from public,anon,authenticated;

-- A dependent view binds the original function OID; it must observe the new
-- contract after the public function is replaced, without dependency rewrites.
create view private.flags_dependency_fixture as select public.current_master_feature_flags() as flags;
create table private.reader_oid_fixture as select 'public.current_master_feature_flags()'::regprocedure::oid as original_oid;

-- Expected hashes here are synthetic test inputs, not production evidence.
do $$ declare signature text; begin
 foreach signature in array array['public.current_master_feature_flags()','qr_attendance_private.require_enabled()',
 'public.set_master_feature_enabled(text,boolean)',
 'public.set_master_feature_enabled_with_proof(text,boolean,text)',
 'public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text)'] loop
 perform set_config('sko.review.qr_'||md5(signature),md5(pg_get_functiondef(to_regprocedure(signature))),false);
 end loop;
 perform set_config('sko.review.qr_check_md5',(select md5(pg_get_constraintdef(oid)) from pg_constraint where conrelid='private.master_feature_settings'::regclass and conname='master_feature_settings_feature_key_check'),false);
end $$;
\ir qr-common-public-contract.sql.review-only
select set_config('fixture.actor','00000000-0000-0000-0000-000000000001',false);
select set_config('fixture.session','live',false);
select set_config('fixture.master','yes',false);
do $$ declare before_flags jsonb; flags jsonb; begin
 flags:=public.current_master_feature_flags();
 if 'public.current_master_feature_flags()'::regprocedure::oid is distinct from
    (select original_oid from private.reader_oid_fixture) then raise exception 'public reader OID changed'; end if;
 if (select dependency.flags->>'qr_attendance_contract_version' from private.flags_dependency_fixture dependency)<>'1' then
  raise exception 'dependent reader bypassed QR contract';
 end if;
 if flags->>'qr_attendance'<>'false' or flags->>'vehicle_management'<>'true' or flags->>'route_assignment'<>'true' then raise exception 'common flags not preserved/default OFF'; end if;
 begin perform public.set_master_feature_enabled_with_proof('qr_attendance',true,'fixture-bound-proof'); raise exception 'OFF permitted'; exception when insufficient_privilege then null; end;
 if (select used from private.proof_fixture) then raise exception 'OFF consumed proof'; end if;
 -- A preexisting settings value alone cannot bypass default-OFF rollout.
 insert into private.master_feature_settings(feature_key,enabled) values('qr_attendance',true);
 begin perform qr_attendance_private.require_enabled(); raise exception 'gate ignored rollout'; exception when insufficient_privilege then null; end;
 update qr_attendance_private.public_contract_rollout set enabled=true;
 flags:=public.set_master_feature_enabled_with_proof('qr_attendance',true,'fixture-bound-proof');
 perform qr_attendance_private.require_enabled();
 if flags->>'qr_attendance'<>'true' or (select count(*) from private.master_admin_audit_log)<>1 then raise exception 'proof bridge/audit failed'; end if;
 begin perform public.set_master_feature_enabled('qr_attendance',false); raise exception 'legacy permitted'; exception when raise_exception then if sqlerrm='legacy permitted' then raise; end if; end;
 update private.proof_fixture set used=false;
 flags:=public.set_master_feature_enabled_with_proof('qr_attendance',false,'fixture-off-proof');
 if flags->>'qr_attendance'<>'false' or (select count(*) from private.master_admin_audit_log)<>2 then raise exception 'OFF bridge/audit failed'; end if;
 if has_function_privilege('anon','public.current_master_feature_flags()','EXECUTE') or has_function_privilege('authenticated','public.current_master_feature_flags_before_qr_candidate()','EXECUTE') or has_function_privilege('authenticated','public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text)','EXECUTE') then raise exception 'public ACL expanded'; end if;
 if not has_function_privilege('authenticated','public.set_master_feature_enabled_with_proof(text,boolean,text)','EXECUTE') then raise exception 'existing proof ACL lost'; end if;
end $$;
select set_config('fixture.master','no',false);
do $$ begin
 update private.proof_fixture set used=false;
 begin perform public.set_master_feature_enabled_with_proof('qr_attendance',true,'fixture-bound-proof'); raise exception 'worker permitted'; exception when insufficient_privilege then null; end;
 if (select used from private.proof_fixture) then raise exception 'worker consumed proof'; end if;
end $$;
select set_config('fixture.session','expired',false);
do $$ begin
 begin perform public.current_master_feature_flags(); raise exception 'expired read'; exception when insufficient_privilege then null; end;
end $$;
