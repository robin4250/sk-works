import fs from 'node:fs';
import assert from 'node:assert/strict';
const connectionString = process.env.SKO_RACE_DATABASE_URL;
const url = new URL(connectionString ?? 'postgres://invalid');
if (!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
    url.pathname !== '/sko_race_fixture') {
  throw new Error('Only local disposable sko_race_fixture database is permitted');
}
const pgModule = await import(process.argv[2]);
const Client = pgModule.Client ?? pgModule.default?.Client;
if (typeof Client !== 'function') {
  throw new Error('The pg runtime does not export a Client constructor');
}
const connections = [];
async function connect(name) {
  const client = new Client({ connectionString, application_name: name });
  await client.connect();
  await client.query("set statement_timeout='15s'; set lock_timeout='12s'");
  connections.push(client);
  return client;
}
const admin = await connect('sko-race-admin');
const a = await connect('sko-race-a');
const b = await connect('sko-race-b');
const read = (path) => fs.readFileSync(path, 'utf8');
const fixtures = 'tool/fixtures/attendance_race/';
const id = (n) => `10000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
async function initialize() {
  await admin.query('drop schema if exists private cascade; drop schema if exists auth cascade; drop schema public cascade; create schema public');
  await admin.query(`do $$ begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if; if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; end $$`);
  // DROP/CREATE public loses initdb's default PUBLIC schema usage grant.
  await admin.query('grant usage on schema public to authenticated');
  await admin.query(read(fixtures + 'schema.sql').replace('create role anon; create role authenticated;', ''));
  for (const path of ['20261008042058_fix_managed_attendance_overnight_chronology.sql', '20261008124940_gps_shift_work_date_evidence.sql']) {
    await admin.query(read('supabase/migrations/' + path));
  }
  await admin.query(read(fixtures + '20261008153425_vehicle_active_driver_claims.sql'));
  await admin.query(read(fixtures + '20261008154241_group_proxy_checkout_staged.sql'));
  await admin.query(`alter table route_assignments add column is_active boolean not null default true; alter table vehicles add column odometer_km numeric(12,1) not null default 1000; alter table vehicles add column updated_by uuid; alter table vehicles add column updated_at timestamptz; alter table daily_report_workers add column vehicle_id uuid; alter table daily_report_workers add column route_assignment_id uuid; alter table daily_report_workers add column odometer_km numeric;`);
  await admin.query(read('supabase/migrations/20261001232457_add_daily_report_vehicle_usage_rpc.sql'));
  await admin.query(read(fixtures + '20261008154433_vehicle_meter_snapshots.sql'));
  await admin.query('insert into companies values($1)', [id(1)]);
  for (const n of [2, 3]) {
    await admin.query("insert into company_members values($1,$2,'employee');", [id(1), id(n)]);
    await admin.query("insert into workers(id,company_id,status,user_id,name) values($1,$2,'active',$3,$4)", [id(n + 10), id(1), id(n), 'worker ' + n]);
  }
  await admin.query('insert into sites(id,company_id,name) values($1,$2,$3)', [id(4), id(1), 'race site']);
  await admin.query('insert into vehicles(id,company_id,is_active) values($1,$2,true)', [id(5), id(1)]);
  await admin.query('insert into private.vehicle_usage_rollout values($1,true);', [id(1)]);
  await admin.query('insert into private.group_checkout_rollout values($1,true);', [id(1)]);
  for (const [client, n] of [[a, 2], [b, 3]]) {
    await client.query('select set_config($1,$2,false)', ['test.actor', id(n)]);
    await client.query('set role authenticated');
  }
}
async function waitBothBlocked() {
  const deadline = Date.now() + 7000;
  while (Date.now() < deadline) {
    await admin.query('select pg_stat_clear_snapshot()');
    const result = await admin.query("select count(*)::int n from pg_stat_activity where application_name in ('sko-race-a','sko-race-b') and wait_event_type='Lock'");
    if (result.rows[0].n === 2) return;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error('Both independent connections did not reach the lock barrier');
}
const startSql = `insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,verification_mode,confirmed_at,created_by) values($1,$2,$3,$4,$5,'clock_in','manual','2026-01-31 20:00+09',$6)`;
try {
  await initialize();
  await admin.query('begin');
  await admin.query('select 1 from vehicles where id=$1 for update', [id(5)]);
  const first = a.query(startSql, [id(21), id(1), id(12), id(4), id(5), id(2)]);
  const second = b.query(startSql, [id(22), id(1), id(13), id(4), id(5), id(3)]);
  // Attach rejection handlers immediately while waiting for the lock barrier.
  const resultsPromise = Promise.allSettled([first, second]);
  await waitBothBlocked();
  await admin.query('commit');
  const results = await resultsPromise;
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.find(r => r.status === 'rejected').reason.code, '23505');
  assert.equal((await admin.query('select count(*)::int n from attendance_verifications')).rows[0].n, 1);
  assert.equal((await admin.query('select count(*)::int n from vehicle_usage_claims where ended_at is null')).rows[0].n, 1);
  console.log('PASS two connections: same vehicle has one driver; losing attendance INSERT rolls back');

  const winner = (await admin.query('select * from vehicle_usage_claims')).rows[0];
  const winnerActor = winner.driver_worker_id === id(12) ? id(2) : id(3);
  for (const client of [a, b]) {
    await client.query('select set_config($1,$2,false)', ['test.actor', winnerActor]);
  }
  await a.query(`insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,verification_mode,confirmed_at,source_clock_in_id,created_by) values($1,$2,$3,$4,'clock_out','manual','2026-02-01 05:00+09',$5,$6)`,
    [id(1), winner.driver_worker_id, id(4), id(5), winner.source_clock_in_id, winnerActor]);
  await admin.query('begin');
  await admin.query('select 1 from vehicle_usage_claims where source_clock_in_id=$1 for update', [winner.source_clock_in_id]);
  const meterSql = 'select public.record_vehicle_driver_meter($1,$2,900,55) result';
  const meterPromise = Promise.all([a.query(meterSql, [winner.source_clock_in_id, id(51)]), b.query(meterSql, [winner.source_clock_in_id, id(51)])]);
  meterPromise.catch(() => {});
  await waitBothBlocked();
  await admin.query('commit');
  const meters = await meterPromise;
  assert.deepEqual(meters[0].rows[0].result, meters[1].rows[0].result);
  assert.equal((await admin.query('select count(*)::int n from vehicle_meter_events')).rows[0].n, 1);
  assert.equal((await admin.query('select count(*)::int n from private.vehicle_meter_notice_outbox')).rows[0].n, 1);
  assert.equal(Number((await admin.query('select odometer_km from vehicles')).rows[0].odometer_km), 900);
  assert.equal(Number(meters[0].rows[0].result.distance_km), 55);
  console.log('PASS simultaneous meter retry: one immutable decrease event, baseline update and warning');

  await a.query('reset role'); await b.query('reset role');
  await initialize();
  // A rollout UPDATE takes its row lock before the guard runs. Meter reads
  // must not request that row lock while holding the shared company lock.
  await a.query(startSql, [id(71), id(1), id(12), id(4), id(5), id(2)]);
  await a.query(`insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,verification_mode,confirmed_at,source_clock_in_id,created_by) values($1,$2,$3,$4,'clock_out','manual','2026-02-01 05:00+09',$5,$6)`,
    [id(1), id(12), id(4), id(5), id(71), id(2)]);
  await b.query('reset role');
  await admin.query('begin');
  await admin.query("select pg_advisory_xact_lock(hashtextextended('vehicle-rollout:'||$1::text,0))", [id(1)]);
  const toggleMeterPromise = Promise.allSettled([
    a.query('select public.record_vehicle_driver_meter($1,$2,1050,null) result', [id(71), id(72)]),
    b.query('update private.vehicle_usage_rollout set enabled=false where company_id=$1 returning company_id', [id(1)]),
  ]);
  await waitBothBlocked();
  await admin.query('commit');
  const toggleMeter = await toggleMeterPromise;
  assert.equal(toggleMeter[1].status, 'fulfilled');
  assert.equal(toggleMeter[1].value.rowCount, 1);
  if (toggleMeter[0].status === 'rejected') {
    assert.equal(toggleMeter[0].reason.code, 'P0001');
    assert.match(toggleMeter[0].reason.message, /車両連携はまだ有効ではありません/);
  }
  assert.equal((await admin.query('select count(*)::int n from vehicle_meter_events')).rows[0].n,
    toggleMeter[0].status === 'fulfilled' ? 1 : 0);
  assert.equal(Number((await admin.query('select odometer_km from vehicles')).rows[0].odometer_km),
    toggleMeter[0].status === 'fulfilled' ? 1050 : 1000);
  console.log('PASS rollout toggle versus meter: no advisory/gate-row lock cycle, atomic result');
  await a.query('reset role');
  await initialize();

  // Deletion cascades and driver meter writes must use a consistent lock order.
  await a.query(startSql, [id(61), id(1), id(12), id(4), id(5), id(2)]);
  await a.query(`insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,verification_mode,confirmed_at,source_clock_in_id,created_by) values($1,$2,$3,$4,'clock_out','manual','2026-02-01 05:00+09',$5,$6)`,
    [id(1), id(12), id(4), id(5), id(61), id(2)]);
  await b.query('reset role');
  await admin.query('begin');
  await admin.query('select 1 from vehicles where id=$1 for update', [id(5)]);
  const deletionRace = Promise.allSettled([
    a.query('select public.record_vehicle_driver_meter($1,$2,1050,null) result', [id(61), id(62)]),
    b.query('delete from vehicles where id=$1 returning id', [id(5)]),
  ]);
  await waitBothBlocked();
  await admin.query('commit');
  const deletionResults = await deletionRace;
  assert.equal(deletionResults[1].status, 'fulfilled');
  assert.equal(deletionResults[1].value.rowCount, 1);
  if (deletionResults[0].status === 'rejected') {
    // Deletion winning the race invalidates the claim; it is a clear business
    // validation failure, never a deadlock or partially committed meter event.
    assert.equal(deletionResults[0].reason.code, 'P0001');
  }
  assert.equal((await admin.query('select count(*)::int n from vehicle_meter_events')).rows[0].n,
    deletionResults[0].status === 'fulfilled' ? 1 : 0);
  assert.equal((await admin.query('select count(*)::int n from private.vehicle_meter_notice_outbox')).rows[0].n, 0);
  assert.equal((await admin.query('select count(*)::int n from vehicle_usage_claims')).rows[0].n, 0);
  console.log('PASS meter versus vehicle deletion: serialization or explicit validation, no deadlock/partial meter event');
  await a.query('reset role');
  await initialize();

  // Group test excludes vehicle claims: vehicle/group ON compatibility remains separate.
  await a.query(startSql, [id(31), id(1), id(12), id(4), null, id(2)]);
  await b.query(startSql, [id(32), id(1), id(13), id(4), null, id(3)]);
  const sources = [id(31), id(32)];
  await admin.query('begin');
  await admin.query("select pg_advisory_xact_lock(hashtextextended($1,0))", [id(1) + ':' + id(4) + ':2026-01-31']);
  const callSql = 'select public.commit_group_checkout($1,$2::uuid[],$3) result';
  const groupResultsPromise = Promise.all([
    a.query(callSql, [id(31), sources, id(41)]),
    b.query(callSql, [id(32), sources, id(42)]),
  ]);
  // Prevent unhandled rejection while the supervisor observes the barrier.
  groupResultsPromise.catch(() => {});
  await waitBothBlocked();
  await admin.query('commit');
  const groupResults = await groupResultsPromise;
  assert.deepEqual(groupResults[0].rows[0].result, groupResults[1].rows[0].result);
  const retry = await a.query(callSql, [id(31), sources, id(41)]);
  assert.deepEqual(retry.rows[0].result, groupResults[0].rows[0].result);
  assert.equal((await admin.query("select count(*)::int n from attendance_verifications where event_type='clock_out'")).rows[0].n, 2);
  assert.equal((await admin.query("select count(*)::int n from attendance_verifications where event_type='clock_out' and evidence_origin='team_proxy' and latitude is null and photo_storage_path is null")).rows[0].n, 2);
  assert.equal((await admin.query('select count(*)::int n from private.group_checkout_requests')).rows[0].n, 2);
  console.log('PASS two participants: concurrent group checkout and retry create exactly one checkout per source');

  await a.query('reset role'); await b.query('reset role');
  await initialize();
  // Driver and passenger share the site. The passenger may proxy checkout,
  // but only the claimed driver may commit the final meter value.
  await a.query(startSql, [id(81), id(1), id(12), id(4), id(5), id(2)]);
  await b.query(startSql, [id(82), id(1), id(13), id(4), null, id(3)]);
  await admin.query('begin');
  await admin.query("select pg_advisory_xact_lock(hashtextextended('vehicle-rollout:'||$1::text,0))", [id(1)]);
  const personalCheckout = a.query(`insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,verification_mode,confirmed_at,source_clock_in_id,created_by) values($1,$2,$3,$4,'clock_out','manual','2026-02-01 05:00+09',$5,$6) returning id`,
    [id(1), id(12), id(4), id(5), id(81), id(2)]);
  const groupedCheckout = b.query(callSql, [id(82), [id(81), id(82)], id(83)]);
  const mixedPromise = Promise.allSettled([personalCheckout, groupedCheckout]);
  await waitBothBlocked();
  await admin.query('commit');
  const mixed = await mixedPromise;
  assert.equal(mixed[1].status, 'fulfilled');
  if (mixed[0].status === 'rejected') {
    assert.equal(mixed[0].reason.code, '23505');
  }
  assert.equal((await admin.query("select count(*)::int n from attendance_verifications where event_type='clock_out'")).rows[0].n, 2);
  const closedClaim = (await admin.query('select * from vehicle_usage_claims')).rows[0];
  assert.notEqual(closedClaim.ended_at, null);
  const driverOut = (await admin.query('select id,confirmed_at from attendance_verifications where source_clock_in_id=$1', [id(81)])).rows[0];
  assert.equal(closedClaim.source_clock_out_id, driverOut.id);
  assert.equal(closedClaim.ended_at.toISOString(), driverOut.confirmed_at.toISOString());
  assert.equal(closedClaim.work_date instanceof Date
    ? closedClaim.work_date.toISOString().slice(0, 10)
    : closedClaim.work_date, '2026-01-31');
  await assert.rejects(b.query('select public.record_vehicle_driver_meter($1,$2,1050,null)', [id(81), id(84)]),
    error => error.code === 'P0001' && /運転手本人だけ/.test(error.message));
  const driverMeter = await a.query('select public.record_vehicle_driver_meter($1,$2,1050,null) result', [id(81), id(84)]);
  assert.equal(Number(driverMeter.rows[0].result.distance_km), 50);
  assert.equal((await admin.query('select count(*)::int n from vehicle_meter_events')).rows[0].n, 1);
  assert.equal(Number((await admin.query('select odometer_km from vehicles')).rows[0].odometer_km), 1050);
  console.log('PASS combined ON: personal versus member proxy checkout releases driver once; meter remains driver-only');

} finally {
  await admin.query('rollback').catch(() => {});
  await Promise.all(connections.map(client => client.end()));
}
