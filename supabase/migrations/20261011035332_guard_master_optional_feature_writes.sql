-- Additive write gates only. Existing RPCs, ACLs, RLS and historical data remain intact.
-- Row locks serialize a new optional write with the existing master setter.
create function private.require_master_optional_feature(p_key text)
returns void language plpgsql security definer set search_path='' as $$
declare v_enabled boolean;
begin
  if p_key not in ('vehicle_management','route_assignment') then
    raise exception 'unsupported master feature';
  end if;
  perform 1 from private.master_feature_settings s order by s.feature_key for share;
  select s.enabled into v_enabled from private.master_feature_settings s
    where s.feature_key=p_key for share;
  if not found then
    -- Preserve the existing absent-row = ON contract, without an insertion race.
    lock table private.master_feature_settings in share mode;
    select s.enabled into v_enabled from private.master_feature_settings s
      where s.feature_key=p_key for share;
    v_enabled:=coalesce(v_enabled,true);
  end if;
  if not v_enabled then
    raise exception using errcode='P0001',message='master feature disabled: '||p_key;
  end if;
end;
$$;
revoke all on function private.require_master_optional_feature(text) from public,anon,authenticated,service_role;

create function private.guard_master_optional_feature_write()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  n jsonb:=to_jsonb(NEW); o jsonb; v_previous jsonb;
  v_vehicle_changed boolean:=false; v_route_changed boolean:=false;
  v_meter_allowed boolean:=false;
begin
  if TG_OP='UPDATE' then o:=to_jsonb(OLD); end if;
  if TG_TABLE_NAME='vehicles' then
    if TG_OP='UPDATE' and n=o then return NEW; end if;
    -- A completed, authenticated driver's meter snapshot is the sole OFF exception.
    -- Its existing RPC inserts the immutable signed event immediately before this UPDATE.
    if TG_OP='UPDATE'
      and (n - array['odometer_km','updated_by','updated_at'])=
          (o - array['odometer_km','updated_by','updated_at'])
      and n->>'updated_by'=auth.uid()::text
      and to_regclass('public.vehicle_meter_events') is not null
      and to_regclass('public.vehicle_usage_claims') is not null then
      execute $meter$
        select exists(select 1 from public.vehicle_meter_events e
          join public.vehicle_usage_claims c on c.source_clock_in_id=e.source_clock_in_id
          join public.workers w on w.id=c.driver_worker_id and w.company_id=c.company_id
          join public.attendance_verifications a on a.id=c.source_clock_in_id
          join public.attendance_verifications z on z.id=c.source_clock_out_id
          where e.company_id=($1->>'company_id')::uuid and e.vehicle_id=($1->>'id')::uuid
            and e.recorded_by=auth.uid() and w.user_id=auth.uid() and w.status='active'
            and c.company_id=e.company_id and c.vehicle_id=e.vehicle_id
            and c.driver_worker_id=e.driver_worker_id and c.work_date=e.work_date
            and c.ended_at is not null and c.source_clock_out_id is not null
            and a.event_type='clock_in' and a.company_id=c.company_id
            and a.vehicle_id=c.vehicle_id and a.worker_id=c.driver_worker_id
            and z.event_type='clock_out' and z.company_id=c.company_id
            and z.vehicle_id=c.vehicle_id and z.worker_id=c.driver_worker_id
            and e.previous_km=($2->>'odometer_km')::numeric
            and e.current_km=($1->>'odometer_km')::numeric
            and e.xmin::text::bigint=(txid_current() % 4294967296))
      $meter$ into v_meter_allowed using n,o;
    end if;
    if not v_meter_allowed then perform private.require_master_optional_feature('vehicle_management'); end if;
  elsif TG_TABLE_NAME in ('route_assignments','route_stops') then
    if TG_OP='UPDATE' and n=o then return NEW; end if;
    perform private.require_master_optional_feature('route_assignment');
    if TG_TABLE_NAME='route_assignments' and n->>'vehicle_id' is not null
      and (TG_OP='INSERT' or n->>'vehicle_id' is distinct from o->>'vehicle_id') then
      perform private.require_master_optional_feature('vehicle_management');
    end if;
  elsif TG_TABLE_NAME='attendance_verifications' then
    -- Old source rows and all checkout evidence remain available while OFF.
    if n->>'event_type'<>'clock_in' then return NEW; end if;
    if TG_OP='UPDATE' and o->>'event_type'='clock_in' and row(n->>'vehicle_id',n->>'route_assignment_id')
       is not distinct from row(o->>'vehicle_id',o->>'route_assignment_id') then return NEW; end if;
    if n->>'route_assignment_id' is not null then perform private.require_master_optional_feature('route_assignment'); end if;
    if n->>'vehicle_id' is not null then perform private.require_master_optional_feature('vehicle_management'); end if;
  else
    -- BEFORE INSERT also runs for ON CONFLICT UPDATE. Preserve existing choices,
    -- while UPDATE and the clock-in gate still reject newly selected disabled features.
    if TG_OP='INSERT' then
      if TG_TABLE_NAME='gps_auto_attendance_schedules' then
        execute format('select to_jsonb(s) from public.%I s where company_id=$1 and worker_id=$2',TG_TABLE_NAME)
          into v_previous using NEW.company_id,NEW.worker_id;
      else
        execute format('select to_jsonb(s) from public.%I s where company_id=$1 and worker_id=$2 and work_date=$3',TG_TABLE_NAME)
          into v_previous using NEW.company_id,NEW.worker_id,NEW.work_date;
      end if;
      o:=v_previous;
    end if;
    v_vehicle_changed:=n->>'vehicle_id' is not null and n->>'vehicle_id' is distinct from o->>'vehicle_id';
    v_route_changed:=n->>'route_assignment_id' is not null and n->>'route_assignment_id' is distinct from o->>'route_assignment_id';
    if TG_TABLE_NAME='gps_auto_attendance_schedules' and n->>'route_assignment_id' is not null
      and n->>'enabled'='true' and coalesce(o->>'enabled','false')<>'true' then
      v_route_changed:=true;
    end if;
    if v_route_changed then perform private.require_master_optional_feature('route_assignment'); end if;
    if v_vehicle_changed then perform private.require_master_optional_feature('vehicle_management'); end if;
  end if;
  return NEW;
end;
$$;
revoke all on function private.guard_master_optional_feature_write() from public,anon,authenticated,service_role;

create trigger aa_master_optional_write_guard before insert or update on public.vehicles
for each row execute function private.guard_master_optional_feature_write();
create trigger aa_master_optional_write_guard before insert or update on public.route_assignments
for each row execute function private.guard_master_optional_feature_write();
create trigger aa_master_optional_write_guard before insert or update on public.route_stops
for each row execute function private.guard_master_optional_feature_write();
create trigger aa_master_optional_write_guard before insert or update on public.work_vehicle_route_selections
for each row execute function private.guard_master_optional_feature_write();
create trigger aa_master_optional_write_guard before insert or update on public.work_attendance_selections
for each row execute function private.guard_master_optional_feature_write();
create trigger aa_master_optional_write_guard before insert or update on public.gps_auto_attendance_schedules
for each row execute function private.guard_master_optional_feature_write();
create trigger aa_master_optional_write_guard before insert or update on public.attendance_verifications
for each row execute function private.guard_master_optional_feature_write();
