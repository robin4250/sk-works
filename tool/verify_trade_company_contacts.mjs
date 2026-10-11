import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const db=new PGlite();
const c='10000000-0000-0000-0000-000000000001',u='10000000-0000-0000-0000-000000000002',id='10000000-0000-0000-0000-000000000003',other='20000000-0000-0000-0000-000000000001';
await db.exec(`create role authenticated;create role anon;create schema auth;create schema private;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.actor',true),'')::uuid$$;
create function private.account_access_allowed() returns boolean language sql stable as $$select current_setting('fixture.blocked',true) is distinct from 'true'$$;
create function private.current_company_admin_id() returns uuid language sql stable as $$select case when current_setting('fixture.role',true) in ('owner','admin','manager') then '${c}'::uuid end$$;
create function private.ensure_trade_company_legacy_links(uuid) returns void language sql as $$select$$;
create table trade_companies(id uuid primary key default gen_random_uuid(),company_id uuid,name text,trade_role text,postal_code text,address text,phone text,email text,corporate_number text,notes text,created_by uuid,updated_by uuid,updated_at timestamptz,linked_company_id uuid,link_status text,customer_id uuid,partner_company_id uuid);
create table trade_company_contracts(company_id uuid,trade_company_id uuid,contract_method text,daily_rate_yen int,monthly_rate_yen int,square_meter_unit_price_yen int,square_meter_quantity numeric,contract_amount_yen int);
insert into trade_companies(id,company_id,name,trade_role,notes) values('${id}','${c}','会社','both','元の備考'),('${other}','${other}','別会社','customer','保持');
insert into trade_company_contracts values('${c}','${id}','daily',12345,0,0,0,0);
set fixture.actor='${u}';set fixture.role='admin';grant usage on schema public,auth,private to authenticated,anon;`);
const original=fs.readFileSync(root+'/supabase/migrations/20261004132001_add_trade_company_master_and_contract_sources.sql','utf8');
for(const name of ['save_trade_company','trade_company_workspace']){
 const start=original.indexOf(`create or replace function private.${name}(`),end=original.indexOf('\n$$;',start)+4;
 await db.exec(original.slice(start,end));
}
const before=(await db.query('select private.trade_company_workspace() data')).rows[0].data;
await db.exec(fs.readFileSync(root+'/supabase/migrations/20261011205233_trade_company_representative_contacts.sql','utf8'));
const data={id,name:'会社編集',trade_role:'both',notes:'担当 090-1234-5678',representative_name:' 代表者 ',representative_phone:'090-1234-5678'};
await db.exec('set role authenticated');
assert.equal((await db.query('select public.save_trade_company_contact($1) id',[data])).rows[0].id,id);
let rows=(await db.query('select public.trade_company_contact_workspace() data')).rows[0].data;
assert.equal(rows[0].representative_name,'代表者');assert.equal(rows[0].representative_phone,'090-1234-5678');
assert.equal(rows[0].notes,data.notes);assert.equal(rows[0].daily_rate_yen,before[0].daily_rate_yen);
await assert.rejects(db.query('select public.save_trade_company_contact($1)',[{...data,id:other}]),e=>e.code==='P0001');
await assert.rejects(db.query('select public.save_trade_company_contact($1)',[{...data,representative_name:'x'.repeat(201)}]),e=>e.code==='22023');
for(const role of ['owner','admin','manager']){await db.exec(`set fixture.role='${role}'`);assert.equal((await db.query('select public.trade_company_contact_workspace() data')).rows[0].data.length,1);}
for(const role of ['viewer','employee']){await db.exec(`set fixture.role='${role}'`);await assert.rejects(db.query('select public.save_trade_company_contact($1)',[data]),e=>e.code==='42501');}
await db.exec("set fixture.role='admin';set fixture.blocked='true'");
await assert.rejects(db.query('select public.save_trade_company_contact($1)',[data]),e=>e.code==='42501');
await db.exec("set fixture.blocked='false';set fixture.actor=''");
await assert.rejects(db.query('select public.trade_company_contact_workspace()'),e=>e.code==='42501');
await db.exec('reset role;set role anon');
await assert.rejects(db.query('select public.trade_company_contact_workspace()'),e=>e.code==='42501');
await db.close();console.log('PASS: scoped representative save/read, original company writer/workspace delegated, contract preserved, foreign-company, oversized, viewer/employee/blocked/anonymous denied');
