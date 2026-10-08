// Disposable PostgreSQL; never connects to production.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
try {
await db.exec(`create schema private;create schema auth;create role anon;create role authenticated;
create function auth.uid() returns uuid language sql as $$select '${id(99)}'::uuid$$;
create function private.current_company_admin_id() returns uuid language sql as $$select '${id(1)}'::uuid$$;
create table public.trade_companies(id uuid,company_id uuid,trade_role text,customer_id uuid,partner_company_id uuid);
create table public.customers(id uuid,company_id uuid);
create table public.sites(id uuid,company_id uuid,name text,customer_id uuid);
create table public.partner_companies(id uuid,company_id uuid);
create table public.workers(id uuid,company_id uuid,partner_company_id uuid);
create table public.attendance_entries(company_id uuid,site_id uuid,worker_id uuid,work_date date);
create table public.site_calculation_source_preferences(company_id uuid,site_id uuid,output_type text,trade_company_id uuid,source text,selected_by uuid,selected_at timestamptz,primary key(company_id,site_id,output_type));
create table public.trade_company_contracts(company_id uuid,trade_company_id uuid,contract_method text);
create table public.site_financial_settings(company_id uuid,site_id uuid,billing_unit_price_yen int,billing_monthly_rate_yen int,billing_square_meter_unit_price_yen int,billing_square_meter_quantity numeric,billing_contract_amount_yen int,worker_daily_rate_yen int,overtime_hour_rate_yen int,early_hour_rate_yen int);
create function private.refresh_automatic_invoice(uuid,uuid,date) returns void language sql as $$select$$;
create function private.refresh_automatic_payment_certificate(uuid,uuid,date) returns void language sql as $$select$$;
create function private.refresh_automatic_payroll(uuid,uuid,date) returns void language sql as $$select$$;
insert into customers values('${id(3)}','${id(1)}');
insert into sites values('${id(2)}','${id(1)}','Monthly site','${id(3)}');
insert into trade_companies values('${id(4)}','${id(1)}','customer','${id(3)}',null),('${id(5)}','${id(1)}','customer','${id(6)}',null),('${id(7)}','${id(8)}','customer','${id(3)}',null);
insert into site_financial_settings(company_id,site_id,billing_monthly_rate_yen) values('${id(1)}','${id(2)}',300000);
insert into trade_company_contracts values('${id(1)}','${id(4)}','monthly');`);
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261008044046_validate_registered_calculation_sources.sql'),'utf8'));
const conflicts=(await db.query(`select private.trade_company_calculation_conflicts('${id(4)}') as value`)).rows[0].value;
if(conflicts.length!==1||!conflicts[0].conflict||!conflicts[0].site_setting_configured) throw Error('Monthly conflict missing');
for(const source of ['site','trade_company']) {
 await db.query(`select private.select_site_calculation_source('${id(2)}','invoice','${id(4)}','${source}')`);
 const saved=(await db.query('select source from site_calculation_source_preferences')).rows;
 if(saved.length!==1||saved[0].source!==source) throw Error('Choice not revisable');
}
await db.exec(`insert into partner_companies values('${id(10)}','${id(1)}');
insert into trade_companies values('${id(11)}','${id(1)}','subcontractor',null,'${id(10)}');`);
await db.query(`select private.select_site_calculation_source('${id(2)}','payroll','${id(11)}','trade_company')`);
for(const party of [id(5),id(7)]) for(const source of ['site','trade_company']) {
 let rejected=false;
 try{await db.query(`select private.select_site_calculation_source('${id(2)}','invoice','${party}','${source}')`);}catch{rejected=true;}
 if(!rejected) throw Error('Wrong party/tenant accepted');
}
await db.exec(`create or replace function private.current_company_admin_id() returns uuid language sql as $$select null::uuid$$;`);
let denied=false;try{await db.query(`select private.select_site_calculation_source('${id(2)}','invoice','${id(4)}','site')`);}catch{denied=true;}
if(!denied) throw Error('Unauthorized selection accepted');
console.log('Calculation source monthly conflict, revisable choice, tenant/party authorization passed');
} finally {await db.close();}
