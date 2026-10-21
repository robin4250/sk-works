import fs from 'node:fs';
import assert from 'node:assert/strict';

const { PGlite } = await import(process.argv[2]);
const db = new PGlite();
const read = p => fs.readFileSync(p, 'utf8');
const dir = 'tool/security/attendance_minute_guard/';
const message = '出勤と同じ時刻のため退勤できません。時刻が進んでから再度お試しください';
const cid = '10000000-0000-0000-0000-000000000001';
const uid = '10000000-0000-0000-0000-000000000002';
const wid = '10000000-0000-0000-0000-000000000003';
const sid = '10000000-0000-0000-0000-000000000004';
const rid = '10000000-0000-0000-0000-000000000005';
let checks = 0;
async function rejected(query) {
  await assert.rejects(query, e => e.message === message && e.code === '22023');
  checks++;
}
async function start(at, route = false) {
  return (await db.query(`insert into attendance_verifications
    (company_id,worker_id,site_id,route_assignment_id,event_type,confirmed_at)
    values($1,$2,$3,$4,'clock_in',$5) returning id`,
  [cid,wid,route ? null : sid,route ? rid : null,at])).rows[0].id;
}
async function end(id, at, route = false) {
  return db.query(`insert into attendance_verifications
    (company_id,worker_id,site_id,route_assignment_id,event_type,confirmed_at,source_clock_in_id)
    values($1,$2,$3,$4,'clock_out',$5,$6) returning id`,
  [cid,wid,route ? null : sid,route ? rid : null,at,id]);
}
try {
  // Reuse the existing schema and actual production guard/management functions.
  // Never import the production adapter or connect to a remote database.
  const fixture = read('tool/verify_gps_shift_work_date.mjs');
  const setup = fixture.split('await db.exec(`')[1]?.split('`);')[0];
  assert.ok(setup?.includes('create table attendance_verifications'));
  await db.exec(setup);
  await db.exec(read('supabase/migrations/20261008042058_fix_managed_attendance_overnight_chronology.sql'));
  await db.exec(read('supabase/migrations/20261008124940_gps_shift_work_date_evidence.sql'));
  await db.exec(`insert into company_members values('${cid}','${uid}','admin');
    insert into workers(id,company_id,status,user_id,name) values('${wid}','${cid}','active','${uid}','fixture');
    insert into sites(id,company_id,name) values('${sid}','${cid}','fixture');
    insert into route_assignments values('${rid}','${cid}','fixture');
    select set_config('test.actor','${uid}',false);`);
  const proc = "'private.validate_attendance_shift_evidence()'::regprocedure";
  const metadata = async () => (await db.query(`select to_jsonb(p)-'prosrc' value from pg_proc p where oid=${proc}`)).rows[0].value;
  const beforeMetadata = await metadata();
  const old = await start('2026-10-01T08:00:01+09:00');
  const oldEnd = (await end(old,'2026-10-01T08:00:59+09:00')).rows[0].id;
  const beforeRows = (await db.query('select jsonb_agg(to_jsonb(a) order by id) value from attendance_verifications a')).rows[0].value;
  await db.exec(read(dir+'forward.sql.review-only'));
  assert.deepEqual(await metadata(),beforeMetadata); checks++;
  assert.deepEqual((await db.query('select jsonb_agg(to_jsonb(a) order by id) value from attendance_verifications a')).rows[0].value,beforeRows); checks++;
  await db.query("update attendance_verifications set photo_storage_path='fixture/link' where id=$1",[oldEnd]); checks++;
  await assert.rejects(db.query("update attendance_verifications set confirmed_at=confirmed_at+interval '1 minute' where id=$1",[oldEnd]),/immutable/); checks++;
  for (const route of [false,true]) {
    const id = await start(route ? '2026-10-02T08:00:01+09:00' : '2026-10-03T08:00:01+09:00',route);
    const day = route ? '02' : '03';
    await rejected(end(id,`2026-10-${day}T08:00:01+09:00`,route));
    await rejected(end(id,`2026-10-${day}T08:00:59.999+09:00`,route));
    await end(id,`2026-10-${day}T08:01:00+09:00`,route); checks++;
  }
  const edge = await start('2026-10-04T23:59:59.999+09:00');
  await end(edge,'2026-10-05T00:00:00+09:00'); checks++;
  const nextDay = await start('2026-10-06T08:00:30+09:00');
  await end(nextDay,'2026-10-07T08:00:30+09:00'); checks++;
  await db.exec("set timezone='America/New_York'");
  const offset = await start('2026-10-08T08:00:01+09:00');
  await rejected(end(offset,'2026-10-07T23:00:59Z'));
  await end(offset,'2026-10-07T23:01:00Z'); checks++;
  // Capture/outbox retries carry the same ID and source, never confirmed_at.
  // Use an isolated server clock default to exercise a minute advancing between
  // two transactions without changing the logical request or photograph.
  await db.exec(`create function private.fixture_server_clock() returns timestamptz
    language sql as $$select current_setting('test.server_clock')::timestamptz$$;
    alter table attendance_verifications alter column confirmed_at
      set default private.fixture_server_clock();`);
  const pendingSource = await start('2026-10-08T09:00:01+09:00');
  const pendingId = '30000000-0000-0000-0000-000000000001';
  const retrySql = `insert into attendance_verifications
    (id,company_id,worker_id,site_id,event_type,source_clock_in_id,photo_storage_path)
    values($1,$2,$3,$4,'clock_out',$5,'fixture/immutable-photo') returning confirmed_at`;
  const retryArgs = [pendingId,cid,wid,sid,pendingSource];
  await db.query("select set_config('test.server_clock',$1,false)",['2026-10-08T09:00:59+09:00']);
  await rejected(db.query(retrySql,retryArgs));
  await db.query("select set_config('test.server_clock',$1,false)",['2026-10-08T09:01:00+09:00']);
  const retried = (await db.query(retrySql,retryArgs)).rows[0];
  assert.equal(new Date(retried.confirmed_at).toISOString(),'2026-10-08T00:01:00.000Z'); checks++;
  // Actual administrative RPC: rejected replacement rolls back deletions,
  // report/signature updates and every new row in the same statement.
  const managed = times => JSON.stringify([{worker_id:wid,site_id:sid,date:'2026-10-09',clock_in:times[0],clock_out:times[1],man_days:1}]);
  await db.query("select public.force_manage_attendance('upsert',$1::jsonb)",[managed(['08:00','17:00'])]);
  await db.exec("update daily_reports set signature_json='{\"strokes\":[[1,2]]}',signer_name='fixture' where report_date='2026-10-09'");
  const protectedState = async () => (await db.query(`select jsonb_build_object(
    'attendance',(select jsonb_agg(to_jsonb(a) order by id) from attendance_verifications a),
    'reports',(select jsonb_agg(to_jsonb(d) order by id) from daily_reports d),
    'entries',(select jsonb_agg(to_jsonb(e) order by id) from attendance_entries e),
    'payroll',(select jsonb_agg(to_jsonb(p)) from payroll_history p)) value`)).rows[0].value;
  const protectedBefore = await protectedState();
  await rejected(db.query("select public.force_manage_attendance('upsert',$1::jsonb)",[managed(['08:00','08:00'])]));
  assert.deepEqual(await protectedState(),protectedBefore); checks++;
  await db.query("select public.force_manage_attendance('upsert',$1::jsonb)",[managed(['08:00','08:01'])]); checks++;
  // Group inserts are atomic: an eligible first member cannot persist when
  // another member's explicit source is still in the same minute.
  const first = await start('2026-10-10T07:59:00+09:00');
  const second = await start('2026-10-10T08:00:01+09:00');
  const count = (await db.query('select count(*) n from attendance_verifications')).rows[0].n;
  await rejected(db.query(`insert into attendance_verifications(company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id)
    values($1,$2,$3,'clock_out','2026-10-10T08:00:59+09:00',$4),
          ($1,$2,$3,'clock_out','2026-10-10T08:00:59+09:00',$5)`,[cid,wid,sid,first,second]));
  assert.equal((await db.query('select count(*) n from attendance_verifications')).rows[0].n,count); checks++;
  const installed = (await db.query(`select pg_get_functiondef(${proc}) definition`)).rows[0].definition;
  await assert.rejects(db.exec(read(dir+'forward.sql.review-only')),/prerequisite differs/);
  await db.exec('rollback');
  assert.equal((await db.query(`select pg_get_functiondef(${proc}) definition`)).rows[0].definition,installed); checks++;
  const bodyMd5 = (await db.query(`select md5(prosrc) hash from pg_proc where oid=${proc}`)).rows[0].hash;
  console.log(`PASS ${checks} minute boundaries, unchanged request retry, management rollback, atomic group, historical linking and catalog guards; candidate_body_md5=${bodyMd5}`);
} finally { await db.close(); }
