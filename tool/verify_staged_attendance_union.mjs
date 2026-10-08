import fs from 'node:fs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import path from 'node:path';
const { PGlite } = await import(process.argv[2]);
const vehicleRoot = '.';
const groupRoot = '.';
const attachmentRoot = '.';
const vehicleAttachmentRoot = '.';
if (!vehicleRoot || !groupRoot || !attachmentRoot || !vehicleAttachmentRoot) throw new Error('Pinned vehicle, group, group report and vehicle report attachment dependency roots are required.');
const db = new PGlite();
const sql = file => fs.readFileSync(file, 'utf8');
try {
  const manifest = JSON.parse(sql('tool/fixtures/staged_attendance_union_manifest.json'));
  for (const item of manifest.migrations) {
    const bytes = fs.readFileSync(item.path);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), item.sha256, item.path);
  }
  for (const name of ['20261008153425_vehicle_active_driver_claims.sql', '20261008154241_group_proxy_checkout_staged.sql', '20261008154433_vehicle_meter_snapshots.sql']) {
    assert.equal(sql('supabase/migrations/' + name), sql('tool/fixtures/attendance_race/' + name), 'deployed SQL differs from realPG fixture: ' + name);
  }
  const baseline = sql('tool/verify_gps_shift_work_date.mjs');
  const setup = baseline.match(/await db\.exec\(`([\s\S]*?)`\);/);
  if (!setup) throw new Error('GPS fixture schema unavailable');
  await db.exec(setup[1]);
  await db.exec(`create table companies(id uuid primary key);
    alter table workers add primary key(id);
    alter table company_members enable row level security;
    create policy fixture_own_member on company_members for select to authenticated using(user_id=auth.uid());
    alter table attendance_verifications alter column verification_mode set not null;
    alter table attendance_verifications add constraint fixture_mode check(verification_mode in ('manual','location','location_photo','gps_auto'));
    alter table attendance_verifications add constraint attendance_verifications_check check(verification_mode='manual' or (latitude is not null and longitude is not null));
    alter table attendance_verifications add constraint attendance_verifications_check1 check(verification_mode<>'location_photo' or photo_storage_path is not null);`);
  await db.exec(sql('supabase/migrations/20261008042058_fix_managed_attendance_overnight_chronology.sql'));
  await db.exec(sql('supabase/migrations/20261008124940_gps_shift_work_date_evidence.sql'));
  await db.exec(sql('supabase/migrations/20261008160834_attendance_rollout_capabilities.sql'));
  await db.exec(`insert into companies values('10000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000001');
    insert into company_members values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000011','viewer'),('20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000011','owner');
    insert into workers(id,company_id,status,user_id,name) values('10000000-0000-0000-0000-000000000021','10000000-0000-0000-0000-000000000001','active','10000000-0000-0000-0000-000000000011','driver');
    insert into sites(id,company_id,name) values('10000000-0000-0000-0000-000000000031','10000000-0000-0000-0000-000000000001','site');
    insert into vehicles values('10000000-0000-0000-0000-000000000041','10000000-0000-0000-0000-000000000001',true);
    select set_config('test.actor','10000000-0000-0000-0000-000000000011',false);`);
  await db.exec(`set role authenticated; do $$ declare r jsonb; begin
    r:=public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001');
    if r->>'group_checkout_enabled'<>'false' or r->>'vehicle_usage_enabled'<>'false' or r->>'vehicle_meter_enabled'<>'false' then raise exception 'base-only capability not OFF'; end if;
    end $$; reset role;`);
  // Exact staged files from separately checked-out immutable PR head SHAs.
  await db.exec(sql(path.join(vehicleRoot,'supabase/migrations/20261008153425_vehicle_active_driver_claims.sql')));
  await db.exec(`insert into private.vehicle_usage_rollout(company_id) values('10000000-0000-0000-0000-000000000001');`);
  await db.exec(`set role authenticated; do $$ declare r jsonb; begin
    r:=public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001');
    if r->>'vehicle_usage_enabled'<>'false' or r->>'vehicle_meter_enabled'<>'false' then raise exception 'claims default not OFF'; end if;
    end $$; reset role;
    update private.vehicle_usage_rollout set enabled=true;`);
  await db.exec(`set role authenticated; do $$ begin
    if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'vehicle_meter_enabled'<>'false' then raise exception 'actual claims-only migration enabled meter'; end if;
    end $$; reset role;`);
  await db.exec(`alter table route_assignments add column is_active boolean not null default true;
    alter table vehicles add column odometer_km numeric(12,1) not null default 1000;
    alter table vehicles add column display_name text; alter table vehicles add column updated_by uuid; alter table vehicles add column updated_at timestamptz;
    alter table daily_report_workers add column vehicle_id uuid; alter table daily_report_workers add column route_assignment_id uuid; alter table daily_report_workers add column odometer_km numeric;`);
  await db.exec(sql('supabase/migrations/20261001232457_add_daily_report_vehicle_usage_rpc.sql'));
  await db.exec(sql(path.join(vehicleRoot,'supabase/migrations/20261008154433_vehicle_meter_snapshots.sql')));
  await db.exec(sql(path.join(groupRoot,'supabase/migrations/20261008154241_group_proxy_checkout_staged.sql')));
  await db.exec(`insert into private.group_checkout_rollout(company_id) values('10000000-0000-0000-0000-000000000001');`);
  await db.exec(`set role authenticated; do $$ declare r jsonb; begin
    r:=public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001');
    if r->>'group_checkout_enabled'<>'false' or r->>'vehicle_meter_enabled'<>'false' then raise exception 'actual staged migration discovery mismatch'; end if;
    end $$; reset role; update private.group_checkout_rollout set enabled=true;
    set role authenticated; do $$ begin
      if public.get_attendance_rollout_capabilities('10000000-0000-0000-0000-000000000001')->>'group_checkout_enabled'<>'false' then raise exception 'actual group without report attach enabled UI'; end if;
    end $$; reset role;`);
  await db.exec(sql(path.join(attachmentRoot,'supabase/migrations/20261008161708_group_report_source_attachment.sql')));
  await db.exec(sql(path.join(vehicleAttachmentRoot,'supabase/migrations/20261008162618_attach_vehicle_meter_to_report.sql')));
  // Load the repository's actual notification baseline, then the staged server
  // migration before capture, matching deployment timestamp order.
  await db.exec(`create table auth.users(id uuid primary key);
    alter table vehicles add column registration_number text;`);
  await db.exec(sql('tool/fixtures/source_member_notifications/20260919213000_add_app_notifications.sql'));
  await db.exec(sql('tool/fixtures/source_member_notifications/20260920214500_restrict_notification_table_grants.sql'));
  await db.exec(sql('supabase/migrations/20261008171216_source_member_notifications.sql'));
  await db.exec(sql('supabase/migrations/20261008173515_attendance_capture_failure_contract.sql'));
  await db.exec(`do $$ begin
    if exists(select 1 from private.source_notification_rollouts) or
       exists(select 1 from private.attendance_capture_rollouts) then
      raise exception 'notification or capture migration enabled company rows';
    end if;
  end $$;`);
  await db.exec(sql('supabase/tests/attendance_rollout_capabilities_staged_assertions.sql'));
  await db.exec(`do $$ begin
    if exists(select 1 from public.app_notifications) then raise exception 'OFF notification trigger emitted notifications'; end if;
    if not exists(select 1 from pg_trigger where tgname='attendance_capture_contract_guard') or not exists(select 1 from pg_trigger where tgname='source_vehicle_started_notification') then raise exception 'capture and notification triggers do not coexist'; end if;
  end $$;`);
  console.log('PASS combined capture + notifications + capabilities with actual staged claim/meter/proxy/report attachment migrations, scoped real RPCs and private gates (isolated fixture only)');
} catch (error) { console.error(error.message,error.where ?? ''); process.exitCode=1; }
finally { await db.close(); }
