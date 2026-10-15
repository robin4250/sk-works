// Disposable real PostgreSQL only. Never connects to Supabase or an existing app DB.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const module = await import(pathToFileURL(process.argv[2]).href);
const {Client} = module.default ?? module;
const raw = process.env.SKO_SITE_CONTRACT_DATABASE_URL;
if (!raw) throw new Error('SKO_SITE_CONTRACT_DATABASE_URL required');
const url = new URL(raw);
if (!['postgres:', 'postgresql:'].includes(url.protocol) ||
    !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) ||
    url.search || !url.pathname.toLowerCase().includes('fixture')) {
  throw new Error('Only localhost disposable fixture database URL is allowed');
}
const database = `sko_site_contract_fixture_${process.pid}_${Date.now()}`;
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
 await admin.connect();
 await admin.query(`create database "${database}"`); created=true;
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
 for(const c of [a,b]) await c.query(`set test.uid='${admin1}'; set role authenticated`);
 const pidA=(await a.query('select pg_backend_pid() pid')).rows[0].pid;
 const pidB=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const pidCtl=(await ctl.query('select pg_backend_pid() pid')).rows[0].pid;
 const preview=async(c,company,proposal=null)=>(await c.query('select public.preview_site_contract_seal($1,$2,$3) v',[item,company,proposal])).rows[0].v;
 const send=(hash)=>a.query('select public.send_sealed_site_contract($1,$2,0,$3,$4) id',[item,parent,terms,hash]);
 const before=async()=>(await ctl.query(`select
  (select coalesce(jsonb_agg(p order by p.id),'[]') from private.site_payment_proposals p) proposals,
  (select coalesce(jsonb_agg(s order by s.proposal_id,s.company_id),'[]') from private.site_contract_seals s) seals,
  (select coalesce(jsonb_agg(c order by c.proposal_id,c.company_id),'[]') from private.site_payment_confirmations c) confirmations,
  (select coalesce(jsonb_agg(o order by o.id),'[]') from private.site_contract_notification_outbox o) notifications`)).rows[0];
 // Exact company-row wait, observed through real backend blocking state.
 const senderPreview=await preview(a,parent), initial=await before();
 await ctl.query('begin');
 await ctl.query("update companies set company_seal_style='aoyagi_reisho' where id=$1",[parent]);
 const staleSend=outcome(send(senderPreview.seal_hash));
 await waitBlocked(ctl,pidA,pidCtl);
 await ctl.query('commit');
 assert.equal((await staleSend).error?.code,'40001');
 assert.deepEqual(await before(),initial);
 console.log('PASS observed company-row wait: changed sender seal rejects atomically');
 const refreshed=await preview(a,parent);
 assert.notEqual(refreshed.seal_hash,senderPreview.seal_hash);
 const proposal=(await send(refreshed.seal_hash)).rows[0].id;
 await b.query(`set test.uid='${admin2}'`);
 const recipientPreview=await preview(b,child,proposal), sent=await before();
 await ctl.query('begin');
 await ctl.query("update companies set name='変更後会社名' where id=$1",[child]);
 const staleApprove=outcome(b.query('select public.approve_sealed_site_contract($1,$2,1,$3)',[proposal,child,recipientPreview.seal_hash]));
 await waitBlocked(ctl,pidB,pidCtl);
 await ctl.query('commit');
 assert.equal((await staleApprove).error?.code,'40001');
 assert.deepEqual(await before(),sent);
 console.log('PASS observed company-row wait: changed recipient name rejects atomically');
 const approvedPreview=await preview(b,child,proposal);
 await b.query('select public.approve_sealed_site_contract($1,$2,1,$3)',[proposal,child,approvedPreview.seal_hash]);
 const approved=await before();
 // Seal updates after approval must never change the earlier records.
 await ctl.query("update companies set company_seal_style='legacy',name='さらに変更' where id=$1",[child]);
 await b.query('select public.approve_sealed_site_contract($1,$2,1,$3)',[proposal,child,approvedPreview.seal_hash]);
 assert.deepEqual(await before(),approved);
 console.log('PASS committed old proposal, terms, actors, seals and outbox remain identical');
 console.log('Scope: actual PostgreSQL company-row name/style races; shared authorization helpers unchanged.');
} finally {
 for(const c of clients) { try { await c.query('rollback'); } catch {} }
 await Promise.allSettled(clients.map(c=>c.end()));
 if(created) await admin.query(`drop database "${database}" with (force)`);
 await admin.end();
}
