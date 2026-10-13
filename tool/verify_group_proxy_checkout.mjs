import fs from 'node:fs';
const { PGlite } = await import(process.argv[2]);
const db = new PGlite();
try {
  const baseline = fs.readFileSync('tool/verify_gps_shift_work_date.mjs', 'utf8');
  const setup = baseline.match(/await db\.exec\(`([\s\S]*?)`\);/);
  if (!setup) throw new Error('GPS fixture schema unavailable');
  await db.exec(setup[1]);
  await db.exec(`create table companies(id uuid primary key);
    alter table attendance_verifications alter column verification_mode set not null;
    alter table attendance_verifications add constraint fixture_mode check(verification_mode in ('manual','location','location_photo','gps_auto'));
    alter table attendance_verifications add constraint fixture_gps check(verification_mode='manual' or (latitude is not null and longitude is not null));
    alter table attendance_verifications add constraint fixture_photo check(verification_mode<>'location_photo' or photo_storage_path is not null);
    grant usage on schema private to authenticated;`);
  await db.exec(fs.readFileSync('supabase/migrations/20261008042058_fix_managed_attendance_overnight_chronology.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261008124940_gps_shift_work_date_evidence.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261008154241_group_proxy_checkout_staged.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/tests/group_proxy_checkout_assertions.sql','utf8'));
  console.log('PASS staged proxy checkout: gate, roster scope, early leave, idempotency, origin and existing RLS');
} catch (error) { console.error(error.message,error.where ?? ''); process.exitCode=1; }
finally { await db.close(); }
