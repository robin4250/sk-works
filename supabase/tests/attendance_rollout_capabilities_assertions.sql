-- New RPC and real role/RLS enforcement. Prerequisite stubs are used only for
-- catalog readiness checks; this suite never invokes staged checkout/meter RPCs.
select set_config('test.actor','10000000-0000-0000-0000-000000000011',false);
set role authenticated;
do $$ declare r jsonb; begin
 if (select count(*) from public.company_members)<>1 then raise exception 'membership RLS fixture not enforced'; end if;
 r:=public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001');
 if r->>'version'<>'1' or r->>'company_id'<>'10000000-0000-0000-0000-000000000001'
 or r->>'group_checkout_enabled'<>'false' or r->>'vehicle_usage_enabled'<>'false'
 or r->>'vehicle_meter_enabled'<>'false' then raise exception 'missing schema was not OFF'; end if;
 begin perform public.get_attendance_rollout_capabilities('20000000-0000-0000-0000-000000000001'); raise exception 'foreign company leaked';
 exception when insufficient_privilege then null; end;
 begin perform public.get_attendance_rollout_capabilities(null); raise exception 'NULL company accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
-- Schema matches the gate contract from #761 and #765; it remains private.
create table private.group_checkout_rollout(company_id uuid primary key,enabled boolean not null default false);
create table private.vehicle_usage_rollout(company_id uuid primary key,enabled boolean not null default false);
alter table private.group_checkout_rollout enable row level security;
alter table private.vehicle_usage_rollout enable row level security;
revoke all on private.group_checkout_rollout,private.vehicle_usage_rollout from public,anon,authenticated;
create table private.group_checkout_requests(id uuid);
create table public.vehicle_usage_claims(id uuid);
create function private.enforce_vehicle_usage_claim() returns trigger language plpgsql as $$ begin return NEW; end $$;
create function private.group_checkout_candidates(uuid) returns jsonb language sql as $$ select '[]'::jsonb $$;
create function private.commit_group_checkout(uuid,uuid[],uuid) returns jsonb language sql as $$ select '[]'::jsonb $$;
create function public.group_checkout_candidates(uuid) returns jsonb language sql as $$ select '[]'::jsonb $$;
create function public.commit_group_checkout(uuid,uuid[],uuid) returns jsonb language sql as $$ select '[]'::jsonb $$;
insert into private.group_checkout_rollout(company_id) values('10000000-0000-0000-0000-000000000001');
insert into private.vehicle_usage_rollout(company_id) values('10000000-0000-0000-0000-000000000001');
set role authenticated;
do $$ declare r jsonb; begin
 r:=public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001');
 if r->>'group_checkout_enabled'<>'false' or r->>'vehicle_usage_enabled'<>'false' or r->>'vehicle_meter_enabled'<>'false' then raise exception 'default rows were not OFF'; end if;
 begin perform 1 from private.vehicle_usage_rollout; raise exception 'private vehicle table exposed'; exception when insufficient_privilege then null; end;
 begin update private.group_checkout_rollout set enabled=true; raise exception 'client enabled gate'; exception when insufficient_privilege then null; end;
end $$;
reset role;
-- Explicit ON exists only in this isolated fixture, never in the migration.
update private.group_checkout_rollout set enabled=true;
update private.vehicle_usage_rollout set enabled=true;
-- A group checkout without complete report attachment must never enable UI.
set role authenticated;
do $$ begin
 if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'group_checkout_enabled'<>'false' then raise exception 'missing attach RPC enabled group'; end if;
end $$;
reset role;
create function public.attach_group_report_sources(uuid,uuid,uuid[]) returns jsonb language sql as $$ select '{}'::jsonb $$;
set role authenticated;
do $$ begin
 if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'group_checkout_enabled'<>'false' then raise exception 'public attach wrapper alone enabled group'; end if;
end $$;
reset role;
create function private.attach_group_report_sources(uuid,uuid,uuid[]) returns jsonb language sql as $$ select '{}'::jsonb $$;
set role authenticated;
do $$ declare r jsonb; begin
 r:=public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001');
 if r->>'group_checkout_enabled'<>'true' or r->>'vehicle_usage_enabled'<>'true' then raise exception 'own staged booleans unreadable'; end if;
 if r->>'vehicle_meter_enabled'<>'false' then raise exception 'claim-only schema enabled meter'; end if;
end $$;
reset role;
create table public.vehicle_meter_events(id uuid);
create function public.record_vehicle_driver_meter(uuid,uuid,numeric,numeric) returns jsonb language sql as $$ select '{}'::jsonb $$;
set role authenticated;
do $$ begin
 if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'vehicle_meter_enabled'<>'false' then raise exception 'public wrapper alone enabled meter'; end if;
end $$;
reset role;
create function private.record_vehicle_driver_meter(uuid,uuid,numeric,numeric) returns jsonb language sql as $$ select '{}'::jsonb $$;
-- Report integration is required even when driver meter recording is installed.
set role authenticated;
do $$ begin
 if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'vehicle_meter_enabled'<>'false' then raise exception 'recording without report contract enabled meter'; end if;
end $$;
reset role;
create function public.get_report_vehicle_meter_context(uuid) returns jsonb language sql as $$ select '{}'::jsonb $$;
create function public.attach_vehicle_meter_to_report(uuid,uuid) returns jsonb language sql as $$ select '{}'::jsonb $$;
create function private.require_vehicle_meter_report_context(uuid) returns jsonb language sql as $$ select '{}'::jsonb $$;
create table private.vehicle_meter_report_links(id uuid);
create table public.daily_report_workers(vehicle_meter_event_id uuid,vehicle_meter_source_clock_in_id uuid,previous_odometer_km numeric,trip_distance_km numeric);
-- Remove each exact dependency in turn; restore after checking fail-closed.
do $$ declare n text; r jsonb; begin
 foreach n in array array['public.get_report_vehicle_meter_context(uuid)','public.attach_vehicle_meter_to_report(uuid,uuid)','private.require_vehicle_meter_report_context(uuid)'] loop
   execute format('alter function %s rename to fixture_missing_contract',n);
   r:=public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001');
   if r->>'vehicle_meter_enabled'<>'false' then raise exception 'missing report function enabled meter: %',n; end if;
   execute format('alter function %s.fixture_missing_contract(%s) rename to %I',split_part(n,'.',1),split_part(split_part(n,'(',2),')',1),split_part(split_part(n,'.',2),'(',1));
 end loop;
 alter table private.vehicle_meter_report_links rename to fixture_missing_ledger;
 if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'vehicle_meter_enabled'<>'false' then raise exception 'missing ledger enabled meter'; end if;
 alter table private.fixture_missing_ledger rename to vehicle_meter_report_links;
 foreach n in array array['vehicle_meter_event_id','vehicle_meter_source_clock_in_id','previous_odometer_km','trip_distance_km'] loop
   execute format('alter table public.daily_report_workers rename column %I to fixture_missing_column',n);
   if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'vehicle_meter_enabled'<>'false' then raise exception 'missing snapshot column enabled meter: %',n; end if;
   execute format('alter table public.daily_report_workers rename column fixture_missing_column to %I',n);
 end loop;
 alter table public.daily_report_workers alter column previous_odometer_km type text;
 if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'vehicle_meter_enabled'<>'false' then raise exception 'wrong snapshot type enabled meter'; end if;
 alter table public.daily_report_workers alter column previous_odometer_km type numeric using previous_odometer_km::numeric;
end $$;

set role authenticated;
do $$ begin
 if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'vehicle_meter_enabled'<>'true' then raise exception 'installed meter was unavailable'; end if;
end $$;
reset role;
update private.vehicle_usage_rollout set enabled=false;
set role authenticated;
do $$ begin
 if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'vehicle_meter_enabled'<>'false' then raise exception 'meter remained on after gate off'; end if;
end $$;
select set_config('test.blocked','true',false);
do $$ begin
 begin perform public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001'); raise exception 'blocked account read capability';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('test.blocked','false',false);
select set_config('test.actor','',false);
set role authenticated;
do $$ begin
 begin perform public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001'); raise exception 'no actor read capability';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
set role anon;
do $$ begin
 begin perform public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001'); raise exception 'anonymous RPC execute accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
-- An unrecognized/partial gate schema must also fail closed.
alter table private.group_checkout_rollout rename column enabled to unknown_flag;
select set_config('test.actor','10000000-0000-0000-0000-000000000011',false);
set role authenticated;
do $$ begin
 if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'group_checkout_enabled'<>'false' then raise exception 'unknown gate column enabled capability'; end if;
end $$;
reset role;

-- Avoid accepting assignment casts such as integer 1 as an enabled boolean.
alter table private.group_checkout_rollout rename column unknown_flag to enabled;
alter table private.group_checkout_rollout alter column enabled drop default;
alter table private.group_checkout_rollout alter column enabled type integer using case when enabled then 1 else 0 end;
set role authenticated;
do $$ begin
 if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'group_checkout_enabled'<>'false' then raise exception 'unknown gate type coerced to true'; end if;
end $$;
reset role;
