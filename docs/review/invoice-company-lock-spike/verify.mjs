// Synthetic isolation experiment. Never use against an application database.
import assert from 'node:assert/strict';
import pg from 'pg';
const url = new URL(process.env.FIXTURE_URL || 'http://invalid');
if (process.env.CI !== 'true' || url.protocol !== 'postgresql:' ||
    url.hostname !== '127.0.0.1' || url.port !== '5432' ||
    url.pathname !== '/sko_lock_fixture' ||
    Object.keys(process.env).some(k => /^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))
  throw Error('isolated CI fixture only');
const clients = Array.from({length: 4}, () => new pg.Client({connectionString:url.toString()}));
const [setup, approval, same, other] = clients;
const sql = "select pg_advisory_xact_lock(hashtextextended($1::text, 319847))";
try {
  await Promise.all(clients.map(c => c.connect()));
  const exists = await setup.query("select to_regclass('public.synthetic_work') as t");
  assert.equal(exists.rows[0].t, null);
  await setup.query("create table public.synthetic_work(company_id uuid not null, v text not null)");
  const a = '10000000-0000-0000-0000-000000000001';
  const b = '10000000-0000-0000-0000-000000000002';

  // Writer obtains the same company lock BEFORE any write. Other company can
  // write immediately, same company times out; no production trigger exists.
  await approval.query('begin');
  await approval.query(sql,[a]);
  await other.query('begin');
  await other.query("set local lock_timeout='750ms'");
  await other.query(sql,[b]);
  await other.query('insert into public.synthetic_work values($1,$2)',[b,'other company']);
  await other.query('commit');
  await same.query('begin');
  await same.query("set local lock_timeout='300ms'");
  await assert.rejects(() => same.query(sql,[a]), e => e.code === '55P03');
  await same.query('rollback');
  await approval.query('rollback');

  // Lock waits until a cooperating pending writer commits; a READ COMMITTED
  // query executed after acquisition observes its insertion.
  await same.query('begin');
  await same.query(sql,[a]);
  await same.query('insert into public.synthetic_work values($1,$2)',[a,'prior writer']);
  await approval.query('begin');
  const acquired=approval.query(sql,[a]);
  await same.query('commit');
  await acquired;
  const current=await approval.query('select count(*)::int as n from public.synthetic_work where company_id=$1',[a]);
  assert.equal(current.rows[0].n,1);
  await approval.query('rollback');

  // An unmodified direct write ignores advisory locks entirely: this is an
  // explicit release blocker, not evidence that the design is deployable.
  await approval.query('begin');
  await approval.query(sql,[a]);
  await same.query('begin');
  await same.query("set local lock_timeout='750ms'");
  await same.query('insert into public.synthetic_work values($1,$2)',[a,'bypass']);
  await same.query('commit');
  const bypass=await approval.query("select count(*)::int as n from public.synthetic_work where company_id=$1 and v='bypass'",[a]);
  assert.equal(bypass.rows[0].n,1);
  await approval.query('rollback');
  console.log('PASS: cooperative same-company serialization; other company proceeds; direct-write bypass reproduced');
} finally {
  await Promise.allSettled(clients.map(c=>c.end()));
}
