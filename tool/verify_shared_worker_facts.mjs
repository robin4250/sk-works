import assert from 'node:assert/strict';
import fs from 'node:fs';

const connection = process.env.SKO_SHARED_WORKER_FACTS_FIXTURE_URL;
const url = connection && new URL(connection);
if (!url || !['localhost', '127.0.0.1'].includes(url.hostname) ||
    url.pathname !== '/sko_shared_worker_facts_fixture' || url.username !== 'postgres') {
  throw new Error('isolated shared-worker fixture database required');
}
const {default: pg} = await import(process.argv[2]);
const client = new pg.Client({connectionString: connection});
await client.connect();
let checks = 0;
const eq = (a, b) => { assert.deepEqual(a, b); checks++; };
const q = async (sql, args = []) => (await client.query(sql, args)).rows[0]?.v;
async function rejects(sql, args, code) {
  await assert.rejects(client.query(sql, args), (e) => e.code === code); checks++;
}
const C = '00000000-0000-0000-0000-000000000001';
const U = '00000000-0000-0000-0000-000000000010';
const W = '00000000-0000-0000-0000-000000000002';
const R = '00000000-0000-0000-0000-000000000003';
const S = '00000000-0000-0000-0000-000000000004';
const V = '00000000-0000-0000-0000-000000000005';
const OTHER_V = '00000000-0000-0000-0000-000000000015';
const FOREIGN_V = '00000000-0000-0000-0000-000000000025';
const norm = 'select shared_worker_facts_private.normalize_worker_facts($1,$2,$3::jsonb) v';
const apply = 'select shared_worker_facts_private.materialize_confirmed_worker($1,$2,$3::jsonb)';
const params = (facts) => [R, W, JSON.stringify(facts)];
try {
  await client.query(`
    create role anon; create role authenticated; create role service_role;
    create schema auth; create schema private; create schema company_checkout_allowance_private;
    create schema payroll_scope_private; create schema checkout_shared_hours_private;
    create function auth.uid() returns uuid language sql stable as $$select '${U}'::uuid$$;
    create function private.account_access_allowed() returns boolean language sql stable as $$select true$$;
    create table public.company_members(company_id uuid,user_id uuid,primary key(company_id,user_id));
    create table public.workers(id uuid primary key,company_id uuid);
    create table public.daily_reports(id uuid primary key,company_id uuid,report_date date,site_id uuid,
      route_assignment_id uuid,status text,representative_signature_json jsonb);
    create table public.daily_report_workers(report_id uuid,worker_id uuid,overtime_hours numeric,
      early_hours numeric,night_hours numeric,work_category text,allowance_amount integer,allowance_label text,
      company_allowance_selections jsonb,company_allowance_legacy_labels text,vehicle_id uuid,
      route_assignment_id uuid,odometer_km numeric,previous_odometer_km numeric,audit_note text,
      primary key(report_id,worker_id));
    create table public.vehicles(id uuid primary key,company_id uuid,is_active boolean,odometer_km numeric,
      updated_by uuid,updated_at timestamptz);
    create table public.route_assignments(id uuid primary key,company_id uuid,is_active boolean);
    create table public.attendance_verifications(id uuid primary key,company_id uuid,worker_id uuid,
      work_date date,event_type text,site_id uuid,route_assignment_id uuid,vehicle_id uuid);
    create table checkout_shared_hours_private.materialization_permits(report_id uuid,worker_id uuid,
      transaction_id bigint,actor_id uuid,facts jsonb);
    create function payroll_scope_private.report_sources(rid uuid) returns jsonb language sql stable
      as $$select jsonb_build_object('scopes','[]'::jsonb,'report',rid)$$;
    create function payroll_scope_private.lock_scopes(scopes jsonb) returns void language plpgsql as $$begin end$$;
    -- Lookup alone is synthetic here. The actual registration/price chain is
    -- exercised by the separate signed-v2 producer proof, not fabricated here.
    create function company_checkout_allowance_private.registered_item(cid uuid,wid uuid,i jsonb)
    returns jsonb language plpgsql stable as $$begin
      if jsonb_typeof(i)<>'object' or (select count(*) from jsonb_object_keys(i))<>6
        or i->>'id'<>'00000000-0000-0000-0000-000000000099'
        or i->>'name_snapshot'<>'合成PC' or i->>'origin'<>'company_common'
        or i->>'unit'<>'day' or i->'generation'<>'null'::jsonb or i->'registration_version'<>'0'::jsonb
      then raise sqlstate '22023' using message='synthetic registered selection mismatch';end if;
      return i;
    end$$;
    insert into public.company_members values('${C}','${U}');
    insert into public.workers values('${W}','${C}');
    insert into public.daily_reports values('${R}','${C}','2026-10-22','${S}',null,'draft','{"strokes":[[1]]}');
    insert into public.daily_report_workers values('${R}','${W}',0,0,0,'day',500,'個別保存済手当',
      null,null,null,null,null,90,'preserve-existing-metadata');
    insert into public.vehicles values('${V}','${C}',true,100,null,now()),
      ('${OTHER_V}','${C}',true,200,null,now()),
      ('${FOREIGN_V}','00000000-0000-0000-0000-000000000020',true,10,null,now());
  `);
  const sources = JSON.parse(fs.readFileSync('tool/fixtures/shared_worker_facts_sources.json', 'utf8'));
  for (const source of sources.functions) {
    await client.query(source.definition);
    eq(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure', [source.signature]), source.source_md5);
    if (source.signature.includes('company_checkout_allowance_private')) {
      await client.query(`revoke all on function ${source.signature} from public,anon,authenticated,service_role`);
    }
  }
  await client.query(fs.readFileSync('docs/candidates/checkout_shared_worker_facts.sql.review-only', 'utf8'));
  await client.query(`
    create function checkout_shared_hours_private.permits_worker_materialization(rid uuid,wid uuid,oldj jsonb,newj jsonb)
    returns boolean language sql stable set search_path='' as $$
      select exists(select 1 from checkout_shared_hours_private.materialization_permits p where
      p.report_id=rid and p.worker_id=wid and p.transaction_id=txid_current() and p.actor_id=auth.uid()
      and shared_worker_facts_private.matches_materialization(oldj,newj,p.facts))$$;
    revoke all on function checkout_shared_hours_private.permits_worker_materialization(uuid,uuid,jsonb,jsonb)
      from public,anon,authenticated,service_role;
    create function private.synthetic_frozen_roster_guard() returns trigger language plpgsql as $$begin
      if to_jsonb(new) is distinct from to_jsonb(old) and not
       checkout_shared_hours_private.permits_worker_materialization(old.report_id,old.worker_id,to_jsonb(old),to_jsonb(new))
      then raise sqlstate '42501' using message='synthetic frozen roster requires context';end if;
      return new;end$$;
    create trigger synthetic_frozen_roster before update on public.daily_report_workers
      for each row execute function private.synthetic_frozen_roster_guard();
  `);
  const input = {schema: 1, overtime_hours: 0, early_hours: 0, night_hours: 0,
    work_category: 'day', allowance_amount: 500, allowance_label: '個別保存済手当',
    company_allowance_selections: {contract_version: 1, items: []}, vehicle_id: null,
    route_assignment_id: null, odometer_km: null};
  const canonical = await q(norm, params(input));
  eq(canonical.overtime_hours, 0);
  eq(canonical.allowance_amount, 500);
  eq(canonical.company_allowance_legacy_labels, '個別保存済手当');
  await client.query(`insert into workers values('00000000-0000-0000-0000-000000000012','${C}');
    insert into daily_reports values('00000000-0000-0000-0000-000000000013','${C}',
      '2026-10-23','${S}',null,'draft',null);
    insert into daily_report_workers(report_id,worker_id,overtime_hours,early_hours,night_hours,
      work_category,allowance_amount,allowance_label) values(
      '00000000-0000-0000-0000-000000000013','00000000-0000-0000-0000-000000000012',0,0,0,'day',0,'個別保存済手当')`);
  eq((await q(norm, ['00000000-0000-0000-0000-000000000013',
    '00000000-0000-0000-0000-000000000012', JSON.stringify({...input, allowance_amount: 0})])).allowance_amount, 0);
  await rejects(norm, ['00000000-0000-0000-0000-000000000013',
    '00000000-0000-0000-0000-000000000012', JSON.stringify({...input, allowance_amount: 100000})], '42501');
  eq(await q('select shared_worker_facts_private.propose_worker_facts($1,$2) v', [R, W]), null);
  for (const key of ['overtime_hours', 'early_hours', 'night_hours', 'work_category', 'allowance_amount', 'company_allowance_selections']) {
    const missing = {...input}; delete missing[key];
    await rejects(norm, params(missing), '22023');
  }
  for (const bad of [{overtime_hours: null}, {early_hours: -1}, {night_hours: 24.0001},
    {overtime_hours: 'NaN'}, {work_category: 'invented'}, {allowance_amount: 500.5},
    {company_allowance_selections: null}, {odometer_km: 5}, {vehicle_id: V},
    {vehicle_id: FOREIGN_V, odometer_km: 20}, {allowance_label: '架空手当'}]) {
    await rejects(norm, params({...input, ...bad}), '22023');
  }
  await rejects(norm, params({...input, allowance_amount: 100000}), '42501');
  await rejects(norm, params({...input, company_allowance_legacy_labels: 'injected'}), '22023');
  await rejects(norm, params({...input, rate_yen: 999999}), '22023');
  const selected = {...input, allowance_label: '個別保存済手当\n合成PC', company_allowance_selections: {
    contract_version: 1, items: [{origin: 'company_common', id: '00000000-0000-0000-0000-000000000099',
      generation: null, registration_version: 0, name_snapshot: '合成PC', unit: 'day'}]}};
  eq((await q(norm, params(selected))).company_allowance_selections.items.length, 1);
  const initial = await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2', [R, W]);
  const after = {...initial, ...canonical}; delete after.schema;
  eq(await q('select shared_worker_facts_private.matches_materialization($1,$2,$3) v',
    [JSON.stringify(initial), JSON.stringify(after), JSON.stringify(canonical)]), true);
  for (const changed of [{report_id: S}, {worker_id: U}, {audit_note: 'changed'},
    {previous_odometer_km: 0}, {allowance_amount: 100000}, {overtime_hours: 8}]) {
    eq(await q('select shared_worker_facts_private.matches_materialization($1,$2,$3) v',
      [JSON.stringify(initial), JSON.stringify({...after, ...changed}), JSON.stringify(canonical)]), false);
  }
  await rejects(apply, params(canonical), '42501');
  eq(await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1 and worker_id=$2', [R, W]), initial);
  const actual = await q(norm, params({...input, overtime_hours: 1.5, early_hours: 0.25, work_category: 'night'}));
  async function materialize(facts, actor = U) {
    await client.query('begin');
    try {
      await client.query('insert into checkout_shared_hours_private.materialization_permits values($1,$2,txid_current(),$3,$4)',
        [R, W, actor, JSON.stringify(facts)]);
      await client.query(apply, params(facts));
      await client.query('delete from checkout_shared_hours_private.materialization_permits');
      await client.query('commit');
    } catch (error) { await client.query('rollback'); throw error; }
  }
  await assert.rejects(materialize(actual, W), (e) => e.code === '42501'); checks++;
  await materialize(actual);
  eq(await q('select overtime_hours::float8 v from daily_report_workers where report_id=$1', [R]), 1.5);
  eq(await q('select allowance_amount v from daily_report_workers where report_id=$1', [R]), 500);
  eq(await q('select representative_signature_json v from daily_reports where id=$1', [R]), {strokes: [[1]]});
  eq(await q('select audit_note v from daily_report_workers where report_id=$1', [R]), 'preserve-existing-metadata');
  await client.query(`insert into attendance_verifications values('00000000-0000-0000-0000-000000000050',
    '${C}','${W}','2026-10-22','clock_in','${S}',null,'${V}')`);
  await rejects(norm, params({...input, vehicle_id: OTHER_V, odometer_km: 210}), '22023');
  const vehicle = await q(norm, params({...input, vehicle_id: V, odometer_km: 110}));
  await materialize(vehicle);
  eq(await q('select odometer_km::float8 v from vehicles where id=$1', [V]), 110);
  eq(await q('select odometer_km::float8 v from daily_report_workers where report_id=$1', [R]), 110);
  const oldRow = await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1', [R]);
  const regressive = await q(norm, params({...input, vehicle_id: V, odometer_km: 105}));
  await assert.rejects(materialize(regressive), /現在の走行距離より小さい/); checks++;
  eq(await q('select to_jsonb(w) v from daily_report_workers w where report_id=$1', [R]), oldRow);
  eq(await q('select odometer_km::float8 v from vehicles where id=$1', [V]), 110);
  await client.query(`create table private.vehicle_usage_rollout(company_id uuid,enabled boolean);
    insert into private.vehicle_usage_rollout values('${C}',true)`);
  await rejects(norm, params({...input, vehicle_id: V, odometer_km: 111}), '55000');
  eq((await q(norm, params({...input, vehicle_id: V, odometer_km: 110}))).odometer_km, 110);
  for (const role of ['anon', 'authenticated', 'service_role']) {
    eq(await q("select has_schema_privilege($1,'shared_worker_facts_private','USAGE') v", [role]), false);
    eq(await q("select has_function_privilege($1,'shared_worker_facts_private.materialize_confirmed_worker(uuid,uuid,jsonb)','EXECUTE') v", [role]), false);
  }
  console.log(JSON.stringify({pass: true, checks, exact_validator_and_vehicle_sources: true,
    registered_lookup_and_context_are_synthetic: true, production_changed: false, real_gotrue: false}));
} finally { await client.end(); }
