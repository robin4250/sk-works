import fs from 'node:fs/promises';
import assert from 'node:assert/strict';

// This runner is for a fresh, disposable Native PostgreSQL 17 fixture only.
// It never accepts a hosted/project database, inherited libpq host, or schema reset.
const connectionString = process.env.SKO_ROUTE_EXPLICIT_FINALIZATION_DATABASE_URL;
const database = 'sko_route_explicit_fixture';
const url = new URL(connectionString ?? 'postgres://invalid');
if (!['postgres:', 'postgresql:'].includes(url.protocol) || url.search || url.hash ||
    !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
    url.pathname !== `/${database}`) {
  throw new Error('Only a local disposable route explicit-finalization fixture is permitted');
}
const pg = await import(process.argv[2]);
const Client = pg.Client ?? pg.default?.Client;
const clients = [];
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
let checks = 0;
function equal(actual, expected, message) { assert.deepEqual(actual, expected, message); checks++; }
function ok(value, message) { assert.ok(value, message); checks++; }
async function rejects(action, expected, message) {
  await assert.rejects(action, expected, message); checks++;
}
async function connect(name) {
  const client = new Client({connectionString, application_name: name});
  const p = client.connectionParameters;
  if (!['127.0.0.1', 'localhost', '::1'].includes(p.host) || p.database !== database ||
      Number(p.port) !== Number(url.port || 5432)) {
    throw new Error('Effective connection must remain the local disposable route fixture');
  }
  await client.connect();
  clients.push(client);
  await client.query("set statement_timeout='20s'; set lock_timeout='15s'");
  return client;
}
async function value(client, sql, params = []) { return (await client.query(sql, params)).rows[0].v; }
function settle(promise) { promise.catch(() => {}); return promise; }
async function waitForLocks(observer, count) {
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) {
    await observer.query('select pg_stat_clear_snapshot()');
    const r = await observer.query("select count(*)::int n from pg_stat_activity where application_name in ('route-explicit-a','route-explicit-b') and wait_event_type='Lock'");
    if (r.rows[0].n >= count) return;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error(`Actual blocked Native connections not observed: ${count}`);
}

// The rest of this fixture is bound to the reviewed route SQL API. The parent
// SQL owner integrates this runner in the same candidate; do not use a product
// database or replace signature/authorization routines with JavaScript mocks.

const root = new URL('../../..', import.meta.url);
const repoFile = path => fs.readFile(new URL(path, root), 'utf8');
const sqlPath = process.argv[3] ?? new URL('./explicit-route-finalization.sql.review-only', import.meta.url);
const restorePath = process.argv[4] ?? new URL('./explicit-route-finalization-restore-unused.sql.review-only', import.meta.url);
const company = id(1), creator = id(2), member = id(3), outsider = id(4), foreign = id(5);
const otherCompany = id(6), source = id(7), route = id(8), stop = id(9);
const worker = id(10), memberWorker = id(11), outsiderWorker = id(12), foreignWorker = id(13);
const sid = actor => id(100 + Number(actor.slice(-3)));
const day = '2026-10-26';
const signature = n => ({strokes: [[{x: 0.1, y: 0.2}, {x: 0.2 + n / 100, y: 0.8}]]});
const sourceTuple = row => ['source_clock_in_id','route_assignment_id','route_stop_id','start_capture_id','end_capture_id'].map(k => row[k]);
let admin, a, b, observer;
async function asActor(client, actor, session = sid(actor)) {
  await client.query('reset role');
  await client.query("select set_config('test.uid',$1,false),set_config('test.claims',$2,false)",
    [actor, JSON.stringify({sub: actor, role: 'authenticated', session_id: session, is_anonymous: false})]);
  await client.query('set role authenticated');
}
const read = (client, args) => value(client, 'select public.read_route_visit_report($1,$2,$3,$4,$5) v', args);
const sign = (client, rid, role, name, strokes) => value(client, 'select public.save_route_visit_report_signature($1,$2,$3,$4) v', [rid, role, name, strokes]);
const finalize = (client, row) => value(client, 'select public.finalize_route_visit_report($1,$2,$3) v', [row.id, row.report_updated_at, row.signature_scope_fingerprint]);
const edit = (client, row, reason = '手当を実入力に訂正') => value(client, 'select public.start_route_visit_report_finalization_edit($1,$2,$3,$4) v', [row.id, row.report_updated_at, row.signature_scope_fingerprint, reason]);
const saveDraft = (client, args, description, workers) => value(client, 'select public.save_route_visit_report_draft($1,$2,$3,$4,$5,$6,$7) v', [...args, description, workers]);
async function protectedState() {
  return value(admin, `select jsonb_build_object(
    'reports',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.daily_reports x),
    'attendance',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.attendance_entries x),
    'verification',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from public.attendance_verifications x)) v`);
}
async function originalCatalogue() {
  return value(admin, `select coalesce(jsonb_agg(v order by v->>'signature'),'[]') v from (
    select jsonb_build_object('oid',p.oid::text,'signature',p.oid::regprocedure::text,
      'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),
      'config',p.proconfig,'acl',p.proacl::text,'security_definer',p.prosecdef,
      'volatility',p.provolatile,'parallel',p.proparallel) v
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','private','auth','checkout_report_registration_private') and p.prokind='f') x`);
}
async function moduleState() {
  const tables = (await admin.query("select tablename from pg_tables where schemaname='explicit_route_finalization_private' order by tablename")).rows;
  const result = {};
  for (const {tablename} of tables) {
    assert.match(tablename, /^[a-z_]+$/);
    result[tablename] = (await admin.query(`select coalesce(jsonb_agg(v order by v::text),'[]') v from (select to_jsonb(t) v from explicit_route_finalization_private.${tablename} t) x`)).rows[0].v;
  }
  return result;
}
async function newVisit(offset, {enable = true} = {}) {
  const start = id(offset), end = id(offset + 1), args = [source, route, stop, start, end];
  const capture = (key, kind) => ({id: key, company_id: company, created_by: creator,
    source_clock_in_id: source, route_assignment_id: route, route_stop_id: stop,
    worker_id: worker, visit_kind: kind, start_capture_id: start, stop_label: '合成の訪問現場', work_date: day});
  await admin.query('insert into private.test_captures values($1,$2),($3,$4)', [start, capture(start,'start'), end, capture(end,'end')]);
  await asActor(a, creator);
  let row = await value(a, 'select public.choose_route_visit_report($1,$2,$3,$4,$5,true) v', args);
  if (enable) await admin.query('insert into explicit_route_finalization_private.reports(report_id,company_id,enabled) values($1,$2,true)', [row.id, company]);
  row = await saveDraft(a, args, '合成の実作業内容', [{worker_id: worker, overtime_hours: 1, allowance_label: '合成手当', allowance_amount: 100}]);
  return {args, row};
}
async function bothSign(visit, offset = 0) {
  await asActor(a, creator);
  await sign(a, visit.row.id, 'reporter', `合成報告者${offset}`, signature(offset + 1));
  await asActor(b, member);
  return sign(b, visit.row.id, 'responsible', `合成責任者${offset}`, signature(offset + 2));
}
try {
  admin = await connect('route-explicit-admin');
  a = await connect('route-explicit-a');
  b = await connect('route-explicit-b');
  observer = await connect('route-explicit-observer');
  assert.match((await admin.query('show server_version')).rows[0].server_version, /^17\./);
  equal((await admin.query("select count(*)::int n from pg_namespace where nspname in ('private','auth','checkout_report_registration_private','explicit_route_finalization_private')")).rows[0].n, 0, 'fresh fixture only; never drop schemas');
  const originalRunner = await repoFile('tool/verify_route_visit_reports.mjs');
  const fixture = originalRunner.match(/await db\.exec\(`([\s\S]*?)`\);/)[1];
  ok(!fixture.includes('${'), 'reuse the literal baseline fixture without interpolated mocks');
  await admin.query(fixture);
  await admin.query(`create role service_role; create schema checkout_report_registration_private;
    alter table public.workers add column user_id uuid;
    create table auth.users(id uuid primary key,is_anonymous boolean,banned_until timestamptz);
    create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
    create function auth.jwt() returns jsonb language sql stable as $$select nullif(current_setting('test.claims',true),'')::jsonb$$;`);
  const registration = await repoFile('docs/candidates/checkout_report_registration.sql.review-only');
  const actorFunction = registration.match(/create function checkout_report_registration_private\.current_actor\(\)[\s\S]*?end \$\$;/);
  ok(actorFunction, 'reuse the actual live-session actor helper');
  await admin.query(actorFunction[0]);
  await admin.query('revoke all on function checkout_report_registration_private.current_actor() from public,anon,authenticated,service_role');
  await admin.query(await repoFile('supabase/migrations/20261011121738_route_visit_report_documents.sql'));
  await admin.query('insert into public.company_members values($1,$2),($1,$3),($1,$4),($5,$6)', [company,creator,member,outsider,otherCompany,foreign]);
  await admin.query('insert into public.workers(id,company_id,name,user_id) values($1,$2,$3,$4),($5,$2,$6,$7),($8,$2,$9,$10),($11,$12,$13,$14)',
    [worker,company,'合成本人',creator,memberWorker,'合成現場メンバー',member,outsiderWorker,'合成の非参加者',outsider,foreignWorker,otherCompany,'合成他社',foreign]);
  await admin.query('insert into public.route_stops values($1,$2,null)', [stop,route]);
  for (const actor of [creator,member,outsider,foreign]) {
    await admin.query('insert into auth.users values($1,false,null)', [actor]);
    await admin.query('insert into auth.sessions values($1,$2,null)', [sid(actor), actor]);
  }
  await admin.query('insert into public.attendance_verifications(id,worker_id,company_id,route_assignment_id,work_date,event_type) values($1,$2,$3,$4,$5,$6)',
    [id(90),memberWorker,company,route,day,'clock_in']);
  await admin.query('insert into public.daily_reports values($1)', [id(91)]);
  await admin.query('insert into public.attendance_entries values($1)', [id(92)]);
  const protectedBefore = await protectedState();
  const catalogueBefore = await originalCatalogue();
  const installSql = await fs.readFile(sqlPath, 'utf8');
  const restoreSql = await fs.readFile(restorePath, 'utf8');
  await admin.query(installSql);
  equal((await admin.query('select count(*)::int n from explicit_route_finalization_private.rollout')).rows[0].n, 0, 'default OFF has no company rollout rows');
  equal((await admin.query('select count(*)::int n from explicit_route_finalization_private.reports')).rows[0].n, 0, 'default OFF has no report enrollment rows');


  await admin.query(restoreSql);
  equal((await admin.query("select count(*)::int n from pg_namespace where nspname='explicit_route_finalization_private'")).rows[0].n, 0, 'unused restore removes only the new module schema');
  equal(await originalCatalogue(), catalogueBefore, 'unused restore returns every pre-existing routine definition, OID, owner, ACL and configuration');
  equal(await protectedState(), protectedBefore, 'unused restore preserves every original canonical row');
  equal((await admin.query('select count(*)::int n from private.route_visit_reports')).rows[0].n, 0);
  await admin.query(installSql);
  equal((await admin.query('select count(*)::int n from explicit_route_finalization_private.states')).rows[0].n, 0, 'exact reviewed module reinstalls after unused restore');

  const first = await newVisit(200);
  equal(first.row.status, 'draft');
  equal(first.row.explicit_finalization_required, true);
  equal(first.row.explicit_finalization_completed, false);
  equal(first.row.workers.map(x => x.worker_id).sort(), [worker,memberWorker].sort(), 'actual frozen same-day route roster');
  const tuple = sourceTuple(first.row);
  await rejects(() => sign(a, first.row.id, 'responsible', '順序不正', signature(1)), /reporter|required|signature/i);
  for (const actor of [outsider, foreign]) {
    await asActor(b, actor);
    await rejects(() => read(b, first.args), /unavailable|required|permission|actor|member/i, 'non-roster/foreign actor cannot read');
    await rejects(() => sign(b, first.row.id, 'responsible', '権限なし', signature(1)), /unavailable|required|permission|actor|member/i);
  }
  await asActor(a, creator);
  let row = await sign(a, first.row.id, 'reporter', '変更前の合成報告者', signature(1));
  equal(row.status, 'reporter_signed');
  equal(row.signed_at, null);
  await asActor(b, member);
  const handoff = await read(b, first.args);
  equal(handoff.id, first.row.id, 'frozen roster member resumes creator report');
  equal(sourceTuple(handoff), tuple, 'handoff preserves all five source IDs');
  row = await sign(b, first.row.id, 'responsible', '変更前の合成責任者', signature(2));
  equal(row.status, 'reporter_signed', 'responsible signature is evidence only');
  equal(row.signed_at, null, 'not finalized at signature capture');
  equal(row.explicit_finalization_ready, true);
  equal(row.explicit_finalization_completed, false);
  equal(await protectedState(), protectedBefore, 'signature capture writes no canonical attendance/payroll source');

  const signedBeforeEdit = structuredClone(row);
  await rejects(() => finalize(b, {...row, signature_scope_fingerprint: 'stale-scope'}), /scope|changed|conflict|stale|PT409|updated/i);
  await rejects(() => finalize(b, {...row, report_updated_at: '2000-01-01T00:00:00Z'}), /scope|changed|conflict|stale|PT409|updated/i);
  row = await edit(b, row);
  equal(row.status, 'draft');
  equal(row.representative_signature_json, null);
  equal(row.supervisor_signature_json, null);
  equal(row.explicit_finalization_ready, false);
  const archived = JSON.stringify(await moduleState());
  ok(archived.includes('変更前の合成報告者') && archived.includes('変更前の合成責任者'), 'old actual signature evidence retained in immutable history');
  await rejects(() => finalize(b, signedBeforeEdit), /scope|changed|conflict|stale|signature|ready|required|updated/i);
  row = await saveDraft(b, first.args, '手直し後の合成作業', [{worker_id:worker,overtime_hours:2,allowance_label:'手直し後の合成手当',allowance_amount:200}]);
  equal(row.work_description, '手直し後の合成作業');
  equal(row.workers.find(x => x.worker_id === worker).overtime_hours, 2);
  equal(row.explicit_finalization_ready, false, 'changed allowance/hours requires real new signatures');
  equal(sourceTuple(row), tuple);
  await asActor(a, creator);
  await sign(a, row.id, 'reporter', '手直し後の合成報告者', signature(3));
  await asActor(b, member);
  row = await sign(b, row.id, 'responsible', '手直し後の合成責任者', signature(4));
  equal(row.explicit_finalization_ready, true);
  const finalRequest = structuredClone(row);

  // Actual row locks serialize two independent connections carrying the same CAS.
  await asActor(a, creator);
  await admin.query('begin');
  await admin.query('select id from private.route_visit_reports where id=$1 for update', [row.id]);
  const pa = settle(finalize(a, finalRequest)), pb = settle(finalize(b, finalRequest));
  await waitForLocks(observer, 2);
  await admin.query('commit');
  const [doneA,doneB] = await Promise.all([pa,pb]);
  equal(doneA.actor_id, creator);
  equal(doneB.actor_id, member);
  const withoutActor = ({actor_id: _actor, ...rest}) => rest;
  equal(withoutActor(doneA), withoutActor(doneB), 'same exact finalization retry is idempotent across real connections; response actor stays caller-bound');
  equal(doneA.status, 'completed');
  equal(doneA.explicit_finalization_completed, true);
  ok(doneA.signed_at, 'only explicit finalize sets completion time');
  equal(sourceTuple(doneA), tuple);
  const completedState = await moduleState();
  equal(await finalize(b, finalRequest), doneB, 'retry after caller discards committed response');
  equal(await moduleState(), completedState, 'lost-result retry appends no duplicate receipts/events');
  equal(await protectedState(), protectedBefore, 'visit finalization cannot fabricate canonical financial sources');

  // A separate report proves transactional rollback and a fresh post-commit observer.
  const second = await newVisit(210);
  row = await bothSign(second, 10);
  const pendingState = await moduleState();
  await asActor(a, creator);
  await a.query('begin');
  equal((await finalize(a, row)).status, 'completed');
  await a.query('rollback');
  equal((await read(b, second.args)).status, 'reporter_signed', 'rolled-back finalize is not visible');
  equal(await moduleState(), pendingState, 'rollback removes finalization evidence atomically');
  await a.query('begin');
  await finalize(a, row); // Deliberately discard the RPC reply at the caller boundary.
  await a.query('commit');
  const observed = await read(b, second.args);
  equal(observed.status, 'completed', 'fresh independent connection observes committed state');
  equal(await finalize(b, row), observed, 'original CAS can safely recover a discarded committed result');

  const third = await newVisit(220);
  row = await bothSign(third, 20);
  await admin.query('update auth.sessions set not_after=clock_timestamp()-interval \'1 second\' where id=$1', [sid(member)]);
  await rejects(() => finalize(b, row), /actor|session|access|unavailable|required/i, 'expired live SID cannot finalize');
  await admin.query('update auth.sessions set not_after=null where id=$1', [sid(member)]);
  await asActor(b, member, sid(creator));
  await rejects(() => finalize(b, row), /actor|session|access|unavailable|required/i, 'another actor SID cannot finalize');
  await asActor(b, member);
  await b.query('set role anon');
  await rejects(() => finalize(b, row), /permission denied/i, 'anonymous cannot call explicit finalize');
  await b.query('reset role');
  await b.query('set role service_role');
  await rejects(() => finalize(b, row), /permission denied/i, 'service role cannot impersonate an interactive signer');
  await asActor(b, member);
  equal((await finalize(b, row)).status, 'completed');
  const usedCatalogue = await originalCatalogue();
  const usedModule = await moduleState();
  await rejects(() => admin.query(restoreSql), /used|enabled|unused|restore|active|state|receipt|event/i, 'used module cannot be removed by unused restore');
  await admin.query('rollback');
  equal(await originalCatalogue(), usedCatalogue, 'failed used-restore retains active routine definitions and metadata');
  equal(await moduleState(), usedModule, 'failed used-restore retains all signatures, history and finalization evidence');
  equal(await protectedState(), protectedBefore);
  console.log(`PASS Native PostgreSQL 17 route explicit finalization: ${checks} assertions; capture-only signatures, exact CAS, real row-lock concurrency, discarded-result retry, rollback, frozen-roster handoff, audited edit/re-sign, live SID, unused restore/reinstall and used-restore rejection, canonical isolation`);
} finally {
  await Promise.allSettled(clients.map(async client => {
    try { await client.query('rollback'); } finally { await client.end(); }
  }));
}
