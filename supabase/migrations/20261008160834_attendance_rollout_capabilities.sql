-- Read-only, fail-closed discovery for staged #761/#764/#765. No gate is enabled.
-- Definer reads restricted private tables only after caller account/membership checks.
create function private.get_attendance_rollout_capabilities(p_company_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid();
 v_group boolean:=false;
 v_vehicle boolean:=false;
 v_meter boolean:=false;
begin
 if v_actor is null or p_company_id is null or not private.account_access_allowed()
    or not exists(select 1 from public.company_members m
       where m.company_id=p_company_id and m.user_id=v_actor) then
   raise exception 'attendance capability access unavailable' using errcode='42501';
 end if;

 -- These migrations may not have been installed yet. Missing schema is OFF,
 -- and existence of claims or a previous successful call never infers a gate.
 if to_regclass('private.group_checkout_rollout') is not null
    and exists(select 1 from pg_catalog.pg_attribute a
      where a.attrelid=to_regclass('private.group_checkout_rollout') and a.attname='enabled'
        and not a.attisdropped and a.atttypid=to_regtype('pg_catalog.bool'))
    and to_regclass('private.group_checkout_requests') is not null
    and to_regprocedure('public.group_checkout_candidates(uuid)') is not null
    and to_regprocedure('public.commit_group_checkout(uuid,uuid[],uuid)') is not null
    and to_regprocedure('private.group_checkout_candidates(uuid)') is not null
    and to_regprocedure('private.commit_group_checkout(uuid,uuid[],uuid)') is not null
    and to_regprocedure('public.attach_group_report_sources(uuid,uuid,uuid[])') is not null
    and to_regprocedure('private.attach_group_report_sources(uuid,uuid,uuid[])') is not null then
   begin
     execute 'select coalesce(enabled,false) from private.group_checkout_rollout where company_id=$1'
       into v_group using p_company_id;
     v_group:=coalesce(v_group,false);
   exception when undefined_table or undefined_column or datatype_mismatch then
     v_group:=false;
   end;
 end if;

 if to_regclass('private.vehicle_usage_rollout') is not null
    and exists(select 1 from pg_catalog.pg_attribute a
      where a.attrelid=to_regclass('private.vehicle_usage_rollout') and a.attname='enabled'
        and not a.attisdropped and a.atttypid=to_regtype('pg_catalog.bool'))
    and to_regclass('public.vehicle_usage_claims') is not null
    and to_regprocedure('private.enforce_vehicle_usage_claim()') is not null then
   begin
     execute 'select coalesce(enabled,false) from private.vehicle_usage_rollout where company_id=$1'
       into v_vehicle using p_company_id;
     v_vehicle:=coalesce(v_vehicle,false);
   exception when undefined_table or undefined_column or datatype_mismatch then
     v_vehicle:=false;
   end;
 end if;

 -- #761 alone never advertises meter entry: #764's tables and both exact
 -- driver recording and report snapshot contracts must all be installed.
 -- Partial deployment must not make the UI call an unavailable report RPC.
 v_meter:=v_vehicle
   and to_regclass('public.vehicle_meter_events') is not null
   and to_regprocedure('public.record_vehicle_driver_meter(uuid,uuid,numeric,numeric)') is not null
   and to_regprocedure('private.record_vehicle_driver_meter(uuid,uuid,numeric,numeric)') is not null
   and to_regprocedure('public.get_report_vehicle_meter_context(uuid)') is not null
   and to_regprocedure('public.attach_vehicle_meter_to_report(uuid,uuid)') is not null
   and to_regprocedure('private.require_vehicle_meter_report_context(uuid)') is not null
   and to_regclass('private.vehicle_meter_report_links') is not null
   and (select count(*)=4 from pg_catalog.pg_attribute a
     where a.attrelid=to_regclass('public.daily_report_workers') and not a.attisdropped
       and ((a.attname in ('vehicle_meter_event_id','vehicle_meter_source_clock_in_id')
             and a.atttypid=to_regtype('pg_catalog.uuid'))
         or (a.attname in ('previous_odometer_km','trip_distance_km')
             and a.atttypid=to_regtype('pg_catalog.numeric'))));
 return jsonb_build_object('version',1,'company_id',p_company_id,
   'group_checkout_enabled',coalesce(v_group,false),
   'vehicle_usage_enabled',coalesce(v_vehicle,false),
   'vehicle_meter_enabled',coalesce(v_meter,false));
end $$;
revoke all on function private.get_attendance_rollout_capabilities(uuid) from public,anon;
grant execute on function private.get_attendance_rollout_capabilities(uuid) to authenticated;

create function public.get_attendance_rollout_capabilities(p_company_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.get_attendance_rollout_capabilities(p_company_id)
$$;
revoke all on function public.get_attendance_rollout_capabilities(uuid) from public,anon;
grant execute on function public.get_attendance_rollout_capabilities(uuid) to authenticated;
