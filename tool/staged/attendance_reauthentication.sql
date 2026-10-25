-- REVIEW ONLY. Install AFTER reauthentication_proofs and PR1422 allowance candidate.
-- Default OFF. No rollout row is enabled; no employee/signature/financial data changes.
begin;
do $pins$ begin
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.force_manage_attendance(text,jsonb)')
  and md5(prosrc)='840b139fd78b9e9c2542db100f3232a7' and prosecdef and pg_get_userbyid(proowner)='postgres')
 then raise exception 'attendance_reauthentication_force_source_mismatch';end if;
 if to_regprocedure('private.require_reauthentication_session()') is null then
  raise exception 'attendance_reauthentication_proof_dependency_missing';end if;
end $pins$;
create schema attendance_stepup_private;
revoke all on schema attendance_stepup_private from public,anon,authenticated,service_role;
create table attendance_stepup_private.originals(signature text primary key,definition text not null,acl text);
alter table attendance_stepup_private.originals enable row level security;
revoke all on attendance_stepup_private.originals from public,anon,authenticated,service_role;
insert into attendance_stepup_private.originals
select p.oid::regprocedure::text,pg_get_functiondef(p.oid),p.proacl::text from pg_proc p
where p.oid in(to_regprocedure('public.force_manage_attendance(text,jsonb)'),
 to_regprocedure('private.reauthentication_scope(text)'),to_regprocedure('public.reauthentication_capabilities()'));

-- Keep the old public OID: dependent SQL callers must hit the same gate.
-- The exact pinned implementation is copied, never moved or exposed to callers.
do $copy$ declare body text;begin
 select definition into strict body from attendance_stepup_private.originals
 where signature='force_manage_attendance(text,jsonb)';
 if body not like 'CREATE OR REPLACE FUNCTION public.force_manage_attendance(%' then
  raise exception 'attendance_reauthentication_force_header_mismatch';end if;
 execute regexp_replace(body,'^CREATE OR REPLACE FUNCTION public\.force_manage_attendance\(',
  'CREATE FUNCTION attendance_stepup_private.force_manage_attendance_unproven(');
end $copy$;
revoke all on function attendance_stepup_private.force_manage_attendance_unproven(text,jsonb) from public,anon,authenticated,service_role;

alter table private.reauthentication_rollout drop constraint reauthentication_rollout_scope_check;
alter table private.reauthentication_rollout add constraint reauthentication_rollout_scope_check
 check(scope in('secondary_password','master_feature','master_security','attendance_management'));
insert into private.reauthentication_rollout(scope) values('attendance_management');
create or replace function private.reauthentication_scope(p_operation text) returns text
language sql immutable set search_path='' as $$
 select case p_operation when 'secondary_password.replace' then 'secondary_password'
  when 'secondary_password.change' then 'secondary_password'
  when 'master.feature.set' then 'master_feature'
  when 'master.security_incidents.read' then 'master_security'
  when 'attendance.manage' then 'attendance_management' end
$$;
create or replace function public.reauthentication_capabilities() returns jsonb
language plpgsql security definer set search_path='' as $$begin
 perform private.require_reauthentication_session();
 return jsonb_build_object('protocol','sko-reauthentication-v1',
  'secondary_password',private.reauthentication_required('secondary_password'),
  'secondary_password_change_supported',private.reauthentication_required('secondary_password') and exists(select 1 from public.user_secondary_credentials where user_id=auth.uid()),
  'secondary_password_recovery_supported',private.reauthentication_required('secondary_password') and exists(select 1 from auth.users where id=auth.uid() and coalesce(encrypted_password,'')<>''),
  'master_feature',private.reauthentication_required('master_feature'),
  'master_security',private.reauthentication_required('master_security'),
  'attendance_management',private.reauthentication_required('attendance_management') and private.reauthentication_required('secondary_password'));
end $$;

create function attendance_stepup_private.target(p_action text,p_items jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();cid uuid;begin
 perform private.require_reauthentication_session();
 if not private.reauthentication_required('attendance_management') then
  raise sqlstate '42501' using message='attendance_reauthentication_disabled';end if;
 if not private.reauthentication_required('secondary_password') then
  raise sqlstate '42501' using message='attendance_reauthentication_recovery_dependency_missing';end if;
 -- Prevent a second membership or company reassignment between proof recheck
 -- and the legacy implementation's company lookup in this same transaction.
 lock table public.company_members in share mode;
 if (select count(*) from public.company_members where user_id=actor)<>1 then
  raise sqlstate '42501' using message='attendance_reauthentication_single_company_required';end if;
 select company_id into strict cid from public.company_members where user_id=actor;
 perform attendance_admin_override_private.require_manager(cid);
 if p_action is null or p_action not in('upsert','delete') or p_items is null
  or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>500 then
  raise sqlstate '22023' using message='attendance_reauthentication_invalid_target';end if;
 return jsonb_build_object('company_id',cid,'action',p_action,
  'items_sha256',encode(extensions.digest(convert_to(p_items::text,'UTF8'),'sha256'),'hex'));
end $$;
revoke all on function attendance_stepup_private.target(text,jsonb) from public,anon,authenticated,service_role;

create function public.attendance_management_reauthentication_target(p_action text,p_items jsonb) returns jsonb
language sql security definer set search_path='' as $$select attendance_stepup_private.target(p_action,p_items)$$;
revoke all on function public.attendance_management_reauthentication_target(text,jsonb) from public,anon,service_role;
grant execute on function public.attendance_management_reauthentication_target(text,jsonb) to authenticated;

create or replace function public.force_manage_attendance(p_action text,p_items jsonb) returns integer
language plpgsql security definer set search_path='' as $$begin
 if private.reauthentication_required('attendance_management') then
  raise sqlstate '42501' using message='reauthentication_required';end if;
 return attendance_stepup_private.force_manage_attendance_unproven(p_action,p_items);
end $$;
-- Retain old grants for OFF compatibility; ON denies every old entry including service_role.

create function public.force_manage_attendance_with_proof(p_action text,p_items jsonb,p_proof text) returns integer
language plpgsql security definer set search_path='' as $$declare target jsonb;begin
 target:=attendance_stepup_private.target(p_action,p_items);
 perform private.consume_reauthentication_proof('attendance.manage',target,p_proof);
 return attendance_stepup_private.force_manage_attendance_unproven(p_action,p_items);
end $$;
revoke all on function public.force_manage_attendance_with_proof(text,jsonb,text) from public,anon,service_role;
grant execute on function public.force_manage_attendance_with_proof(text,jsonb,text) to authenticated;
commit;
