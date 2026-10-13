// Disposable real SQL verification; never connects to production.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const {PGlite} = await import(process.argv[2]);
const db = new PGlite();
const read = name => fs.readFile(new URL('../' + name, import.meta.url), 'utf8');
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
await db.exec(`
 create role authenticated; create role anon;
 create schema auth; create schema private;
 create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('test.uid',true),'')::uuid $$;
 create function private.account_access_allowed() returns boolean language sql stable as $$
  select coalesce(nullif(current_setting('test.allowed',true),'')::boolean,true) $$;
 create table public.workers(id uuid,company_id uuid);
 create table public.company_members(company_id uuid,user_id uuid);
 create table public.customers(id uuid,company_id uuid,name text);
 create table public.sites(id uuid,company_id uuid,customer_id uuid);
 create table public.attendance_verifications(id uuid,company_id uuid,event_type text,source_clock_in_id uuid);
 create table private.route_visit_reports(id uuid,company_id uuid,created_by uuid,
  report_date date,status text,workers jsonb,site_id uuid,site_name text,source_clock_in_id uuid,created_at timestamptz);
 create table private.route_billing_quantity_requests(id uuid,company_id uuid,worker_id uuid,work_date date,
  customer_id uuid,version int,status text,requested_quantity numeric,quantity numeric);
 create table private.route_billing_quantity_evidence(request_id uuid,site_id uuid,customer_id uuid,report_id uuid);
 grant usage on schema public,private,auth to authenticated,anon;
`);
const original = await read('supabase/migrations/20261012053842_route_customer_billing_connection.sql');
function definition(marker) {
 const start = original.indexOf(marker);
 assert.ok(start >= 0, marker);
 const next = original.indexOf('create function ', start + marker.length);
 return original.slice(start, next < 0 ? original.indexOf('commit;',start) : next);
}
await db.exec(definition('create function public.route_customer_day_quantity_candidates('));
await db.exec(definition('create function private.route_billing_invoice_blocked('));
const [company,otherCompany,actor,otherActor,worker,otherWorker,customer,site,unresolvedSite] =
 Array.from({length:9},(_,i)=>id(i+1));
await db.exec(`
 insert into workers values('${worker}','${company}'),('${otherWorker}','${otherCompany}');
 insert into company_members values('${company}','${actor}'),('${company}','${otherActor}');
 insert into customers values('${customer}','${company}','会社');
 insert into sites values('${site}','${company}','${customer}'),('${unresolvedSite}','${company}',null);
 insert into attendance_verifications values
  ('${id(20)}','${company}','clock_in',null),('${id(21)}','${company}','clock_out','${id(20)}'),
  ('${id(30)}','${company}','clock_in',null),
  ('${id(40)}','${company}','clock_in',null),('${id(41)}','${company}','clock_out','${id(40)}'),
  ('${id(61)}','${company}','clock_out','${id(60)}');
`);
for (const [n,source,target,creator,status,cid,wid] of [
 [100,20,site,actor,'completed',company,worker],
 [101,30,site,actor,'completed',company,worker],
 [102,50,site,actor,'completed',company,worker],
 [103,40,unresolvedSite,actor,'completed',company,worker],
 [104,60,site,actor,'completed',company,worker],
 [105,20,site,otherActor,'completed',company,worker],
 [106,20,site,actor,'draft',company,worker],
 [107,20,site,actor,'completed',otherCompany,otherWorker],
]) {
 await db.query(`insert into private.route_visit_reports values($1,$2,$3,'2026-10-12',$4,$5,$6,'現場',$7,now())`,
  [id(n),cid,creator,status,JSON.stringify([{worker_id:wid}]),target,id(source)]);
}
const existingDefinitions = async () => (await db.query(`select proname,md5(prosrc) body,prosecdef,provolatile,proconfig,proacl::text acl
 from pg_proc where oid in (
 'public.route_customer_day_quantity_candidates(uuid,date)'::regprocedure,
 'private.route_billing_invoice_blocked(uuid,uuid,date,date)'::regprocedure
 ) order by proname`)).rows;
const beforeDefinitions = await existingDefinitions();
const tables = ['workers','company_members','customers','sites','attendance_verifications',
 'private.route_visit_reports','private.route_billing_quantity_requests','private.route_billing_quantity_evidence'];
const snapshots = async () => Promise.all(tables.map(async table =>
 (await db.query(`select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]') rows from ${table} t`)).rows[0].rows));
const beforeRows = await snapshots();
const migration = await read('supabase/migrations/20261013004228_route_quantity_evidence_diagnostics.sql');
await db.exec(migration);
assert.deepEqual(await existingDefinitions(),beforeDefinitions,'candidate and finalization guards remain exact');
const diag = () => db.query(`select public.route_customer_day_quantity_diagnostics('${worker}','2026-10-12') value`).then(x=>x.rows[0].value);
await db.exec(`set test.uid='${actor}'; set role authenticated`);
assert.deepEqual(await diag(), {
 completed_report_count:5, eligible_report_count:2, unresolved_customer_count:1,
 missing_source_count:1, waiting_checkout_count:1,
},'own completed evidence is partitioned without inferring archived checkout');
const candidates = (await db.query(`select public.route_customer_day_quantity_candidates('${worker}','2026-10-12') value`)).rows[0].value;
assert.equal(candidates.customers.length,1);
assert.equal(candidates.customers[0].report_ids.length,2,'live checkout remains eligible even without a live clock-in row');
assert.equal(candidates.unresolved_count,1);
await assert.rejects(db.query(`select public.route_customer_day_quantity_diagnostics('${otherWorker}','2026-10-12')`),/worker unavailable/);
await db.exec(`set test.uid='${otherActor}'`);
assert.equal((await diag()).completed_report_count,1,'other actor cannot see the original actor reports');
await db.exec(`set test.uid='${id(999)}'`);
await assert.rejects(diag(),/worker unavailable/);
await db.exec(`set test.uid='${actor}'; set test.allowed='false'`);
await assert.rejects(diag(),/account unavailable/);
await db.exec(`set test.allowed='true'; set test.uid=''`);
await assert.rejects(diag(),/account unavailable/);
await db.exec('reset role; set role anon');
await assert.rejects(diag(),/permission denied/);
await db.exec('reset role');
assert.deepEqual(await snapshots(),beforeRows,'every record remains unchanged');
const blocked = (await db.query(`select private.route_billing_invoice_blocked('${company}','${customer}','2026-10-01','2026-10-31') value`)).rows[0].value;
assert.equal(blocked,true,'unrequested missing-source evidence still blocks finalization');
const properties = (await db.query(`select n.nspname,p.prosecdef,p.provolatile,p.proconfig
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where p.proname='route_customer_day_quantity_diagnostics' order by n.nspname`)).rows;
assert.equal(properties.length,2);assert.equal(properties[0].prosecdef,true);assert.equal(properties[1].prosecdef,false);
assert.ok(properties.every(p=>p.provolatile==='s'&&p.proconfig.includes('search_path=""')));
console.log('PASS read-only evidence reasons, unchanged candidates/guard/data, actor/company/account/anonymous scope');
await db.close();
