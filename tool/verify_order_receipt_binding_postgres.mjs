// Disposable real PostgreSQL only. Never connects to Supabase or an existing app DB.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const module = await import(pathToFileURL(process.argv[2]).href);
const {Client} = module.default ?? module;
const raw = process.env.SKO_ORDER_BINDING_DATABASE_URL;
if (!raw) throw new Error('SKO_ORDER_BINDING_DATABASE_URL required');
const url = new URL(raw);
if (!['postgres:', 'postgresql:'].includes(url.protocol) ||
    !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) ||
    url.search || !url.pathname.toLowerCase().includes('fixture')) {
  throw new Error('Only localhost disposable fixture database URL is allowed');
}
const database = `sko_order_binding_fixture_${process.pid}_${Date.now()}`;
const admin = new Client({connectionString: raw});
const clients = [];
let created = false;
const ids=Array.from({length:9},(_,i)=>`00000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
const [parent,child,admin1,admin2,site1,site2,delivery,item,outsider]=ids;
const terms={effective_from:'2026-10-15',period_start:'2026-10-01',period_end:'2026-10-31',mode:'square_meter',unit_price_yen:1200,area:12.5,base_amount_yen:15000,adjustments:[],tax_included:false,tax_amount_yen:1500,tax_rate:10,taxable_amount_yen:15000,rounding_rule:'floor',final_amount_yen:16500};
async function connect() {
  const u=new URL(raw); u.pathname=`/${database}`;
  const c=new Client({connectionString:u.href}); await c.connect(); clients.push(c);
  await c.query("set statement_timeout='15s'; set lock_timeout='12s'");
  return c;
}
function outcome(promise) { return promise.then(value=>({value}),error=>({error})); }
async function waitBlocked(observer,pid,blocker) {
  const deadline=Date.now()+5000;
  let lastBlockers=[];
  while(Date.now()<deadline) {
    // A second tuple-lock waiter can wait behind the first waiter rather than
    // directly on the row holder. Observe the real chain to that holder;
    // UNION deduplicates backend IDs so an unexpected cycle cannot recurse forever.
    const r=await observer.query(`with recursive blockers(pid) as (
      select unnest(pg_blocking_pids($1::integer))
      union
      select unnest(pg_blocking_pids(blockers.pid)) from blockers
    ) select exists(select 1 from blockers where pid=$2::integer) blocked,
      array(select pid from blockers order by pid) blockers`,[pid,blocker]);
    lastBlockers=r.rows[0].blockers;
    if(r.rows[0].blocked) return;
    await new Promise(resolve=>setTimeout(resolve,25));
  }
  throw new Error(`Expected backend ${pid} to wait for ${blocker}; observed chain ${lastBlockers}`);
}
try {
 await admin.connect();await admin.query(`create database "${database}"`);created=true;
 const ctl=await connect(), a=await connect(), b=await connect();
 await ctl.query(`do $$ begin if not exists(select from pg_roles where rolname='anon') then create role anon; end if; if not exists(select from pg_roles where rolname='authenticated') then create role authenticated; end if; end $$; create schema private; create schema auth;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create function private.account_access_allowed() returns boolean language sql as $$ select auth.uid() is not null $$;
create table companies(id uuid primary key,name text,postal_code text,address text,phone text,fax text,company_seal_enabled boolean not null default true); create table company_members(company_id uuid,user_id uuid,role text);
create table sites(id uuid primary key,company_id uuid,name text); create table private.company_connections(parent_company_id uuid,child_company_id uuid,status text);
create table private.document_deliveries(id uuid primary key,sender_company_id uuid,recipient_company_id uuid);
create table private.company_data_delivery_items(id uuid primary key,delivery_id uuid,payload_kind text,payload jsonb);
create table public.site_financial_settings(site_id uuid primary key,billing_square_meter_unit_price_yen integer,billing_square_meter_quantity numeric,billing_contract_amount_yen integer,billing_allowance_1_name text,billing_allowance_1_amount_yen integer,billing_allowance_2_name text,billing_allowance_2_amount_yen integer,billing_allowance_3_name text,billing_allowance_3_amount_yen integer);
create table private.site_share_inbox(data_item_id uuid primary key,recipient_company_id uuid,status text,accepted_site_id uuid);
grant usage on schema private,auth to authenticated;
`);
 await ctl.query(await fs.readFile(new URL('../supabase/migrations/20261008201215_site_payment_agreement_staged.sql',import.meta.url),'utf8'));
 await ctl.query(await fs.readFile(new URL('../supabase/migrations/20261008212855_site_payment_company_snapshot.sql',import.meta.url),'utf8'));
 await ctl.query(`insert into companies(id,name) values('${parent}','親会社'),('${child}','下請会社'); insert into company_members values('${parent}','${admin1}','admin'),('${child}','${admin2}','admin'); insert into sites values('${site1}','${parent}','現場'),('${site2}','${child}','現場'); insert into private.company_connections values('${parent}','${child}','accepted'); insert into private.document_deliveries values('${delivery}','${parent}','${child}'); insert into private.company_data_delivery_items values('${item}','${delivery}','site_share','{"source_site_id":"${site1}"}'); insert into private.site_share_inbox values('${item}','${child}','accepted','${site2}'); `);
 await ctl.query('insert into private.site_payment_agreement_rollout values($1,true),($2,true)',[parent,child]);
 await ctl.query("alter table companies add column company_seal_style text default 'legacy'; create function private.aoyagi_reisho_name_supported(text) returns boolean language sql as $$select true$$;");
 const source=await fs.readFile(new URL('../supabase/migrations/20261010160154_company_seal_png_designs.sql',import.meta.url),'utf8');
 await ctl.query(source.slice(source.indexOf('create or replace function private.document_company_seal_snapshot')));
 await ctl.query(await fs.readFile(new URL('staged/site_contract_sealed_revision.sql',import.meta.url),'utf8'));

 await ctl.query(`alter table companies add column tax_rate numeric default 10;
 alter table sites add column customer_id uuid;
 alter table site_financial_settings add column company_id uuid,add column billing_unit_price_yen integer default 32800,add column billing_monthly_rate_yen integer default 0,add column billing_rate_formula jsonb default '{"base_mode":"daily","hourly_base":false}',add column billing_rate_overrides jsonb default '{}';
 create table customers(id uuid primary key,company_id uuid);
 create table trade_companies(id uuid primary key,company_id uuid,linked_company_id uuid,trade_role text,customer_id uuid);
 create table trade_company_contracts(company_id uuid,trade_company_id uuid,contract_method text,daily_rate_yen integer,monthly_rate_yen integer,square_meter_unit_price_yen integer,square_meter_quantity numeric,contract_amount_yen integer);
 create table site_calculation_source_preferences(company_id uuid,site_id uuid,output_type text,trade_company_id uuid,source text,selected_at timestamptz);
 insert into customers values('${delivery}','${parent}');update sites set customer_id='${delivery}' where id='${site1}';
 insert into trade_companies values('${delivery}','${parent}','${child}','customer','${delivery}');
 insert into site_calculation_source_preferences values('${parent}','${site1}','invoice','${delivery}','site','2026-10-01');
 insert into site_financial_settings(site_id,company_id,billing_unit_price_yen,billing_monthly_rate_yen,billing_square_meter_unit_price_yen,billing_square_meter_quantity,billing_contract_amount_yen,billing_rate_formula,billing_rate_overrides)
 values('${site1}','${parent}',32800,0,0,0,0,'{"base_mode":"daily","hourly_base":false}','{}');`);
 await ctl.query(await fs.readFile(new URL('staged/site_contract_receipt_binding.sql',import.meta.url),'utf8'));
 await ctl.query('insert into site_contract_binding_private.rollout values($1,true),($2,true)',[parent,child]);
 for(const c of [ctl,a,b]) await c.query(`set test.uid='${admin1}'`);
 const pidA=(await a.query('select pg_backend_pid() pid')).rows[0].pid;
 const pidB=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const pidCtl=(await ctl.query('select pg_backend_pid() pid')).rows[0].pid;
 const preview=async(c)=>(await c.query('select site_contract_binding_private.preview($1,$2,$3) v',[parent,item,'invoice'])).rows[0].v;
 const bind=async(c,p,command,rev=0)=>(await c.query('select site_contract_binding_private.bind($1,$2,$3,$4,$5) v',[parent,item,command,rev,p])).rows[0].v;
 const oldPreview=c=>c.query('select public.preview_site_contract_seal($1,$2,null)',[item,parent]);
 const command='00000000-0000-0000-0000-000000000099';
 // Old real sealed preview starts first and holds canonical inbox row.
 let p=await preview(ctl);
 await a.query('begin');await oldPreview(a);
 const waiting=outcome(bind(b,p,command));await waitBlocked(ctl,pidB,pidA);
 await a.query('commit');assert.equal((await waiting).value.binding_revision,1);
 // Binder starts first; unchanged real old sealed preview waits and succeeds.
 p=await preview(ctl);
 await a.query('begin');await bind(a,p,'00000000-0000-0000-0000-000000000098',1);
 const oldWaiting=outcome(oldPreview(b));await waitBlocked(ctl,pidB,pidA);
 await a.query('rollback');assert.ok((await oldWaiting).value);
 assert.equal((await ctl.query('select count(*)::int n from site_contract_binding_private.bindings')).rows[0].n,1);
 // Genuine source change lock wait must reject a stale preview after commit.
 p=await preview(ctl);await a.query('begin');
 await a.query('update site_financial_settings set billing_unit_price_yen=34000 where site_id=$1',[site1]);
 const stale=outcome(bind(b,p,'00000000-0000-0000-0000-000000000097',1));
 await waitBlocked(ctl,pidB,pidA);await a.query('commit');assert.equal((await stale).error?.code,'40001');
 // Existing rollout OFF is acquired before inbox; no reverse-order deadlock.
 p=await preview(ctl);await a.query('begin');await a.query('update private.site_payment_agreement_rollout set enabled=false where company_id=$1',[child]);
 const off=outcome(bind(b,p,'00000000-0000-0000-0000-000000000096',1));
 await waitBlocked(ctl,pidB,pidA);await a.query('commit');assert.equal((await off).error?.code,'55000');
 await ctl.query('update private.site_payment_agreement_rollout set enabled=true');
 assert.equal((await ctl.query('select count(*)::int n from site_contract_binding_private.bindings')).rows[0].n,1);
 console.log('real PG: unchanged sealed preview / binder both orders observed; rollback, stale source and existing rollout OFF rejected');
} finally {
 for(const c of clients) {try {await c.query('rollback');await c.end();}catch{}}
 if(created){await admin.query(`drop database "${database}" with (force)`);}
 await admin.end();
}
