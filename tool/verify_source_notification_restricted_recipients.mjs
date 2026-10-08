import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const {PGlite} = await import(process.argv[2]);
const db = new PGlite();
await db.exec(await fs.readFile(new URL('./fixtures/source_member_notifications/schema.sql', import.meta.url), 'utf8'));
const manifest = JSON.parse(await fs.readFile(new URL('./fixtures/source_member_notifications/manifest.json', import.meta.url), 'utf8'));
for (const item of manifest.files) {
  const bytes = await fs.readFile(new URL('./fixtures/source_member_notifications/' + item.path, import.meta.url));
  assert.equal(bytes.length, item.bytes);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), item.sha256);
  await db.exec(bytes.toString());
}
for (const name of ['20261008171216_source_member_notifications.sql', '20261008201729_vehicle_notification_settings_read.sql', '20261008204054_source_notification_active_recipients.sql']) {
  await db.exec(await fs.readFile(new URL('../supabase/migrations/' + name, import.meta.url), 'utf8'));
}
const migration = await fs.readFile(new URL('../supabase/migrations/20261008211227_source_notification_restricted_recipients.sql', import.meta.url), 'utf8');
await assert.rejects(db.exec(migration), /existing account deletion restrictions are required/);
// Synthetic deployed baseline; no real users or deletion jobs are loaded.
await db.exec(`create role service_role; create table private.account_deletion_jobs(id uuid primary key); create table private.account_deletion_access_restrictions(user_id uuid primary key,job_id uuid not null unique references private.account_deletion_jobs(id),restricted_at timestamptz not null default now()); alter table private.account_deletion_access_restrictions enable row level security; grant select,insert on private.account_deletion_access_restrictions to service_role;`);
await db.exec('grant select on private.account_deletion_access_restrictions to authenticated');
await assert.rejects(db.exec(migration), /client read access differs/);
await db.exec('revoke select on private.account_deletion_access_restrictions from authenticated');
await db.exec('alter table private.account_deletion_access_restrictions add column unexpected text');
await assert.rejects(db.exec(migration), /columns differ/);
await db.exec('alter table private.account_deletion_access_restrictions drop column unexpected');
await db.exec('alter table private.account_deletion_access_restrictions force row level security');
await assert.rejects(db.exec(migration), /owner\/RLS contract differs/);
await db.exec('alter table private.account_deletion_access_restrictions no force row level security');
await db.exec('create role mismatched_helper_owner; alter function private.source_notification_recipient_eligible(uuid,uuid) owner to mismatched_helper_owner');
await assert.rejects(db.exec(migration), /helper\/restriction owner contract differs/);
const owner = (await db.query('select current_user u')).rows[0].u;
await db.exec(`alter function private.source_notification_recipient_eligible(uuid,uuid) owner to ${owner}`);
await db.exec(migration);
await db.exec(`create or replace function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())$$;`);
const [c, admin, recipient, aw, rw, site, car, report, job] = Array.from({length: 9}, (_, i) => `60000000-0000-0000-0000-${String(i + 1).padStart(12, '0')}`);
await db.exec(`insert into auth.users values('${admin}'),('${recipient}'); insert into companies values('${c}'); insert into company_members values('${c}','${admin}','admin'),('${c}','${recipient}','viewer'); insert into workers values('${aw}','${c}','${admin}','登録者','active'),('${rw}','${c}','${recipient}','受信者','active'); insert into vehicles values('${car}','${c}','番号','車両'); insert into private.source_notification_rollouts values('${c}',true); set test.uid='${admin}'; set role authenticated; select public.set_vehicle_notification_assignees('${car}',array['${recipient}']::uuid[]); reset role;`);
async function start(number) {
  const source = `70000000-0000-0000-0000-${String(number).padStart(12, '0')}`;
  await db.exec(`begin; insert into attendance_verifications values('${source}','${c}','${aw}','${site}',null,'2026-10-09','clock_in',null,null,'${car}'); insert into vehicle_usage_claims values('${source}','${c}','${car}','${aw}','2026-10-09'); commit;`);
}
await start(1);
assert.equal((await db.query('select count(*)::int n from app_notifications')).rows[0].n, 1);
const notice = (await db.query('select id from app_notifications')).rows[0].id;
await db.exec(`insert into private.account_deletion_jobs values('${job}'); insert into private.account_deletion_access_restrictions(user_id,job_id) values('${recipient}','${job}'); set role authenticated;`);
assert.equal((await db.query('select private.account_access_allowed() allowed')).rows[0].allowed, true);
const settings = (await db.query(`select public.get_vehicle_notification_settings('${car}') t`)).rows[0].t;
assert.deepEqual(settings.user_ids, [recipient]);
assert(!settings.candidates.some(r => r.user_id === recipient));
await assert.rejects(db.query(`select public.set_vehicle_notification_assignees('${car}',array['${recipient}']::uuid[])`), /active vehicle/);
await assert.rejects(db.query(`select private.source_notification_recipient_eligible('${c}','${recipient}')`), /permission denied/);
await assert.rejects(db.query('select * from private.account_deletion_access_restrictions'), /permission denied/);
await db.exec(`set test.uid='${recipient}'`);
await assert.rejects(db.query(`select public.get_source_notification_target('${notice}')`), /account unavailable/);
await db.exec(`reset role; set test.uid='${admin}'`);
await start(2);
assert.equal((await db.query('select count(*)::int n from app_notifications')).rows[0].n, 1);
assert.equal((await db.query('select count(*)::int n from private.source_notification_receipts')).rows[0].n, 1);
assert.deepEqual((await db.query('select user_ids from private.vehicle_notification_assignees')).rows[0].user_ids, [recipient]);
await db.exec(`insert into daily_reports values('${report}','${c}','${site}',null,'2026-10-09','${admin}'); insert into daily_report_workers values('${report}','${aw}'),('${report}','${rw}');`);
for (const worker of [aw, rw]) {
  const source = (await db.query('select gen_random_uuid() id')).rows[0].id;
  await db.exec(`insert into attendance_verifications values('${source}','${c}','${worker}','${site}',null,'2026-10-09','clock_in',null,'${report}',null); insert into attendance_verifications values(gen_random_uuid(),'${c}','${worker}','${site}',null,'2026-10-09','clock_out','${source}','${report}',null);`);
}
await db.exec('set role authenticated');
assert.equal((await db.query(`select public.publish_saved_group_report_notifications('${report}') n`)).rows[0].n, 0);
await db.exec('reset role');
assert.equal((await db.query('select count(*)::int n from private.account_deletion_access_restrictions')).rows[0].n, 1);
assert.equal((await db.query(`select status from workers where id='${rw}'`)).rows[0].status, 'active');
assert.equal((await db.query(`select role from company_members where user_id='${recipient}'`)).rows[0].role, 'viewer');
// Only this synthetic fixture clears a restriction to check eligible behavior.
await db.exec(`delete from private.account_deletion_access_restrictions where user_id='${recipient}'; set role authenticated;`);
assert.equal((await db.query(`select public.publish_saved_group_report_notifications('${report}') n`)).rows[0].n, 1);
assert.equal((await db.query(`select public.publish_saved_group_report_notifications('${report}') n`)).rows[0].n, 0);
await db.exec(`reset role; update private.source_notification_rollouts set enabled=false; insert into private.account_deletion_access_restrictions(user_id,job_id) values('${recipient}','${job}');`);
await start(3);
assert.equal((await db.query('select count(*)::int n from app_notifications')).rows[0].n, 2);
assert.equal((await db.query('select count(*)::int n from private.source_notification_receipts')).rows[0].n, 2);
await db.exec('set role anon');
await assert.rejects(db.query('select * from private.account_deletion_access_restrictions'), /permission denied/);
await assert.rejects(db.query(`select private.source_notification_recipient_eligible('${c}','${recipient}')`), /permission denied/);
await db.close();
console.log('PASS: existing schema/ACL guards, caller remains allowed while recipient is restricted, vehicle/group skip, setter/candidates/target refusal, saved selection/ledger preserved, no role/status mutation, OFF no send');
