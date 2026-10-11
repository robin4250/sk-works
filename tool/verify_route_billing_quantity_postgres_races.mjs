import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const connectionString = process.env.SKO_BILLING_RACE_DATABASE_URL;
const url = new URL(connectionString ?? 'postgres://invalid');
const database = 'sko_billing_quantity_race_fixture';
if (!['postgres:', 'postgresql:'].includes(url.protocol) || url.search || url.hash || !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) || url.pathname !== `/${database}`) throw new Error('Only local disposable billing fixture permitted');
const pg = await import(process.argv[2]);
const Client = pg.Client ?? pg.default?.Client;
const clients = [];
async function connect(name) {
  const client = new Client({connectionString, application_name: name});
  const p = client.connectionParameters;
  if (!['127.0.0.1', 'localhost', '::1'].includes(p.host) || p.database !== database || Number(p.port) !== Number(url.port || 5432)) throw new Error('Effective connection must remain local disposable fixture');
  await client.connect(); clients.push(client);
  await client.query("set statement_timeout='20s';set lock_timeout='15s'");
  return client;
}
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [company, worker, user, manager, customerA, customerB, siteA, siteB, reportA, reportB, reportB2] = Array.from({length: 11}, (_, i) => id(i + 1));
const settle = promise => { promise.catch(() => {}); return promise; };
let admin, a, b, observer;
async function blocked() {
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) {
    await observer.query('select pg_stat_clear_snapshot()');
    const r = await observer.query("select count(*)::int n from pg_stat_activity where application_name in ('billing-a','billing-b') and wait_event_type='Lock'");
    if (r.rows[0].n === 2) return;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error('Two actual blocked billing connections not observed');
}
const actor = (c, uid) => c.query(`set test.uid='${uid}';set role authenticated`);
const submit = (c, reports, allocations) => c.query('select public.submit_route_customer_day_allocations($1,$2,$3) v', [worker, reports, JSON.stringify(allocations)]);
const approve = (c, request, site, price) => c.query("select public.decide_route_billing_quantity($1,1,'approve','confirmed',1,$2,$3) v", [request.id, site, price]);
try {
  admin = await connect('billing-admin'); a = await connect('billing-a'); b = await connect('billing-b'); observer = await connect('billing-observer');
  assert.match((await admin.query('show server_version')).rows[0].server_version, /^17\./);
  assert.equal((await admin.query("select count(*)::int n from pg_namespace where nspname in ('private','auth')")).rows[0].n, 0, 'fixture must be fresh; never delete existing schemas');
  const verifier = await fs.readFile(new URL('./verify_route_billing_quantity_allocations.mjs', import.meta.url), 'utf8');
  const fixture = verifier.match(/await db\.exec\(`([\s\S]*?)`\);/)[1];
  assert.ok(!fixture.includes('${'), 'fixture must remain literal SQL');
  await admin.query(fixture);
  await admin.query(await fs.readFile(new URL('../supabase/tests/route_customer_day_billing_allocations_schema.sql', import.meta.url), 'utf8'));
  await admin.query('insert into company_members values($1,$2,\'employee\'),($1,$3,\'manager\')', [company, user, manager]);
  await admin.query('insert into workers values($1,$2,\'本人\')', [worker, company]);
  await admin.query('insert into customers values($1,$2,\'会社A\'),($3,$2,\'会社B\')', [customerA, company, customerB]);
  await admin.query('insert into sites values($1,$2,\'現場A\',$3),($4,$2,\'現場B\',$5)', [siteA, company, customerA, siteB, customerB]);
  await admin.query('insert into site_financial_settings values($1,$2,20000,0,0),($1,$3,25000,0,0)', [company, siteA, siteB]);
  for (const [report, site, seed] of [[reportA, siteA, 20], [reportB, siteB, 30], [reportB2, siteB, 40]]) {
    await admin.query("insert into private.route_visit_reports values($1,$2,$3,'2026-10-11','completed',$4,$5,'現場',$6,$7,$8)", [report, company, user, JSON.stringify([{worker_id: worker, worker_name: '本人'}]), site, id(seed), id(seed + 1), id(seed + 2)]);
  }
  await admin.query("insert into attendance_entries values($1,1);", [id(90)]);
  await admin.query("insert into invoices values($1,'finalized',$2)", [id(91), JSON.stringify({amount: 12345})]);
  const canonical = async () => (await admin.query("select jsonb_build_object('attendance',(select jsonb_agg(to_jsonb(e)) from attendance_entries e),'invoices',(select jsonb_agg(to_jsonb(i)) from invoices i),'reports',(select jsonb_agg(to_jsonb(r)) from private.route_visit_reports r)) v")).rows[0].v;
  const before = await canonical();
  await actor(a, user); await actor(b, user);
  await admin.query('begin');
  await admin.query('select pg_advisory_xact_lock(hashtextextended($1,0))', [`route-billing:${company}${worker}`]);
  const allocations = [{customer_id: customerA, quantity: 1}, {customer_id: customerB, quantity: 1}];
  const p = settle(submit(a, [reportA, reportB], allocations));
  const q = settle(submit(b, [reportA, reportB], allocations));
  await blocked(); await admin.query('commit');
  const submissions = await Promise.all([p, q]);
  const first = submissions[0].rows[0].v, second = submissions[1].rows[0].v;
  assert.deepEqual(first.map(r => r.id), second.map(r => r.id));
  assert.equal(first.reduce((sum, r) => sum + Number(r.quantity), 0), 2);
  assert.equal((await admin.query('select count(*)::int n from private.route_billing_quantity_requests')).rows[0].n, 2);
  const requestA = first.find(r => r.customer_id === customerA), requestB = first.find(r => r.customer_id === customerB);
  await actor(a, manager); await actor(b, manager);
  // Registered invoice source must also govern approval eligibility.
  await admin.query('insert into trade_companies values($1,$2)', [id(80), company]);
  await admin.query("insert into trade_company_contracts values($1,$2,'daily',42000)", [company, id(80)]);
  await admin.query("insert into site_calculation_source_preferences values($1,$2,'invoice','trade_company',$3)", [company, siteA, id(80)]);
  const option = async () => (await a.query('select public.route_billing_quantity_request_detail($1) v', [requestA.id])).rows[0].v.site_options[0];
  assert.equal((await option()).unit_price_yen, 42000); assert.equal((await option()).man_day_method, true);
  for (const method of ['monthly', 'square_meter', 'contract', 'none']) {
    await admin.query('update trade_company_contracts set contract_method=$1', [method]);
    assert.equal((await option()).man_day_method, false);
    await assert.rejects(approve(a, requestA, siteA, 20000), /evidenced/);
  }
  await admin.query("update trade_company_contracts set contract_method='daily',daily_rate_yen=0");
  await assert.rejects(approve(a, requestA, siteA, 20000), /evidenced/);
  await admin.query("update site_calculation_source_preferences set source='site'");
  await admin.query('update site_financial_settings set billing_contract_amount_yen=99999 where site_id=$1', [siteA]);
  assert.equal((await option()).unit_price_yen, 20000); assert.equal((await option()).man_day_method, true);
  await admin.query('begin'); await admin.query('select id from private.route_billing_quantity_requests where id=$1 for update', [requestA.id]);
  const x = settle(approve(a, requestA, siteA, 20000)), y = settle(approve(b, requestA, siteA, 20000));
  await blocked(); await admin.query('commit');
  const approvals = await Promise.all([x, y]);
  assert.equal(approvals[0].rows[0].v.status, 'approved');
  assert.deepEqual(approvals[0].rows[0].v, approvals[1].rows[0].v);
  assert.equal((await admin.query('select count(*)::int n from private.route_billing_quantity_audit where request_id=$1', [requestA.id])).rows[0].n, 1);
  // Evidence/quantity revision and old approval compete on the same request.
  await actor(b, user);
  await admin.query('begin'); await admin.query('select id from private.route_billing_quantity_requests where id=$1 for update', [requestB.id]);
  const oldApproval = settle(approve(a, requestB, siteB, 25000));
  const revision = settle(submit(b, [reportB, reportB2], [{customer_id: customerB, quantity: 0.5}]));
  await blocked(); await admin.query('commit');
  const outcomes = await Promise.allSettled([oldApproval, revision]);
  assert.equal(outcomes[1].status, 'fulfilled');
  if (outcomes[0].status === 'rejected') assert.equal(outcomes[0].reason.code, '40001');
  const final = (await admin.query('select * from private.route_billing_quantity_requests where id=$1', [requestB.id])).rows[0];
  assert.equal(final.status, 'pending'); assert.equal(final.version, 2); assert.equal(Number(final.quantity), 0.5); assert.equal(final.unit_price_yen, null);
  assert.deepEqual(await canonical(), before, 'canonical attendance, visit reports and finalized invoice unchanged');
  console.log('PASS PostgreSQL 17 dual-connection customer allocations, idempotent approval, revision/approval race, total2, canonical/finalized records unchanged');
} finally {
  await Promise.allSettled(clients.map(async c => { try { await c.query('rollback'); } finally { await c.end(); } }));
}
