// Disposable real PostgreSQL only. Never connects to Supabase or an existing app DB.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const module = await import(pathToFileURL(process.argv[2]).href);
const {Client} = module.default ?? module;
const raw = process.env.SKO_SITE_PAYMENT_DATABASE_URL;
if (!raw) throw new Error('SKO_SITE_PAYMENT_DATABASE_URL required');
const url = new URL(raw);
if (!['postgres:', 'postgresql:'].includes(url.protocol) ||
    !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) ||
    url.search || !url.pathname.toLowerCase().includes('fixture')) {
  throw new Error('Only localhost disposable fixture database URL is allowed');
}
const database = `sko_site_payment_fixture_${process.pid}_${Date.now()}`;
const admin = new Client({connectionString: raw});
const clients = [];
let created = false;
const ids=Array.from({length:9},(_,i)=>`00000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
const [parent,child,admin1,admin2,site1,site2,delivery,item,outsider]=ids;
const terms={period_start:'2026-10-01',period_end:'2026-10-31',mode:'square_meter',unit_price_yen:1200,area:12.5,base_amount_yen:15000,adjustments:[],tax_included:false,tax_amount_yen:1500,tax_rate:10,taxable_amount_yen:15000,rounding_rule:'floor',final_amount_yen:16500};
async function connect() {
  const u=new URL(raw); u.pathname=`/${database}`;
  const c=new Client({connectionString:u.href}); await c.connect(); clients.push(c);
  await c.query("set statement_timeout='15s'; set lock_timeout='12s'");
  return c;
}
function outcome(promise) { return promise.then(value=>({value}),error=>({error})); }
async function waitBlocked(observer,pid,blocker) {
  const deadline=Date.now()+5000;
  while(Date.now()<deadline) {
    const r=await observer.query('select $2::integer = any(pg_blocking_pids($1::integer)) blocked',[pid,blocker]);
    if(r.rows[0].blocked) return;
    await new Promise(resolve=>setTimeout(resolve,25));
  }
  throw new Error(`Expected backend ${pid} to wait for ${blocker}`);
}
const propose=(c,revision)=>c.query('select public.propose_site_payment_terms($1,$2,$3,$4::jsonb) id',[item,parent,revision,JSON.stringify(terms)]);
try {
 await admin.connect();
 await admin.query(`create database "${database}"`); created=true;
 const ctl=await connect(), a=await connect(), b=await connect();
 await ctl.query(`do $$ begin if not exists(select from pg_roles where rolname='anon') then create role anon; end if; if not exists(select from pg_roles where rolname='authenticated') then create role authenticated; end if; end $$; create schema private; create schema auth;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create function private.account_access_allowed() returns boolean language sql as $$ select auth.uid() is not null $$;
create table companies(id uuid primary key,name text); create table company_members(company_id uuid,user_id uuid,role text);
create table sites(id uuid primary key,company_id uuid,name text); create table private.company_connections(parent_company_id uuid,child_company_id uuid,status text);
create table private.document_deliveries(id uuid primary key,sender_company_id uuid,recipient_company_id uuid);
create table private.company_data_delivery_items(id uuid primary key,delivery_id uuid,payload_kind text,payload jsonb);
create table public.site_financial_settings(site_id uuid primary key,billing_square_meter_unit_price_yen integer,billing_square_meter_quantity numeric,billing_contract_amount_yen integer,billing_allowance_1_name text,billing_allowance_1_amount_yen integer,billing_allowance_2_name text,billing_allowance_2_amount_yen integer,billing_allowance_3_name text,billing_allowance_3_amount_yen integer);
create table private.site_share_inbox(data_item_id uuid primary key,recipient_company_id uuid,status text,accepted_site_id uuid);
grant usage on schema private,auth to authenticated;
`);
 await ctl.query(await fs.readFile(new URL('../supabase/migrations/20261008201215_site_payment_agreement_staged.sql',import.meta.url),'utf8'));
 await ctl.query(`insert into companies values('${parent}','親会社'),('${child}','下請会社'); insert into company_members values('${parent}','${admin1}','admin'),('${child}','${admin2}','admin'); insert into sites values('${site1}','${parent}','現場'),('${site2}','${child}','現場'); insert into private.company_connections values('${parent}','${child}','accepted'); insert into private.document_deliveries values('${delivery}','${parent}','${child}'); insert into private.company_data_delivery_items values('${item}','${delivery}','site_share','{"source_site_id":"${site1}"}'); insert into private.site_share_inbox values('${item}','${child}','accepted','${site2}'); `);
 await ctl.query('insert into private.site_payment_agreement_rollout values($1,true),($2,true)',[parent,child]);
 for(const c of [a,b]) await c.query(`set test.uid='${admin1}'; set role authenticated`);
 const pidA=(await a.query('select pg_backend_pid() pid')).rows[0].pid;
 const pidB=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const pidCtl=(await ctl.query('select pg_backend_pid() pid')).rows[0].pid;
 // Force both proposals into the same observed canonical lock wait.
 await ctl.query('begin');
 await ctl.query('select 1 from private.site_share_inbox where data_item_id=$1 for update',[item]);
 const first=outcome(propose(a,0)), second=outcome(propose(b,0));
 await waitBlocked(ctl,pidA,pidCtl); await waitBlocked(ctl,pidB,pidCtl);
 await ctl.query('commit');
 const results=await Promise.all([first,second]);
 assert.equal(results.filter(x=>x.value).length,1);
 assert.equal(results.filter(x=>x.error?.code==='40001').length,1);
 assert.equal((await ctl.query('select count(*)::int n from private.site_payment_proposals')).rows[0].n,1);
 console.log('PASS concurrent same revision: one proposal, one 40001');
 // Commit a stop while the caller waits on its rollout lock; fresh pair must reject.
 await ctl.query('begin');
 await ctl.query('update private.site_payment_agreement_rollout set enabled=false where company_id=$1',[parent]);
 const stopped=outcome(propose(a,1));
 await waitBlocked(ctl,pidA,pidCtl); await ctl.query('commit');
 assert.equal((await stopped).error?.code,'55000');
 assert.equal((await ctl.query('select count(*)::int n from private.site_payment_proposals')).rows[0].n,1);
 console.log('PASS rollout stop during lock wait: no proposal');
 await ctl.query('update private.site_payment_agreement_rollout set enabled=true');
 await ctl.query('begin');
 await ctl.query("update private.company_connections set status='revoked'");
 const revoked=outcome(propose(a,1));
 await waitBlocked(ctl,pidA,pidCtl); await ctl.query('commit');
 assert.match((await revoked).error?.message??'',/対応/);
 assert.equal((await ctl.query('select count(*)::int n from private.site_payment_proposals')).rows[0].n,1);
 console.log('PASS connection revoke during lock wait: no proposal');
 await ctl.query("update private.company_connections set status='accepted'");
 const old=(await ctl.query('select id from private.site_payment_proposals where revision=1')).rows[0].id;
 // Newer proposal holds canonical lock until commit, then old confirmation rejects.
 await a.query('begin'); await propose(a,1);
 const confirm=outcome(b.query('select public.confirm_site_payment_terms($1,$2)',[old,parent]));
 await waitBlocked(ctl,pidB,pidA); await a.query('commit');
 assert.equal((await confirm).error?.code,'40001');
 assert.equal((await ctl.query('select count(*)::int n from private.site_payment_confirmations')).rows[0].n,0);
 console.log('PASS newer proposal vs old confirmation: stale confirmation rejected');
 console.log('Scope excludes company deletion, membership changes and account-restriction races.');
} finally {
 for(const c of clients) { try { await c.query('rollback'); } catch {} }
 await Promise.allSettled(clients.map(c=>c.end()));
 if(created) await admin.query(`drop database "${database}" with (force)`);
 await admin.end();
}
