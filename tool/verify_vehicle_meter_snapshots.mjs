import fs from 'node:fs';
const { PGlite } = await import(process.argv[2]);
const db = new PGlite();
try {
  // Same isolated schema as the GPS shift verifier; no production connection.
  await db.exec(`
    create schema auth; create schema private;
    create role anon; create role authenticated;
    create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.actor',true),'')::uuid $$;
    create function public.current_feature_permissions() returns jsonb language sql as $$ select '{"can_manage_attendance":true}'::jsonb $$;
    create table company_members(company_id uuid,user_id uuid,role text);
    create table workers(id uuid primary key,company_id uuid,status text); alter table workers add column user_id uuid; alter table workers add column name text;
    create table sites(id uuid,company_id uuid); alter table sites add column name text; alter table sites add column latitude double precision; alter table sites add column longitude double precision;
    create table daily_reports(id uuid primary key default gen_random_uuid(),company_id uuid,site_id uuid,report_date date,work_description text,status text,created_by uuid,updated_by uuid,updated_at timestamptz,signer_name text,signature_json jsonb,signed_at timestamptz,representative_signature_json jsonb,representative_signer_name text,supervisor_signature_json jsonb,supervisor_signer_name text);
    create table daily_report_workers(report_id uuid,worker_id uuid,overtime_hours numeric,early_hours numeric,night_hours numeric,allowance_amount integer,allowance_label text,work_category text,unique(report_id,worker_id));
    create table attendance_entries(id uuid default gen_random_uuid(),company_id uuid,work_date date,worker_id uuid,site_id uuid,base_man_days numeric,overtime_hours numeric,early_hours numeric,night_hours numeric,allowance_amount integer,allowance_names text[],notes text,created_by uuid,updated_by uuid,work_category text,source_report_id uuid);
    create table attendance_verifications(id uuid primary key default gen_random_uuid(),company_id uuid,worker_id uuid,site_id uuid,event_type text,verification_mode text,confirmed_at timestamptz,proximity_status text,note text,created_by uuid,daily_report_id uuid);
    create table vehicles(id uuid primary key,company_id uuid,is_active boolean);
    alter table attendance_verifications add column vehicle_id uuid references vehicles(id) on delete set null;
    create table work_vehicle_route_selections(company_id uuid,worker_id uuid,work_date date,vehicle_id uuid);
    alter table attendance_verifications add column route_assignment_id uuid;
    alter table attendance_verifications add column photo_storage_path text;
    alter table attendance_verifications add column latitude double precision;
    alter table attendance_verifications add column longitude double precision;
    alter table attendance_verifications add column accuracy_m double precision;
    alter table attendance_verifications add column distance_to_site_m double precision;
    alter table daily_reports add column route_assignment_id uuid;
    create table route_assignments(id uuid,company_id uuid,route_name text);
    create table route_stops(id uuid,route_assignment_id uuid,latitude double precision,longitude double precision,source_label text,address text);
    create table gps_auto_attendance_schedules(company_id uuid,worker_id uuid,enabled boolean,site_id uuid,route_assignment_id uuid,timezone text,weekdays smallint[],local_time time,last_attempt_date date,last_result text,updated_at timestamptz,radius_m double precision);
    create table work_attendance_selections(company_id uuid,worker_id uuid,work_date date,verification_mode text,site_id uuid,route_assignment_id uuid,updated_by uuid,updated_at timestamptz,unique(company_id,worker_id,work_date));
    create function private.has_company_feature(uuid,text) returns boolean language sql as $$ select exists(select 1 from public.company_members where company_id=$1 and user_id=auth.uid() and role in ('admin','manager','owner')) $$;
    create function private.account_access_allowed() returns boolean language sql as $$ select coalesce(current_setting('test.blocked',true),'false') <> 'true' $$;
    alter table attendance_verifications enable row level security;
    create policy "worker or attendance manager can create verification" on attendance_verifications for insert to authenticated with check (true);
    create policy fixture_read on attendance_verifications for select to authenticated using(exists(select 1 from workers where id=worker_id and company_id=attendance_verifications.company_id and user_id=auth.uid()) or private.has_company_feature(company_id,'can_manage_attendance'));
    create policy account_deletion_access_guard on attendance_verifications as restrictive for all to authenticated using(private.account_access_allowed()) with check(private.account_access_allowed());
    grant usage on schema auth,private to authenticated;
    grant select on all tables in schema public to authenticated;
    grant insert on attendance_verifications to authenticated;
    create table payroll_history(id integer,amount integer);
    insert into payroll_history values(1,123456);
    create table attendance_correction_items(attendance_entry_id uuid);
    create table paid_leave_requests(batch_id uuid,company_id uuid,worker_id uuid,requested_by uuid,leave_date date,reason text,status text,reviewed_by uuid,reviewed_at timestamptz,review_note text,updated_at timestamptz);
  
create table companies(id uuid primary key);
`);
  await db.exec(fs.readFileSync('supabase/migrations/20261008042058_fix_managed_attendance_overnight_chronology.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261008124940_gps_shift_work_date_evidence.sql','utf8'));
  // Execute the unchanged real public wrapper and its original ACLs.
  const originalGps = fs.readFileSync('supabase/migrations/20261002003417_add_gps_auto_attendance_and_evidence_link.sql','utf8');
  const wrapperStart = originalGps.indexOf('create or replace function public.attempt_gps_auto_attendance(');
  const wrapperEnd = originalGps.indexOf('create or replace function', wrapperStart + 1);
  if (wrapperStart < 0 || wrapperEnd < 0) throw new Error('GPS public wrapper fixture not found');
  await db.exec(originalGps.slice(wrapperStart, wrapperEnd));
  await db.exec(fs.readFileSync('supabase/migrations/20261008153425_vehicle_active_driver_claims.sql','utf8'));
  await db.exec(`alter table route_assignments add column is_active boolean not null default true; alter table vehicles add column odometer_km numeric(12,1) not null default 1000; alter table vehicles add column updated_by uuid; alter table vehicles add column updated_at timestamptz; alter table daily_report_workers add column vehicle_id uuid; alter table daily_report_workers add column route_assignment_id uuid; alter table daily_report_workers add column odometer_km numeric;`);
  await db.exec(fs.readFileSync('supabase/migrations/20261001232457_add_daily_report_vehicle_usage_rpc.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261008154433_vehicle_meter_snapshots.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/tests/vehicle_meter_snapshots_assertions.sql','utf8'));
  console.log('PASS driver meter snapshots: ownership, exact decrease/manual mileage, immutable retry, old-report/current baseline protection, pending warning dedup and unchanged OFF RPC');
} catch (error) { console.error(error.message, error.where ?? ''); process.exitCode = 1; } finally { await db.close(); }
