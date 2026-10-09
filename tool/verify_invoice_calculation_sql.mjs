// Disposable PostgreSQL fixture; never connects to production.
// node tool/verify_invoice_calculation_sql.mjs /tmp/sko-sql-runtime/node_modules/@electric-sql/pglite/dist/index.js
import fs from 'node:fs';
import assert from 'node:assert/strict';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const db=new PGlite();
const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const original=fs.readFileSync(repo+'/supabase/migrations/20261006173142_common_rate_formula_invoice_hourly.sql','utf8');
const helpers=original.slice(original.indexOf('CREATE OR REPLACE FUNCTION'),original.indexOf('CREATE OR REPLACE FUNCTION private.refresh_automatic_invoice'));
try {
await db.exec(`create schema private;create schema auth;
create function auth.uid() returns uuid language sql as $$select '00000000-0000-0000-0000-000000000001'::uuid$$;
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
insert into companies values('00000000-0000-0000-0000-000000000002',10);
insert into customers values('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002','Fixture customer','');
insert into sites(id,company_id,customer_id,name) values('00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','Fixture site');
insert into site_financial_settings(company_id,site_id,billing_monthly_rate_yen) values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000004',300000);
insert into attendance_entries values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000004','2026-10-01','day',20,0,0,'{}');`);
await db.exec(helpers);
await db.exec(original.slice(original.indexOf('CREATE OR REPLACE FUNCTION private.refresh_automatic_invoice')));
const refresh=`select private.refresh_automatic_invoice('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','2026-10-01')`;
await db.exec(refresh);
assert.equal((await db.query('select subtotal from invoices')).rows[0].subtotal,6000000); // Baseline defect reproduced.
await db.exec(fs.readFileSync(repo+'/supabase/migrations/20261008035509_invoice_registered_method_amounts_and_formula_labels.sql','utf8'));
await db.exec(refresh);
assert.equal((await db.query('select subtotal from invoices')).rows[0].subtotal,300000);
assert.equal((await db.query("select private.rate_formula_label('{}','overtime') as label")).rows[0].label,'1日単価÷8×1.25');
await db.exec(`update site_financial_settings set billing_monthly_rate_yen=0,billing_unit_price_yen=12000,billing_overtime_hour_rate_yen=2200;update attendance_entries set base_man_days=1,overtime_hours=2;`);
await db.exec(refresh);
assert.equal((await db.query('select subtotal from invoices')).rows[0].subtotal,16400);
const check=async(update,days,ot,early,expected)=>{
 await db.exec('update site_financial_settings set '+update);
 await db.exec(`update attendance_entries set base_man_days=${days},overtime_hours=${ot},early_hours=${early}`);
 await db.exec(refresh);
 assert.equal((await db.query('select subtotal from invoices')).rows[0].subtotal,expected);
};
await check("billing_rate_overrides='{\"overtime\":2500}'",1,2,0,17000);
await check("billing_rate_overrides='{}',billing_early_hour_rate_yen=2300",1,0,2,16600);
await db.exec("update attendance_entries set work_category='night'");
await check("billing_rate_overrides='{}',billing_early_hour_rate_yen=2300",1,0,2,22600);
await db.exec("update attendance_entries set work_category='day'");
await check("billing_unit_price_yen=0,billing_square_meter_unit_price_yen=2500,billing_square_meter_quantity=100",20,0,0,250000);
await check("billing_square_meter_unit_price_yen=0,billing_square_meter_quantity=0,billing_contract_amount_yen=500000",20,0,0,500000);
await check("billing_contract_amount_yen=0,billing_unit_price_yen=12000,billing_overtime_hour_rate_yen=0,billing_early_hour_rate_yen=0",0.5,0,0,6000);
// Independent expected integers, including half-yen rate rounding.
for(const [category,labor,total] of [['day',17625,19969],['night',26439,29955],['holiday',23793,26958],['holiday_night',28200,31951]]) {
 await db.exec(`update attendance_entries set work_category='${category}'`);
 await check("welfare_rate=3,billing_rate_formula='{}'",1,2,1,labor+Math.round(labor*0.03));
 assert.equal((await db.query('select grand_total from invoices')).rows[0].grand_total,total);
}
await db.exec("update attendance_entries set work_category='day'");
await check("welfare_rate=0,billing_rate_formula='{\"base_mode\":\"hourly\",\"hourly_rate_yen\":1500}'",1,2,0,15750);
await check("billing_rate_formula='{\"overtime_multiplier\":1.4}'",1,2,0,16200);
await check("billing_rate_formula='{}'",0.5,0,0,6000);
await db.exec("update invoices set status='approved';update attendance_entries set base_man_days=20");
await db.exec(refresh);
assert.equal((await db.query('select subtotal from invoices')).rows[0].subtotal,6000);
if(process.argv.includes('--seal-snapshots')) {
 await db.exec(`create role anon;create role authenticated;
 alter table companies add column name text default '株式会社テスト建設',add column company_seal_enabled boolean default true,add column updated_at timestamptz;
 create table company_members(company_id uuid,user_id uuid,role text);
 create function private.account_access_allowed() returns boolean language sql as $$select true$$;
 create table payment_certificates(id uuid primary key,company_id uuid,snapshot jsonb);
 create table payroll_statements(id uuid primary key,company_id uuid,detail jsonb);
 create function private.refresh_automatic_payment_certificate(cid uuid,partner uuid,day date) returns void language plpgsql as $$
 declare existing public.payment_certificates; snapshot_value jsonb;
 begin snapshot_value:='{}';if existing.id is null then return;end if;end $$;
 create function private.payroll_document_metadata(p_statement_id uuid) returns jsonb language sql as $$
 select jsonb_build_object('company_seal_enabled',c.company_seal_enabled,'old',true)
 from payroll_statements ps join companies c on c.id=ps.company_id where ps.id=p_statement_id $$;
 create function private.saved_site_payment_document(p_proposal uuid,p_company uuid) returns jsonb language plpgsql as $$
 declare result jsonb;
 begin select jsonb_build_object('snapshot_version',2,'parent_company_seal_enabled',parent.company_seal_enabled)
 into result from companies parent where parent.id=p_company;return result;end $$;`);
 await db.exec(fs.readFileSync(repo+'/supabase/migrations/20261009011357_company_seal_aoyagi_style.sql','utf8'));
 await db.exec(fs.readFileSync(repo+'/supabase/migrations/20261009012730_company_seal_document_snapshots.sql','utf8'));
 await db.exec("update companies set company_seal_style='aoyagi_reisho'");
 const legacyBefore=(await db.query('select snapshot from invoices')).rows[0].snapshot;
 await db.exec(refresh); // Existing approved invoice remains byte-for-byte unchanged.
 assert.deepEqual((await db.query('select snapshot from invoices')).rows[0].snapshot,legacyBefore);
 await db.exec("update invoices set status='draft';update attendance_entries set base_man_days=1");
 await db.exec(refresh); // An old draft is recalculated without style backfill.
 assert.equal((await db.query("select snapshot ? 'company_seal_snapshot' present from invoices")).rows[0].present,false);
 await db.exec('delete from invoices');
 await db.exec(refresh);
 const initial=(await db.query('select snapshot,updated_at from invoices')).rows[0];
 assert.equal(initial.snapshot.company_seal_snapshot.style,'aoyagi_reisho');
 await db.exec("update companies set name='株式会社別名',company_seal_style='legacy'");
 await db.exec(refresh);
 const repeated=(await db.query('select snapshot,updated_at from invoices')).rows[0];
 assert.deepEqual(repeated.snapshot,initial.snapshot);
 assert.equal(String(repeated.updated_at),String(initial.updated_at)); // No redundant cron write.
 await db.exec('update attendance_entries set overtime_hours=3');
 await db.exec(refresh);
 const changed=(await db.query('select snapshot from invoices')).rows[0].snapshot;
 assert.deepEqual(changed.company_seal_snapshot,initial.snapshot.company_seal_snapshot);
 assert.notDeepEqual(changed,initial.snapshot); // Real financial change still recalculates.
 console.log('PASS: real invoice cron stable, old approved/draft not backfilled, financial changes retain original seal');
}
console.log('Invoice monthly/area/contract, legacy and JSON overrides, half-day, decimal labels, finalized preservation passed');
} finally {await db.close();}
