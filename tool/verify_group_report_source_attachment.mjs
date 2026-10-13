import fs from 'node:fs';
import path from 'node:path';
const { PGlite } = await import(process.argv[2]);
const groupRoot = process.argv[3];
if (!groupRoot) throw new Error('Immutable staged group checkout dependency root is required.');
const db = new PGlite();
const sql = file => fs.readFileSync(file, 'utf8');
try {
  const setup = sql('tool/verify_gps_shift_work_date.mjs').match(/await db\.exec\(`([\s\S]*?)`\);/);
  if (!setup) throw new Error('GPS fixture schema unavailable');
  await db.exec(setup[1]);
  await db.exec(`create table companies(id uuid primary key);
    alter table attendance_verifications alter column verification_mode set not null;
    alter table attendance_verifications add constraint fixture_mode check(verification_mode in ('manual','location','location_photo','gps_auto'));
    alter table attendance_verifications add constraint fixture_gps check(verification_mode='manual' or (latitude is not null and longitude is not null));
    alter table attendance_verifications add constraint fixture_photo check(verification_mode<>'location_photo' or photo_storage_path is not null);
    alter table daily_reports enable row level security;
    create policy fixture_report_read on daily_reports for select to authenticated using(exists(select 1 from company_members m where m.company_id=daily_reports.company_id and m.user_id=auth.uid()));
    alter table daily_report_workers enable row level security;
    create policy fixture_roster_read on daily_report_workers for select to authenticated using(exists(select 1 from daily_reports d where d.id=report_id));
    revoke insert,update,delete on daily_reports,daily_report_workers,attendance_verifications from authenticated;
    grant insert on attendance_verifications to authenticated;`);
  await db.exec(sql('supabase/migrations/20261008042058_fix_managed_attendance_overnight_chronology.sql'));
  await db.exec(sql('supabase/migrations/20261008124940_gps_shift_work_date_evidence.sql'));
  await db.exec(sql(path.join(groupRoot,'supabase/migrations/20261008154241_group_proxy_checkout_staged.sql')));
  // Exercise actual candidate/proxy commit contracts, including early departure.
  await db.exec(sql(path.join(groupRoot,'supabase/tests/group_proxy_checkout_assertions.sql')));
  await db.exec(`select set_config('test.blocked','false',false);`);
  await db.exec(sql('supabase/migrations/20261008161708_group_report_source_attachment.sql'));
  await db.exec(sql('supabase/tests/group_report_source_attachment_assertions.sql'));
  console.log('PASS scoped group report source attachment: saved roster, real proxy/early leave, signed retry, original evidence and real roles/RLS (isolated fixture)');
} catch (error) { console.error(error.message,error.where ?? ''); process.exitCode=1; }
finally { await db.close(); }
