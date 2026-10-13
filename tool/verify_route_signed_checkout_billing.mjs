import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const runtime=await import(pathToFileURL(process.argv[2]).href);
const migration=await fs.readFile(new URL('../supabase/migrations/20261013181708_route_signed_checkout_customer_billing.sql',import.meta.url),'utf8');
function section(name,next) {
 const start=migration.indexOf('create or replace function private.'+name+'(');
 const end=migration.indexOf('create or replace function private.'+next+'(',start+1);
 assert.ok(start>=0 && end>start);return migration.slice(start,end);
}
const realDatabase=process.env.SKO_SIGNED_BILLING_DATABASE_URL;
const PgClient=runtime.Client ?? runtime.default?.Client;
if (realDatabase) {
  const target=new URL(realDatabase);
  assert.ok(['127.0.0.1','localhost'].includes(target.hostname) && target.pathname==='/sko_signed_checkout_fixture',
    'Use only the disposable local signed-checkout fixture database');
}
let pg;
if (realDatabase) { pg=new PgClient({connectionString:realDatabase});await pg.connect(); }
const db=realDatabase ? {
  exec:sql=>pg.query(sql),query:(sql,args)=>pg.query(sql,args),close:()=>pg.end(),
} : new runtime.PGlite();
await db.exec(`create schema private;
create table daily_reports(id uuid,company_id uuid,site_id uuid,route_assignment_id uuid,report_date date,status text,signed_at timestamptz,signature_json jsonb);
create table attendance_entries(id uuid,company_id uuid,worker_id uuid,site_id uuid,route_assignment_id uuid,source_report_id uuid,work_date date,base_man_days numeric,work_category text,overtime_hours numeric,early_hours numeric,allowance_names text[]);
create table daily_report_workers(report_id uuid,worker_id uuid);
create table attendance_verifications(id uuid,company_id uuid,worker_id uuid,site_id uuid,route_assignment_id uuid,work_date date,event_type text,source_clock_in_id uuid,daily_report_id uuid,confirmed_at timestamptz);
create table private.route_journey_visit_events(capture_id uuid,source_clock_in_id uuid,route_stop_id uuid,kind text,start_capture_id uuid);
create table private.route_journey_captures(id uuid,company_id uuid,source_clock_in_id uuid,worker_id uuid,route_assignment_id uuid,route_stop_id uuid,work_date date,recorded_at timestamptz);
create table route_stops(id uuid,route_assignment_id uuid,site_id uuid);
create table sites(id uuid,company_id uuid,customer_id uuid,name text,formal_name text);
create role anon;create role authenticated;`);
const id=n=>`00000000-0000-0000-0000-${n.toString().padStart(12,'0')}`;
const company=id(1), worker=id(2), report=id(3), route=id(4), start=id(5), out=id(6), entry=id(7), a=id(8),b=id(9);
await db.query(`insert into daily_reports values($1,$2,null,$3,'2026-10-12','signed','2026-10-12T09:00Z','[[1,1],[2,2]]');
`,[report,company,route]);
await db.query(`insert into attendance_entries values($1,$2,$3,null,$4,$5,'2026-10-12',1,'day',0,0,'{}')`,[entry,company,worker,route,report]);
await db.query(`insert into daily_report_workers values($1,$2)`,[report,worker]);
await db.query(`insert into attendance_verifications values($1,$2,$3,null,$4,'2026-10-12','clock_in',null,$5,'2026-10-12T00:00Z'),($6,$2,$3,null,$4,'2026-10-12','clock_out',$1,$5,'2026-10-12T09:00Z')`,[start,company,worker,route,report,out]);
for(let i=0;i<3;i++) {
  const site=id(20+i),stop=id(30+i),c=id(40+i),end=id(50+i);
  await db.query(`insert into sites values($1,$2,$3,$4,null)`,[site,company,i===2?b:a,['第一現場','第二現場','第三現場'][i]]);
  await db.query(`insert into route_stops values($1,$2,$3)`,[stop,route,site]);
  await db.query(`insert into private.route_journey_captures values($1,$2,$3,$4,$5,$6,'2026-10-12',$7),($8,$2,$3,$4,$5,$6,'2026-10-12',$9)`,[c,company,start,worker,route,stop,`2026-10-12T0${1+i*2}:00Z`,end,`2026-10-12T0${2+i*2}:00Z`]);
  await db.query(`insert into private.route_journey_visit_events values($1,$2,$3,'start',$1),($4,$2,$3,'end',$1)`,[c,start,stop,end]);
}
await db.exec(section('route_signed_checkout_sources','route_signed_site_rates'));
const rows=async()=> (await db.query(`select * from private.route_signed_checkout_sources($1,'2026-10-12','2026-10-12') order by customer_id`,[company])).rows;
let result=await rows();
assert.equal(result.length,2);assert.ok(result.every(x=>x.quantity==='1'&&x.source_ready));
assert.deepEqual(result[0].site_names,['第一現場','第二現場']);assert.equal(Number(result[0].visit_count),2);
await db.query(`update daily_reports set status='draft'`);assert.equal((await rows()).length,0);
await db.exec(`update daily_reports set status='signed'`);
await db.query(`delete from attendance_verifications where id=$1`,[out]);assert.equal((await rows()).length,0);
await db.query(`insert into attendance_verifications values($1,$2,$3,null,$4,'2026-10-12','clock_out',$5,$6,'2026-10-12T09:00Z')`,[out,company,worker,route,start,report]);
await db.query(`delete from private.route_journey_visit_events where capture_id=$1`,[id(50)]);
result=await rows();assert.equal(result[0].source_ready,false);assert.equal(result[1].source_ready,true);
console.log('signed checkout, actual customer partitions, one-per-customer quantity and unsigned/unfinished guards passed');


await db.exec(`create table companies(id uuid,tax_rate numeric);
create table customers(id uuid,company_id uuid,notes text);
create table site_financial_settings(company_id uuid,site_id uuid,billing_unit_price_yen numeric,billing_monthly_rate_yen numeric,billing_square_meter_unit_price_yen numeric,billing_square_meter_quantity numeric,billing_contract_amount_yen numeric,billing_overtime_hour_rate_yen numeric,billing_early_hour_rate_yen numeric,billing_rate_formula jsonb,billing_rate_overrides jsonb,welfare_rate numeric,billing_allowance_1_name text,billing_allowance_1_amount_yen numeric,billing_allowance_2_name text,billing_allowance_2_amount_yen numeric,billing_allowance_3_name text,billing_allowance_3_amount_yen numeric);
create table site_calculation_source_preferences(company_id uuid,site_id uuid,trade_company_id uuid,output_type text,source text);
create table trade_companies(id uuid,company_id uuid);
create table trade_company_contracts(company_id uuid,trade_company_id uuid,contract_method text,daily_rate_yen numeric);
create table private.route_billing_quantity_requests(company_id uuid,worker_id uuid,work_date date,customer_id uuid,status text);
`);
await db.exec(await fs.readFile(new URL('./fixtures/route_signed_checkout/formula_foundation.sql',import.meta.url),'utf8'));
await db.exec(`create function private.route_billing_site_daily_rate(cid uuid,sid uuid) returns table(unit_price_yen integer,man_day_method boolean) language sql as $$select billing_unit_price_yen::integer,coalesce(billing_unit_price_yen>0,false) from public.site_financial_settings where company_id=cid and site_id=sid$$`);
await db.query(`insert into companies values($1,10)`,[company]);
for(let i=0;i<3;i++) await db.query(`insert into site_financial_settings(company_id,site_id,billing_unit_price_yen,welfare_rate) values($1,$2,32800,15)`,[company,id(20+i)]);
await db.exec(section('route_signed_site_rates','route_signed_checkout_components'));
await db.exec(section('route_signed_checkout_components','route_billing_invoice_blocked'));
// Restore the genuine ended visit, then evaluate actual SQL financial results.
await db.query(`insert into private.route_journey_visit_events values($1,$2,$3,'end',$4)`,[id(50),start,id(30),id(40)]);
const components=async cust=>(await db.query(`select private.route_signed_checkout_components($1,$2,'2026-10-12','2026-10-12') value`,[company,cust])).rows[0].value;
let c=await components(a);assert.equal(c.blocked,false);assert.equal(c.subtotal,37720);assert.equal(c.tax,3772);assert.equal(c.sites.length,1);assert.equal(c.sites[0].lines[0].quantity,1);assert.equal(c.sites[0].site_name,'第一現場〜第二現場');assert.equal(c.sites[0].lines[0].work_content,'複数現場');
let cb=await components(b);assert.equal(cb.sites.length,1);assert.equal(cb.sites[0].lines[0].quantity,1);
// Same customer across every site remains one man-day, never visit-count billing.
await db.query(`update sites set customer_id=$1`,[a]);c=await components(a);assert.equal(c.sites.length,1);assert.equal(c.sites[0].lines[0].quantity,1);assert.equal(c.subtotal,37720);assert.equal(c.sites[0].site_name,'第一現場〜第二現場〜第三現場');
// A missing or conflicting rate cannot silently produce a final zero invoice.
await db.query(`update site_financial_settings set billing_unit_price_yen=0 where site_id=$1`,[id(22)]);c=await components(a);assert.equal(c.blocked,true);assert.equal(c.sites.length,0);
await db.query(`update site_financial_settings set billing_unit_price_yen=32000 where site_id=$1`,[id(22)]);assert.equal((await components(a)).blocked,true);
await db.query(`update site_financial_settings set billing_unit_price_yen=32800 where site_id=$1`,[id(22)]);
await db.query(`update daily_reports set status='draft'`);c=await components(a);assert.equal(c.has_sources,false);assert.equal(c.sites.length,0);
await db.query(`update daily_reports set status='signed'`);
await db.query(`insert into private.route_billing_quantity_requests values($1,$2,'2026-10-12',$3,'approved')`,[company,worker,a]);c=await components(a);assert.equal(c.sites.length,0);assert.equal((await db.query('select status from private.route_billing_quantity_requests')).rows[0].status,'approved');
console.log('actual signed customer billing SQL: one per customer, ordered real site names, registered formulas/welfare/tax, missing/conflicting rate guards and untouched approval history passed');


await db.exec(`create schema auth;create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create function private.account_access_allowed() returns boolean language sql as $$select true$$;
create table company_members(company_id uuid,user_id uuid,role text);
create function private.has_company_feature(cid uuid,feature text) returns boolean language sql as $$select coalesce(current_setting('test.manage',true),'true')='true' and feature='can_manage_invoices' and exists(select 1 from public.company_members where company_id=cid and user_id=auth.uid() and role='owner')$$;
create table invoices(id uuid primary key default gen_random_uuid(),company_id uuid,customer_id uuid,billing_period_start date,billing_period_end date,status text,finalized_at timestamptz,automatic_calculation boolean,calculation_blocked boolean,subtotal integer,tax integer,welfare_amount integer,grand_total integer,snapshot jsonb,updated_at timestamptz);
alter table customers add column name text;
alter table sites add column created_at timestamptz default now();
alter table trade_company_contracts add column monthly_rate_yen numeric,add column square_meter_unit_price_yen numeric,add column square_meter_quantity numeric,add column contract_amount_yen numeric;
alter table private.route_billing_quantity_requests add column id uuid default gen_random_uuid(),add column quantity numeric default 1,add column unit_price_yen integer default 32800,add column representative_site_id uuid,add column version integer default 1,add column reviewed_by uuid;
create table private.route_billing_quantity_evidence(request_id uuid,site_id uuid,customer_id uuid,report_id uuid);
create table private.route_billing_quantity_audit(id uuid,request_id uuid,actor_id uuid,action text);
create table private.route_visit_reports(id uuid,company_id uuid,site_id uuid,report_date date,status text,workers jsonb);
create function private.ensure_unassigned_invoice_customer(cid uuid) returns uuid language sql as $$select null::uuid$$;
create function private.document_company_seal_snapshot(saved jsonb,cid uuid,new_document boolean) returns jsonb language sql as $$select '{}'::jsonb$$;
create function private.expense_cost_components(kind text,cid uuid,customer uuid,first_day date,last_day date,invoice_id uuid) returns jsonb language sql as $$select '{"amount_yen":0,"has_choices":false,"claims":[]}'::jsonb$$;
`);
await db.query(`select set_config('test.uid',$1,false)`,[worker]);
await db.query(`insert into company_members values($1,$2,'owner')`,[company,worker]);
await db.query(`insert into customers(id,company_id,name) values($1,$2,'取引会社A')`,[a,company]);
await db.exec(`update private.route_billing_quantity_requests set status='pending'`);
await db.exec(await fs.readFile(new URL('./fixtures/route_signed_checkout/legacy_route_helpers.sql',import.meta.url),'utf8'));
await db.exec(await fs.readFile(new URL('./fixtures/route_signed_checkout/automatic_invoice_generator.sql',import.meta.url),'utf8'));
await db.query(`select private.refresh_automatic_invoice($1,$2,'2026-10-12')`,[company,a]);
let saved=(await db.query('select * from invoices')).rows;
assert.equal(saved.length,1);assert.equal(saved[0].grand_total,0);assert.equal(saved[0].calculation_blocked,true);
await db.exec(migration);
await db.exec(`create function public.pending_route_billing_quantity_rows() returns jsonb language sql as $$select private.pending_route_billing_quantity_rows()$$`);
await db.query(`select public.refresh_signed_checkout_invoices($1)`,[company]);
saved=(await db.query('select * from invoices')).rows;
assert.equal(saved.length,1);assert.equal(saved[0].grand_total,41492);assert.equal(saved[0].calculation_blocked,false);
assert.equal(saved[0].snapshot.route_quantity_pending,false);assert.equal(saved[0].snapshot.route_source_pending,false);
assert.equal(saved[0].snapshot.sites[0].lines[0].quantity,1);
assert.equal(saved[0].snapshot.sites[0].site_name,'第一現場〜第二現場〜第三現場');
assert.equal((await db.query('select status,reviewed_by from private.route_billing_quantity_requests')).rows[0].status,'pending');
assert.equal((await db.query('select reviewed_by from private.route_billing_quantity_requests')).rows[0].reviewed_by,null);
assert.equal((await db.query('select count(*)::integer n from private.route_billing_quantity_audit')).rows[0].n,0);
assert.equal((await db.query('select public.pending_route_billing_quantity_rows()')).rows.length,1);
await db.exec(migration);await db.query(`select public.refresh_signed_checkout_invoices($1)`,[company]);
assert.equal((await db.query('select count(*)::integer n from invoices')).rows[0].n,1);
assert.equal((await db.query('select base_man_days from attendance_entries')).rows[0].base_man_days,'1');

// A denied viewer and a foreign company cannot refresh financial drafts.
await db.exec("select set_config('test.manage','false',false)");
await assert.rejects(db.query(`select public.refresh_signed_checkout_invoices($1)`,[company]));
await db.exec("select set_config('test.manage','true',false)");
await assert.rejects(db.query(`select public.refresh_signed_checkout_invoices($1)`,[id(900)]));
await db.exec("select set_config('test.uid','',false)");
await assert.rejects(db.query(`select public.route_checkout_billing_contract()`));
await db.query(`select set_config('test.uid',$1,false)`,[worker]);
const capability=(await db.query('select public.route_checkout_billing_contract() contract')).rows[0].contract;
assert.equal(capability.separate_quantity_approval_required,false);
// Reverting a signature blocks the draft instead of publishing a zero invoice.
await db.query(`update daily_reports set status='draft',signed_at=null where id=$1`,[report]);
saved=(await db.query('select * from invoices')).rows;
assert.equal(saved[0].calculation_blocked,true);
assert.equal(saved[0].snapshot.route_source_pending,true);
const blockedUpdatedAt=saved[0].updated_at;
await db.query(`select public.refresh_signed_checkout_invoices($1)`,[company]);
assert.deepEqual((await db.query('select updated_at from invoices')).rows[0].updated_at,blockedUpdatedAt);

await db.query(`update daily_reports set status='signed',signed_at='2026-10-12T09:00Z' where id=$1`,[report]);
assert.equal((await db.query('select grand_total from invoices')).rows[0].grand_total,41492);
if (realDatabase) {
  // Real Postgres connections serialize refreshing the same customer/month.
  const second=new PgClient({connectionString:realDatabase});await second.connect();
  await second.query(`select set_config('test.uid',$1,false)`,[worker]);
  await Promise.all([
    pg.query(`select public.refresh_signed_checkout_invoices($1)`,[company]),
    second.query(`select public.refresh_signed_checkout_invoices($1)`,[company]),
  ]);
  assert.equal((await pg.query('select count(*)::integer n from invoices')).rows[0].n,1);
  assert.equal((await pg.query('select grand_total from invoices')).rows[0].grand_total,41492);
  // Finalization holds the existing row lock. A concurrent refresh must recheck
  // the finalized status after waiting, and keep that snapshot unchanged.
  await pg.query('begin');
  await pg.query('select id from invoices for update');
  const concurrent=second.query(`select public.refresh_signed_checkout_invoices($1)`,[company]);
  let waited=false;
  for (let attempt=0;attempt<100;attempt++) {
    const activity=await pg.query('select wait_event_type from pg_stat_activity where pid=$1',[second.processID]);
    if (activity.rows[0]?.wait_event_type==='Lock') {waited=true;break;}
    await new Promise(resolve=>setTimeout(resolve,10));
  }
  assert.equal(waited,true,'Concurrent refresh must wait for the finalization row lock');
  await pg.query("update invoices set status='finalized',finalized_at=now()");
  const finalSnapshot=(await pg.query('select snapshot from invoices')).rows[0].snapshot;
  await pg.query('commit');await concurrent;
  assert.deepEqual((await pg.query('select snapshot from invoices')).rows[0].snapshot,finalSnapshot);
  await second.end();
}
// A finalized snapshot remains unchanged on refresh after a registered-rate edit.
await db.exec("update invoices set status='finalized',finalized_at=now()");
const frozen=(await db.query('select snapshot from invoices')).rows[0].snapshot;
await db.exec('update site_financial_settings set billing_unit_price_yen=40000');
await db.query(`select public.refresh_signed_checkout_invoices($1)`,[company]);
assert.deepEqual((await db.query('select snapshot from invoices')).rows[0].snapshot,frozen);
assert.equal((await db.query('select grand_total from invoices')).rows[0].grand_total,41492);
console.log('actual existing invoice generator integration, guarded migration replay, authenticated scoped refresh and untouched source/request/review/audit passed');
await db.close();
