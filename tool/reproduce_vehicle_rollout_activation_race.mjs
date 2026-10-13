// Verify that activation serializes with every vehicle start, including OFF.
// Success requires both safe orderings, never accepting the former unsafe state.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const connectionString = process.env.SKO_RACE_DATABASE_URL;
const url = new URL(connectionString ?? 'postgres://invalid');
if (!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
    url.pathname !== '/sko_race_fixture') {
  throw new Error('Only local disposable sko_race_fixture database is permitted');
}
const pg = await import(process.argv[2]);
const Client = pg.Client ?? pg.default?.Client;
const clients = [];
async function connect(name) {
  const client = new Client({ connectionString, application_name: name });
  await client.connect();
  await client.query("set statement_timeout='10s'; set lock_timeout='8s'");
  clients.push(client);
  return client;
}
const read = path => fs.readFileSync(path, 'utf8');
const id = n => `10000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
try {
  const supervisor = await connect('sko-activation-supervisor');
  const starter = await connect('sko-activation-starter');
  const activator = await connect('sko-activation-activator');
  await supervisor.query('drop schema if exists private cascade; drop schema if exists auth cascade; drop schema public cascade; create schema public');
  await supervisor.query(`do $$ begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if; if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; end $$`);
  await supervisor.query('grant usage on schema public to authenticated');
  await supervisor.query(read('tool/fixtures/attendance_race/schema.sql').replace('create role anon; create role authenticated;', ''));
  for (const file of ['20261008042058_fix_managed_attendance_overnight_chronology.sql', '20261008124940_gps_shift_work_date_evidence.sql']) {
    await supervisor.query(read('supabase/migrations/' + file));
  }
  await supervisor.query(read('tool/fixtures/attendance_race/20261008153425_vehicle_active_driver_claims.sql'));
  await supervisor.query('insert into companies values($1)', [id(1)]);
  await supervisor.query("insert into company_members values($1,$2,'employee')", [id(1), id(2)]);
  await supervisor.query("insert into workers(id,company_id,status,user_id,name) values($1,$2,'active',$3,'driver')", [id(3), id(1), id(2)]);
  await supervisor.query('insert into sites(id,company_id,name) values($1,$2,$3)', [id(4), id(1), 'race site']);
  await supervisor.query('insert into vehicles(id,company_id,is_active) values($1,$2,true)', [id(5), id(1)]);
  async function waitForActivationLock(name) {
    const deadline = Date.now() + 7000;
    while (Date.now() < deadline) {
      await supervisor.query('select pg_stat_clear_snapshot()');
      const state = await supervisor.query(
        "select wait_event_type from pg_stat_activity where application_name=$1", [name]);
      if (state.rows[0]?.wait_event_type === 'Lock') return;
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    throw new Error(`Expected ${name} to wait for the shared company activation lock`);
  }
  async function clearCase() {
    await supervisor.query('delete from attendance_verifications');
    await supervisor.query('delete from private.vehicle_usage_rollout');
  }
  async function start(idNumber) {
    await starter.query('begin');
    await starter.query('select set_config($1,$2,true)', ['test.actor', id(2)]);
    await starter.query('set local role authenticated');
    return starter.query(`insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,verification_mode,confirmed_at,created_by) values($1,$2,$3,$4,$5,'clock_in','manual','2026-01-31 20:00+09',$6)`,
      [id(idNumber), id(1), id(3), id(4), id(5), id(2)]);
  }
  for (const gate of ['absent', 'false']) {
    await clearCase();
    if (gate === 'false') {
      await supervisor.query('insert into private.vehicle_usage_rollout values($1,false)', [id(1)]);
    }
    await start(6);
    // OFF trigger has finished but its company lock must remain until COMMIT.
    assert.equal((await activator.query('select count(*)::int n from attendance_verifications')).rows[0].n, 0);
    const enableSql = gate === 'absent'
      ? 'insert into private.vehicle_usage_rollout values($1,true)'
      : 'update private.vehicle_usage_rollout set enabled=true where company_id=$1';
    const enable = activator.query(enableSql, [id(1)]);
    const enableOutcome = Promise.allSettled([enable]);
    await waitForActivationLock('sko-activation-activator');
    await starter.query('commit');
    const [outcome] = await enableOutcome;
    assert.equal(outcome.status, 'rejected');
    assert.equal(outcome.reason.code, 'P0001');
    assert.match(outcome.reason.message, /resolve pre-rollout vehicle starts before enabling/);
    const result = (await supervisor.query(`select
      coalesce((select enabled from private.vehicle_usage_rollout where company_id=$1),false) enabled,
      (select count(*)::int from attendance_verifications where event_type='clock_in') starts,
      (select count(*)::int from vehicle_usage_claims) claims`, [id(1)])).rows[0];
    assert.deepEqual(result, { enabled: false, starts: 1, claims: 0 });
    console.log(`PASS activation (${gate} gate): waits for OFF start then rejects committed unresolved shift`);

    // Opposite order: activation holds its company lock first; start must wait
    // and subsequently observe enabled state rather than skipping its claim.
    await clearCase();
    if (gate === 'false') {
      await supervisor.query('insert into private.vehicle_usage_rollout values($1,false)', [id(1)]);
    }
    await activator.query('begin');
    await activator.query(enableSql, [id(1)]);
    const pendingStart = start(7);
    pendingStart.catch(() => {});
    await waitForActivationLock('sko-activation-starter');
    await activator.query('commit');
    await pendingStart;
    await starter.query('commit');
    const safe = (await supervisor.query(`select
      (select enabled from private.vehicle_usage_rollout where company_id=$1) enabled,
      (select count(*)::int from attendance_verifications where event_type='clock_in') starts,
      (select count(*)::int from vehicle_usage_claims) claims`, [id(1)])).rows[0];
    assert.deepEqual(safe, { enabled: true, starts: 1, claims: 1 });
    console.log(`PASS activation-first (${gate} gate): waiting start observes ON and creates atomic claim`);
  }
  await clearCase();
  await starter.query('begin isolation level repeatable read');
  await starter.query('select set_config($1,$2,true)', ['test.actor', id(2)]);
  await starter.query('set local role authenticated');
  await assert.rejects(starter.query(`insert into attendance_verifications(id,company_id,worker_id,site_id,vehicle_id,event_type,verification_mode,confirmed_at,created_by) values($1,$2,$3,$4,$5,'clock_in','manual','2026-01-31 20:00+09',$6)`,
    [id(8), id(1), id(3), id(4), id(5), id(2)]), error =>
      error.code === 'P0001' && /requires read committed isolation/.test(error.message));
  await starter.query('rollback');
  await activator.query('begin isolation level repeatable read');
  await assert.rejects(activator.query('insert into private.vehicle_usage_rollout values($1,true)', [id(1)]),
    error => error.code === 'P0001' && /require read committed isolation/.test(error.message));
  await activator.query('rollback');
  assert.equal((await supervisor.query('select count(*)::int n from attendance_verifications')).rows[0].n, 0);
  console.log('PASS stale-snapshot isolation is explicitly rejected for both start and activation');
} finally {
  await Promise.all(clients.map(async client => {
    await client.query('rollback').catch(() => {});
    await client.end();
  }));
}
