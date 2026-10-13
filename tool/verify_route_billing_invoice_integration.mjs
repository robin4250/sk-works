// Actual current invoice generator plus staged quantity integration, isolated PostgreSQL only.
import fs from 'node:fs/promises';import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();
const read=async name=>fs.readFile(new URL('../'+name,import.meta.url),'utf8');
await db.exec(`create schema private;create schema auth;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create function private.ensure_unassigned_invoice_customer(uuid) returns uuid language sql as $$select null::uuid$$;
create table companies(id uuid primary key,tax_rate numeric);
create table customers(id uuid primary key,company_id uuid,name text,notes text);
create table sites(id uuid primary key,company_id uuid,customer_id uuid,name text,formal_name text,created_at timestamptz default now());
create table invoices(id uuid default gen_random_uuid(),company_id uuid,customer_id uuid,billing_period_start date,billing_period_end date,status text,finalized_at timestamptz,automatic_calculation boolean,calculation_blocked boolean,subtotal integer,tax integer,welfare_amount integer,grand_total integer,snapshot jsonb,updated_at timestamptz);
create table site_financial_settings(company_id uuid,site_id uuid,billing_unit_price_yen numeric default 0,billing_monthly_rate_yen numeric default 0,billing_square_meter_unit_price_yen numeric default 0,billing_square_meter_quantity numeric default 0,billing_contract_amount_yen numeric default 0,billing_overtime_hour_rate_yen numeric default 0,billing_early_hour_rate_yen numeric default 0,billing_rate_formula jsonb default '{}',billing_rate_overrides jsonb default '{}',welfare_rate numeric default 0,billing_allowance_1_name text,billing_allowance_1_amount_yen numeric default 0,billing_allowance_2_name text,billing_allowance_2_amount_yen numeric default 0,billing_allowance_3_name text,billing_allowance_3_amount_yen numeric default 0);
create table attendance_entries(company_id uuid,site_id uuid,work_date date,work_category text,base_man_days numeric,overtime_hours numeric,early_hours numeric,allowance_names text[]);
create table site_calculation_source_preferences(company_id uuid,site_id uuid,trade_company_id uuid,output_type text,source text);
create table trade_companies(id uuid,company_id uuid);
create table trade_company_contracts(company_id uuid,trade_company_id uuid,contract_method text,daily_rate_yen numeric,monthly_rate_yen numeric,square_meter_unit_price_yen numeric,square_meter_quantity numeric,contract_amount_yen numeric);

create role anon;create role authenticated;grant usage on schema public,private,auth to authenticated,anon;
create function private.account_access_allowed() returns boolean language sql as $$select true$$;
create table company_members(company_id uuid,user_id uuid,role text);
create function private.has_company_feature(p_company uuid,p_feature text) returns boolean language sql as $$
 select p_feature='can_manage_invoices' and coalesce(current_setting('test.invoice_manage',true),'true')='true'
 and exists(select 1 from public.company_members m where m.company_id=p_company and m.user_id=auth.uid() and m.role in ('owner','admin'))$$;

create table workers(id uuid,company_id uuid,name text);
create table private.route_visit_reports(id uuid,company_id uuid,created_by uuid,report_date date,status text,workers jsonb,roster_workers jsonb,site_id uuid,site_name text,source_clock_in_id uuid,start_capture_id uuid,end_capture_id uuid);
alter table invoices add column approval_finalized_at timestamptz;
`);

const original=await read('supabase/migrations/20261006173142_common_rate_formula_invoice_hourly.sql');
await db.exec(original.slice(0,original.indexOf('CREATE OR REPLACE FUNCTION private.refresh_automatic_invoice')));
await db.exec(await read('supabase/migrations/20261008035509_invoice_registered_method_amounts_and_formula_labels.sql'));
await db.exec(await read('supabase/tests/route_customer_day_billing_allocations_schema.sql'));
await db.exec(await read('supabase/tests/route_billing_invoice_integration.sql'));
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [company,worker,user,manager,custA,custB,siteA,siteB,reportA,reportB]=Array.from({length:10},(_,i)=>id(i+1));
const json=x=>`'${JSON.stringify(x)}'::jsonb`;
await db.exec(`insert into companies values('${company}',10);
 insert into company_members values('${company}','${user}','employee'),('${company}','${manager}','admin');
 insert into workers values('${worker}','${company}','本人');
 insert into customers values('${custA}','${company}','会社A',''),('${custB}','${company}','会社B','');
 insert into sites(id,company_id,customer_id,name) values('${siteA}','${company}','${custA}','現場A'),('${siteB}','${company}','${custB}','現場B');
 insert into site_financial_settings(company_id,site_id,billing_unit_price_yen,welfare_rate) values('${company}','${siteA}',20000,3),('${company}','${siteB}',25000,3);`);
for(const [report,site,name,seed] of [[reportA,siteA,'現場A',20],[reportB,siteB,'現場B',30]]){
 await db.exec(`insert into private.route_visit_reports values('${report}','${company}','${user}','2026-10-12','completed',${json([{worker_id:worker,worker_name:'本人'}])},${json([{worker_id:worker,worker_name:'本人'}])},'${site}','${name}','${id(seed)}','${id(seed+1)}','${id(seed+2)}')`);
}
const rpc=async sql=>(await db.query(`select ${sql} value`)).rows[0].value;
const submit=qty=>rpc(`public.submit_route_customer_day_allocations('${worker}',array['${reportA}'::uuid,'${reportB}'::uuid],${json([{customer_id:custA,quantity:qty},{customer_id:custB,quantity:1}])})`);
await db.exec(`set test.uid='${user}';set role authenticated`);
const rows=await submit(1);const a=rows.find(r=>r.customer_id===custA),b=rows.find(r=>r.customer_id===custB);
await db.exec('reset role');
assert.equal((await db.query('select count(*)::int n from invoices where calculation_blocked')).rows[0].n,2);
await assert.rejects(db.exec(`update invoices set status='finalized' where customer_id='${custA}'`),/申請・承認/);
await assert.rejects(db.exec(`update invoices set approval_finalized_at=now() where customer_id='${custB}'`),/申請・承認/);
await db.exec(`set test.uid='${manager}';set role authenticated`);
await rpc(`public.decide_route_billing_quantity('${a.id}',1,'approve','',1,'${siteA}',20000)`);
await rpc(`public.decide_route_billing_quantity('${b.id}',0.5,'approve','',1,'${siteB}',25000)`);
await db.exec('reset role');
const invoices=(await db.query('select * from invoices order by customer_id')).rows;
const invoiceA=invoices.find(r=>r.customer_id===custA),invoiceB=invoices.find(r=>r.customer_id===custB);
assert.equal(invoiceA.subtotal,20600);assert.equal(invoiceA.tax,2060);assert.equal(invoiceA.grand_total,22660);
assert.equal(invoiceB.subtotal,12875);assert.equal(invoiceB.tax,1288);assert.equal(invoiceB.grand_total,14163);
assert.equal(invoiceA.calculation_blocked,false);assert.equal(invoiceB.calculation_blocked,false);
assert.equal(invoiceA.snapshot.sites[0].lines[0].quantity,1);assert.equal(invoiceB.snapshot.sites[0].lines[0].quantity,0.5);
assert.equal((await db.query('select count(*)::int n from attendance_entries')).rows[0].n,0);
// Exact request retries retain the approved reviewer quantity and invoice snapshot.
await db.exec(`set test.uid='${user}';set role authenticated`);await submit(1);await db.exec('reset role');
assert.deepEqual((await db.query(`select snapshot from invoices where customer_id='${custB}'`)).rows[0].snapshot,invoiceB.snapshot);
// Revision invalidates only the affected approval and removes its previous billable quantity.
await db.exec(`set role authenticated`);await submit(0.5);await db.exec('reset role');
const revised=(await db.query(`select * from invoices where customer_id='${custA}'`)).rows[0];
assert.equal(revised.calculation_blocked,true);assert.equal(revised.subtotal,0);
assert.equal((await db.query(`select subtotal from invoices where customer_id='${custB}'`)).rows[0].subtotal,12875);
await assert.rejects(db.exec(`update invoices set status='finalized' where customer_id='${custA}'`),/申請・承認/);
await db.exec(`set test.uid='${manager}';set role authenticated`);
await rpc(`public.decide_route_billing_quantity('${a.id}',0.5,'approve','',2,'${siteA}',20000)`);await db.exec('reset role');
assert.equal((await db.query(`select subtotal from invoices where customer_id='${custA}'`)).rows[0].subtotal,10300);
// A newly completed visit cannot be silently omitted from an already approved customer day.
const extra=id(60);
await db.exec(`insert into private.route_visit_reports values('${extra}','${company}','${user}','2026-10-12','completed',${json([{worker_id:worker}])},${json([{worker_id:worker}])},'${siteA}','現場A','${id(61)}','${id(62)}','${id(63)}')`);
await assert.rejects(db.exec(`update invoices set status='finalized' where customer_id='${custA}'`),/申請・承認/);
await assert.rejects(db.exec(`insert into invoices(company_id,customer_id,billing_period_start,billing_period_end,status) values('${company}','${custA}','2026-10-01','2026-10-31','finalized')`),/申請・承認/);
await db.exec(`set test.uid='${user}';set role authenticated`);
await rpc(`public.submit_route_customer_day_allocations('${worker}',array['${reportA}'::uuid,'${extra}'::uuid],${json([{customer_id:custA,quantity:0.5}])})`);
await db.exec(`set test.uid='${manager}'`);
await rpc(`public.decide_route_billing_quantity('${a.id}',0.5,'approve','',3,'${siteA}',20000)`);
await db.exec('reset role');
assert.equal((await db.query(`select subtotal from invoices where customer_id='${custA}'`)).rows[0].subtotal,10300);
await db.exec("update invoices set status='finalized',finalized_at=now()");
const finalized=(await db.query('select snapshot from invoices order by customer_id')).rows;
await db.exec(`set test.uid='${user}';set role authenticated`);
await assert.rejects(submit(1),/確定済み/);await db.exec('reset role');
await db.exec(`select private.refresh_automatic_invoice('${company}','${custA}','2026-10-12')`);
assert.deepEqual((await db.query('select snapshot from invoices order by customer_id')).rows,finalized);
console.log('PASS route-approved quantities create separate customer drafts, totals/tax/welfare, pending and unallocated finalization guards, revision/retry, finalized history and canonical attendance preserved');
await db.close();
