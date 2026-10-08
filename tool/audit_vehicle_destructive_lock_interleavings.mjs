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

// Separate, unpublished audit lane: never imported by the proven race workflow.
const scenario = process.argv[3];
if (!['company-start', 'company-meter', 'admin-meter'].includes(scenario)) {
  throw new Error('Select company-start, company-meter, or admin-meter explicitly');
}
async function waitBlocked(observer, name) {
  const deadline = Date.now() + 7000;
  while (Date.now() < deadline) {
    await observer.query('select pg_stat_clear_snapshot()');
    const state = await observer.query('select wait_event_type,wait_event from pg_stat_activity where application_name=$1', [name]);
    if (state.rows[0]?.wait_event_type === 'Lock') {
      console.log('Observed genuine blocking', name, state.rows[0]);
      return;
    }
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error('Required independent contender never blocked: ' + name);
}
const startSql = `insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,verification_mode,confirmed_at,created_by) values($1,$2,$3,$4,$5,'clock_in','manual','2026-01-31 20:00+09',$6)`;
const meterSql = 'select public.record_vehicle_driver_meter($1,$2,1050,null) result';
async function closedShift() {
  await a.query(startSql, [id(91), id(1), id(12), id(4), id(5), id(2)]);
  await a.query(`insert into attendance_verifications(company_id,worker_id,site_id,vehicle_id,event_type,verification_mode,confirmed_at,source_clock_in_id,created_by) values($1,$2,$3,$4,'clock_out','manual','2026-02-01 05:00+09',$5,$6)`,
    [id(1), id(12), id(4), id(5), id(91), id(2)]);
}
try {
  await initialize();
  if (scenario.startsWith('company-')) {
    if (scenario === 'company-meter') await closedShift();
    await b.query('reset role');
    await admin.query('begin');
    // DELETE's actual first lock is this same parent row FOR UPDATE. Keep it
    // until its cascade statement, to expose the interleaving deterministically.
    await admin.query('select 1 from companies where id=$1 for update', [id(1)]);
    const pending = scenario === 'company-start'
      ? a.query(startSql, [id(91), id(1), id(12), id(4), id(5), id(2)])
      : a.query(meterSql, [id(91), id(92)]);
    const pendingOutcome = Promise.allSettled([pending]);
    await waitBlocked(b, 'sko-race-a');
    const deletion = admin.query('delete from companies where id=$1', [id(1)]);
    const [deletionOutcome] = await Promise.allSettled([deletion]);
    if (deletionOutcome.status === 'fulfilled') await admin.query('commit');
    else await admin.query('rollback');
    const [operationOutcome] = await pendingOutcome;
    const summary = [deletionOutcome, operationOutcome].map(result => ({
      status: result.status,
      code: result.status === 'rejected' ? result.reason.code : null,
      message: result.status === 'rejected' ? result.reason.message : null,
    }));
    console.log(JSON.stringify({scenario, summary}));
    // A deadlock is a blocker, not accepted evidence or a passing reproduction.
    assert.equal(summary.some(result => result.code === '40P01'), false,
      'Company cascade and vehicle operation have a lock-order deadlock');
    assert.equal(summary.some(result => result.code === '55P03'), false,
      'Lock timeout must not disguise a cycle');
    console.log('PASS company cascade contention has no deadlock');
  } else {
    await closedShift();
    await admin.query("insert into company_members values($1,$2,'admin')", [id(1), id(20)]);
    await b.query('reset role');
    await b.query('begin');
    await b.query('select 1 from vehicle_usage_claims where source_clock_in_id=$1 for update', [id(91)]);
    // This is the actual row lock that attendance DELETE's FK cascade takes.
    // The manager then invokes the unmodified existing approved correction RPC.
    await b.query('select set_config($1,$2,true)', ['test.actor', id(20)]);
    await b.query('set local role authenticated');
    const meter = a.query(meterSql, [id(91), id(92)]);
    const meterOutcome = Promise.allSettled([meter]);
    await waitBlocked(admin, 'sko-race-a');
    const correction = await b.query('select public.force_manage_attendance($1,$2::jsonb) n',
      ['delete', JSON.stringify([{worker_id:id(12), date:'2026-01-31', mode:'work', site_id:id(4)}])]);
    assert.equal(correction.rows[0].n, 1);
    await b.query('commit');
    const [result] = await meterOutcome;
    assert.equal(result.status, 'rejected');
    assert.equal(result.reason.code, 'P0001');
    assert.match(result.reason.message, /運転手本人だけ/);
    assert.equal((await admin.query('select count(*)::int n from vehicle_meter_events')).rows[0].n, 0);
    assert.equal(Number((await admin.query('select odometer_km from vehicles')).rows[0].odometer_km), 1000);
    assert.equal((await admin.query('select count(*)::int n from attendance_verifications')).rows[0].n, 0);
    console.log('PASS authorized correction wins: waiting meter rejects without event or baseline mutation');
    await a.query('reset role'); await b.query('reset role');
    await initialize(); await closedShift();
    await admin.query("insert into company_members values($1,$2,'admin')", [id(1), id(20)]);
    const committed = await a.query(meterSql, [id(91), id(92)]);
    await b.query('select set_config($1,$2,false)', ['test.actor', id(20)]);
    await b.query('select public.force_manage_attendance($1,$2::jsonb)',
      ['delete', JSON.stringify([{worker_id:id(12), date:'2026-01-31', mode:'work', site_id:id(4)}])]);
    const retained = await admin.query('select to_jsonb(e) result from vehicle_meter_events e');
    assert.deepEqual(retained.rows[0].result, committed.rows[0].result);
    assert.equal(Number((await admin.query('select odometer_km from vehicles')).rows[0].odometer_km), 1050);
    console.log('PASS meter-first: authorized correction preserves immutable committed event and current baseline');
  }
} finally {
  await Promise.all(connections.map(async client => {
    await client.query('rollback').catch(() => {});
    await client.end();
  }));
}
