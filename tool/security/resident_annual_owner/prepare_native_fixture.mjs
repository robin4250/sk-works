// Disposable CI setup only; no production connection or owner credentials.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {setupPayrollScopeFixture} from '../../payroll_scope_fixture_setup.mjs';

assert.equal(process.env.CI, 'true');
assert.equal(process.env.SKO_ANNUAL_OWNER_NATIVE_FIXTURE, 'isolated-loopback-only');
assert.equal(process.platform, 'linux');
assert.ok(!Object.keys(process.env).some(k => /^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)));
const ca = fs.readFileSync(process.env.SKO_ANNUAL_FIXTURE_CA);
const pg = (await import(process.argv[2])).default;
const client = new pg.Client({host:'127.0.0.1',port:5432,user:'postgres',
  password:'fixture-only',database:'postgres',ssl:{ca,rejectUnauthorized:true}});
await client.connect();
const db={query:(...args)=>client.query(...args),exec:sql=>client.query(sql)};
let phase='empty-pg17-tls-check';
try {
  const version=Number((await db.query('show server_version_num')).rows[0].server_version_num);
  assert.ok(version>=170000 && version<180000);
  assert.equal((await db.query('select ssl from pg_stat_ssl where pid=pg_backend_pid()')).rows[0].ssl,true);
  assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
  phase='existing-payroll-scope-fixture';
  await setupPayrollScopeFixture(db);
  phase='existing-lock-order-migration';
  await db.exec(fs.readFileSync(path.join(process.cwd(),'supabase/migrations/20261009171504_payroll_refresh_scope_order.sql'),'utf8'));
  phase='fixture-login-roles';
  await db.exec("reset role;create role service_role nologin;create role cli_login_annual_native login superuser password 'fixture-only';create role cli_login_annual_wrong login password 'fixture-only';");
  // Fixture-only server default, never applied by the owner runner. This proves
  // the boundary when that relationship exists, not that real CLI supplies it.
  phase='fixture-server-default-role';
  await db.exec("alter role cli_login_annual_native set role='postgres';");
  phase='wrong-role-readonly-identity-grants';
  await db.exec("grant usage on schema auth to cli_login_annual_wrong;grant execute on function auth.uid() to cli_login_annual_wrong;");
  console.log(JSON.stringify({fixture_prepared:true,native_postgres:17,tls:true,
    cli_default_role_simulated:true,actual_cli_provider_verified:false,production_connected:false}));
} catch {
  console.log(JSON.stringify({fixture_prepared:false,phase,production_connected:false}));
  process.exitCode=1;
} finally {await client.end();}
