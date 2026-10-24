// Disposable fixture only. Exercises generated binder, not a production endpoint.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const run = promisify(execFile);
const dir = await mkdtemp(join(tmpdir(), 'finalizer-binder-native-'));
const unit = 'docs/candidates/expense_finalizer_invoice_revision_20261024.sql.review-only';
const generator = 'tool/security/expense_finalizer_compat/prepare.py';
let client, phase = 'destination', checks = 0;
const eq = (a, b, label) => {assert.deepEqual(a, b, label); checks++;};
const rejects = async (fn, pattern) => {await assert.rejects(fn, pattern); checks++;};
try {
  assert.equal(process.env.CI, 'true');
  assert.equal(process.platform, 'linux');
  assert.ok(!Object.keys(process.env).some(k => /^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)));
  const destination = new URL(process.env.SKO_CONSENT_FIXTURE_URL);
  assert.equal(destination.hostname, '127.0.0.1');
  assert.equal(destination.port, '5432');
  assert.equal(destination.username, 'postgres');
  assert.equal(destination.password, 'fixture-only');
  assert.equal(destination.pathname, '/sko_document_consent_fixture');
  // Reuse exact PR1348 original-failure / corrected financial proof first.
  phase = 'existing-financial-source-proof';
  await run(process.execPath, ['tool/verify_expense_finalizer_invoice_compat_native.mjs', process.argv[2]],
    {timeout: 300000, maxBuffer: 1024 * 1024});
  const pg = (await import(process.argv[2])).default;
  client = new pg.Client({connectionString: destination.href});
  await client.connect();
  const q = async sql => (await client.query(sql)).rows[0]?.v;
  const source = () => q("select md5(prosrc) v from pg_proc where oid='private.expense_cost_finalize()'::regprocedure");
  eq(await source(), '26d214245ad95159dab04059710840bd');
  // Reconstitute the original source from the unchanged public migration + v2
  // source patch. Never reverse every JSON revision reference indiscriminately.
  phase = 'restore-exact-old-source';
  const costs = await readFile('supabase/migrations/20261012142138_expense_document_original_costs.sql', 'utf8');
  const start = costs.search(/create\s+(?:or\s+replace\s+)?function\s+private\.expense_cost_finalize\s*\(/i);
  assert.ok(start >= 0);
  const tail = costs.slice(start);
  const delimiter = /\bas\s+(\$[A-Za-z_0-9]*\$)/i.exec(tail);
  const end = tail.indexOf(delimiter[1], delimiter.index + delimiter[0].length) + delimiter[1].length;
  await client.query(tail.slice(0, end).replace(/^create\s+(?:or\s+replace\s+)?function/i, 'create or replace function') + ';');
  const direction = await readFile('docs/candidates/expense_payment_direction_v2_20261019.sql.review-only', 'utf8');
  const patch = /do \$patch_finalize\$[\s\S]*?end \$patch_finalize\$;/i.exec(direction);
  assert.ok(patch);
  await client.query(patch[0]);
  eq(await source(), '22ff4377666ec56ccc4b261cf380e9c0');

  phase = 'explicit-synthetic-event-surroundings';
  // The production event bodies are reviewed separately. These clearly declared
  // local hooks test catalog preservation + transactional NOTIFY surroundings.
  // They do not claim to recover or reproduce the extension hooks' full bodies.
  await client.query("create function private.fixture_binder_event_noop() returns event_trigger language plpgsql as $$begin return;end$$;create function private.fixture_binder_pgrst_notify() returns event_trigger language plpgsql as $$begin notify pgrst,'reload schema';end$$;");
  for (const [name, event, tags] of [
    ['issue_graphql_placeholder', 'sql_drop', "when tag in ('DROP EXTENSION')"],
    ['pgrst_ddl_watch', 'ddl_command_end', ''],
    ['pgrst_drop_watch', 'sql_drop', ''],
    ['issue_pg_cron_access', 'ddl_command_end', "when tag in ('CREATE EXTENSION')"],
    ['issue_pg_net_access', 'ddl_command_end', "when tag in ('CREATE EXTENSION')"],
    ['issue_pg_graphql_access', 'ddl_command_end', "when tag in ('CREATE EXTENSION')"],
  ]) await client.query(`create event trigger ${name} on ${event} ${tags} execute function private.${name === 'pgrst_ddl_watch' ? 'fixture_binder_pgrst_notify' : 'fixture_binder_event_noop'}()`);
  const query = await readFile('tool/security/expense_finalizer_compat/preflight.read-only.sql', 'utf8');
  await client.query("set search_path=public,extensions;set timezone='UTC';set datestyle='ISO, YMD'");
  const before = (await client.query(query)).rows[0].checkpoint;
  const beforePath = join(dir, 'before.json');
  await writeFile(beforePath, JSON.stringify(before));
  const generate = async (mode, sha) => {
    const out = join(dir, mode + '.sql');
    const args = [generator, mode, '--before', beforePath, '--unit', unit, '--output', out];
    if (sha) args.push('--postgres-sha256', sha);
    await run('python3', args);
    return readFile(out, 'utf8');
  };
  const results = await client.query(await generate('fingerprint'));
  const fingerprint = results.flatMap(r => r.rows ?? []).find(r => r.fingerprint)?.fingerprint;
  assert.ok(fingerprint);
  eq(fingerprint.observation, before, 'PostgreSQL fingerprint covers exact observer object');
  assert.match(fingerprint.sha256, /^[0-9a-f]{64}$/);
  const install = await generate('install', fingerprint.sha256);
  const postflight = await generate('postflight', fingerprint.sha256);
  const restore = await generate('restore', fingerprint.sha256);
  const data = async () => q(`select jsonb_build_object(${before.relations.map(r => {
    const name = r.name.includes('.') ? r.name : 'public.' + r.name;
    return `'${name}',(select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') from ${name} x)`;
  }).join(',')}) v`);
  const originalData = await data();
  const rollback = () => client.query('rollback');

  phase = 'changed-catalog-refused-before-ddl';
  await client.query('alter function private.expense_cost_finalize() cost 101');
  await rejects(() => client.query(install), /full finalizer checkpoint differs/);
  await rollback();
  eq(await source(), '22ff4377666ec56ccc4b261cf380e9c0');
  eq(await data(), originalData);
  await client.query('alter function private.expense_cost_finalize() cost 100');

  phase = 'owner-acl-and-trigger-drift-refused';
  await client.query('create role fixture_finalizer_owner nologin');
  await client.query('alter function private.expense_cost_finalize() owner to fixture_finalizer_owner');
  await rejects(() => client.query(install), /full finalizer checkpoint differs/);
  await rollback();
  eq(await source(), '22ff4377666ec56ccc4b261cf380e9c0');
  await client.query('alter function private.expense_cost_finalize() owner to postgres');
  await client.query('grant execute on function private.expense_cost_finalize() to authenticated');
  await rejects(() => client.query(install), /full finalizer checkpoint differs/);
  await rollback();
  await client.query('revoke execute on function private.expense_cost_finalize() from authenticated');
  await client.query('alter table invoices disable trigger expense_cost_invoice_finalization');
  await rejects(() => client.query(install), /full finalizer checkpoint differs/);
  await rollback();
  await client.query('alter table invoices enable trigger expense_cost_invoice_finalization');
  eq((await client.query(query)).rows[0].checkpoint, before, 'Explicitly restored fixture drift equals exact original catalog');
  eq(await data(), originalData);

  phase = 'late-failure-rolls-back-body-and-data';
  const late = install.replace(/commit;\s*$/, "do $$begin raise exception 'synthetic binder late failure';end$$;commit;\n");
  await rejects(() => client.query(late), /synthetic binder late failure/);
  await rollback();
  eq(await source(), '22ff4377666ec56ccc4b261cf380e9c0');
  eq((await client.query(query)).rows[0].checkpoint, before);
  eq(await data(), originalData);

  phase = 'generated-install-and-read-only-postflight';
  await client.query(install);
  eq(await source(), '26d214245ad95159dab04059710840bd');
  const afterInstall = await data();
  eq(afterInstall, originalData, 'All protected synthetic rows unchanged');
  await client.query(postflight);
  eq(await data(), afterInstall, 'Read-only postflight preserves rows');
  const attemptedWrite = postflight.replace(/rollback;\s*$/, 'update public.invoices set id=id where false;rollback;\n');
  await rejects(() => client.query(attemptedWrite), /read.only transaction/i);
  await rollback();
  eq(await data(), afterInstall, 'Postflight transaction actually refuses writes');
  await rejects(() => client.query(install), /full finalizer checkpoint differs/);
  await rollback();
  eq(await source(), '26d214245ad95159dab04059710840bd');

  phase = 'changed-catalog-refuses-postflight-and-restore';
  await client.query('alter function private.expense_cost_finalize() cost 101');
  await rejects(() => client.query(postflight), /full original catalog differs/);
  await rollback();
  await rejects(() => client.query(restore), /full original catalog differs/);
  await rollback();
  eq(await source(), '26d214245ad95159dab04059710840bd');
  await client.query('alter function private.expense_cost_finalize() cost 100');

  phase = 'conditional-source-only-restore';
  await client.query(restore);
  eq(await source(), '22ff4377666ec56ccc4b261cf380e9c0');
  eq((await client.query(query)).rows[0].checkpoint, before);
  eq(await data(), originalData);
  await rejects(() => client.query(restore), /patched finalizer source differs/);
  await rollback();
  eq(await source(), '22ff4377666ec56ccc4b261cf380e9c0');
  console.log(JSON.stringify({pass: true, checks, engine: 'native PostgreSQL17',
    generated_install_postflight_restore: true, changed_catalog_refused: true,
    late_failure_rollback: true, application_rows_preserved: true,
    synthetic_event_surroundings: true, production_changed: false}));
} catch (error) {
  console.error(JSON.stringify({pass: false, phase, message: String(error.message).slice(0, 400), production_changed: false}));
  process.exitCode = 1;
} finally {
  if (client) await client.end();
  await rm(dir, {recursive: true, force: true});
}
