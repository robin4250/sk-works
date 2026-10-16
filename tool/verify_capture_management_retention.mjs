import fs from 'node:fs';
const { PGlite } = await import(process.argv[2]);
const db = new PGlite();
try {
  // Reuse only the existing synthetic bootstrap SQL, not its assertions. Fail
  // closed if that source layout changes rather than running a partial fixture.
  const harness = fs.readFileSync('tool/verify_attendance_capture_failure.mjs', 'utf8');
  const start = 'await db.exec(`';
  const end = '\n  `);';
  const a = harness.indexOf(start);
  const b = harness.indexOf(end, a);
  if (a < 0 || b < 0 || !harness.slice(a + start.length, b).includes('create schema auth; create schema private;')) {
    throw new Error('capture fixture bootstrap changed; review the retention harness');
  }
  await db.exec(harness.slice(a + start.length, b));
  await db.exec(fs.readFileSync('supabase/migrations/20261008042058_fix_managed_attendance_overnight_chronology.sql', 'utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261008124940_gps_shift_work_date_evidence.sql', 'utf8'));
  await db.exec(`create table public.companies(id uuid primary key);
    alter table public.attendance_verifications add constraint attendance_verifications_check check (verification_mode='manual' or (latitude is not null and longitude is not null));
    alter table public.attendance_verifications add constraint attendance_verifications_check1 check (verification_mode<>'location_photo' or photo_storage_path is not null);
    alter table public.attendance_verifications add constraint retention_fixture_report_fk foreign key(daily_report_id) references public.daily_reports(id) on delete set null;`);
  await db.exec(fs.readFileSync('supabase/migrations/20261008173515_attendance_capture_failure_contract.sql', 'utf8'));
  const assertions = fs.readFileSync('supabase/tests/attendance_capture_management_retention_assertions.sql', 'utf8');
  // PGlite executes one submitted SQL script atomically. Commit setup before
  // testing an explicit business rollback so it does not roll back the fixture.
  const boundary = '\nbegin;\nselect private.retention_fixture_manage';
  const split = assertions.indexOf(boundary);
  if (split < 0) throw new Error('retention transaction boundary missing');
  await db.exec(assertions.slice(0, split));
  await db.exec(assertions.slice(split));
  console.log('PASS existing management loss reproduced; fixture-only archive preserves original capture/report, atomic failure and rollback');
} catch (error) {
  console.error(error.message, error.where ?? ''); process.exitCode = 1;
} finally { await db.close(); }
