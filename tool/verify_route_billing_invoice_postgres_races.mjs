// Only a fresh, disposable local PostgreSQL 17 database is permitted.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const connectionString=process.env.SKO_ROUTE_INVOICE_RACE_DATABASE_URL;
const url=new URL(connectionString??'postgres://invalid');
const database='sko_route_invoice_race_fixture';
if(!['postgres:','postgresql:'].includes(url.protocol)||url.search||url.hash||!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!==`/${database}`) throw new Error('Only local disposable invoice fixture permitted');
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
const clients=[];
async function connect(name){
 const c=new Client({connectionString,application_name:name});
 if(!['127.0.0.1','localhost','::1'].includes(c.connectionParameters.host)||c.connectionParameters.database!==database) throw new Error('Effective fixture connection changed');
 await c.connect();clients.push(c);await c.query("set statement_timeout='20s';set lock_timeout='15s'");return c;
}
const read=name=>fs.readFile(new URL('../'+name,import.meta.url),'utf8');
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [company,worker,user,manager,customer,site,report]=Array.from({length:7},(_,i)=>id(i+1));
const settle=p=>{p.catch(()=>{});return p;};
let admin,reviewer,requester,finalizer,observer;
async function waitForBlocked(name){
 const until=Date.now()+8000;
 while(Date.now()<until){
  await observer.query('select pg_stat_clear_snapshot()');
  const r=await observer.query("select count(*)::int n from pg_stat_activity where application_name=$1 and wait_event_type='Lock'",[name]);
  if(r.rows[0].n===1)return;
  await new Promise(resolve=>setTimeout(resolve,25));
 }
 throw new Error(`Actual blocked connection not observed: ${name}`);
}
const actor=(c,uid)=>c.query(`set test.uid='${uid}';set role authenticated`);
const submit=(c,quantity)=>c.query('select public.submit_route_customer_day_allocations($1,$2,$3) v',[worker,[report],JSON.stringify([{customer_id:customer,quantity}])]);
const approve=(c,request,quantity,version)=>c.query("select public.decide_route_billing_quantity($1,$2,'approve','reviewed',$3,$4,20000) v",[request.id,quantity,version,site]);
try{
 admin=await connect('route-invoice-admin');reviewer=await connect('route-invoice-reviewer');requester=await connect('route-invoice-requester');finalizer=await connect('route-invoice-finalizer');observer=await connect('route-invoice-observer');
 assert.match((await admin.query('show server_version')).rows[0].server_version,/^17\./);
 assert.equal((await admin.query("select count(*)::int n from pg_namespace where nspname in ('private','auth')")).rows[0].n,0,'Never clear an existing database');
 const verifier=await read('tool/verify_route_billing_invoice_integration.mjs');
 const fixture=verifier.match(/await db\.exec\(`([\s\S]*?)`\);/)[1];
 assert.ok(!fixture.includes('${'));await admin.query(fixture);
 const original=await read('supabase/migrations/20261006173142_common_rate_formula_invoice_hourly.sql');
 await admin.query(original.slice(0,original.indexOf('CREATE OR REPLACE FUNCTION private.refresh_automatic_invoice')));
 await admin.query(await read('supabase/migrations/20261008035509_invoice_registered_method_amounts_and_formula_labels.sql'));
 await admin.query(await read('supabase/tests/route_customer_day_billing_allocations_schema.sql'));
 await admin.query(await read('supabase/tests/route_billing_invoice_integration.sql'));
 await admin.query('insert into companies values($1,10)',[company]);
 await admin.query("insert into company_members values($1,$2,'employee'),($1,$3,'manager')",[company,user,manager]);
 await admin.query("insert into workers values($1,$2,'本人')",[worker,company]);
 await admin.query("insert into customers values($1,$2,'会社A','')",[customer,company]);
 await admin.query("insert into sites(id,company_id,customer_id,name) values($1,$2,$3,'現場A')",[site,company,customer]);
 await admin.query('insert into site_financial_settings(company_id,site_id,billing_unit_price_yen,welfare_rate) values($1,$2,20000,3)',[company,site]);
 await admin.query("insert into private.route_visit_reports values($1,$2,$3,'2026-10-12','completed',$4,$4,$5,'現場A',$6,$7,$8)",[report,company,user,JSON.stringify([{worker_id:worker}]),site,id(20),id(21),id(22)]);
 const reportBefore=(await admin.query('select to_jsonb(r) value from private.route_visit_reports r')).rows;
 await actor(requester,user);await actor(reviewer,manager);
 const request=(await submit(requester,1)).rows[0].v[0];
 const invoice=(await admin.query('select id from invoices')).rows[0].id;
 // Approval waits for an already-held invoice row. Finalization must fail promptly,
 // rather than waiting for its advisory lock and creating a row/advisory deadlock.
 await finalizer.query('begin');await finalizer.query('select id from invoices where id=$1 for update',[invoice]);
 const approval=settle(approve(reviewer,request,1,1));await waitForBlocked('route-invoice-reviewer');
 await assert.rejects(finalizer.query("update invoices set status='finalized' where id=$1",[invoice]),e=>e.code==='40001');
 await finalizer.query('rollback');await approval;
 assert.equal((await admin.query('select subtotal from invoices')).rows[0].subtotal,20600);
 // A revision holds the updated draft until commit; concurrent finalization then
 // sees the new pending request and fails instead of sealing stale approved totals.
 await requester.query('begin');await submit(requester,0.5);
 const finalization=settle(finalizer.query("update invoices set status='finalized',finalized_at=now() where id=$1",[invoice]));
 await waitForBlocked('route-invoice-finalizer');await requester.query('commit');
 await assert.rejects(finalization,/申請・承認/);
 assert.equal((await admin.query('select calculation_blocked from invoices')).rows[0].calculation_blocked,true);
 await approve(reviewer,request,0.5,2);
 await finalizer.query("update invoices set status='finalized',finalized_at=now() where id=$1",[invoice]);
 const finalized=(await admin.query('select to_jsonb(i) value from invoices i')).rows;
 assert.equal(finalized[0].value.subtotal,10300);
 await assert.rejects(submit(requester,1),/確定済み/);
 await admin.query("set test.uid='"+manager+"'");
 await admin.query("select private.refresh_automatic_invoice($1,$2,'2026-10-12')",[company,customer]);
 assert.deepEqual((await admin.query('select to_jsonb(i) value from invoices i')).rows,finalized);
 assert.deepEqual((await admin.query('select to_jsonb(r) value from private.route_visit_reports r')).rows,reportBefore);
 assert.equal((await admin.query('select count(*)::int n from attendance_entries')).rows[0].n,0);
 console.log('PASS PostgreSQL 17 approval/finalization and revision/finalization races; latest quantities, signatures and finalized documents preserved');
}finally{
 await Promise.allSettled(clients.map(async c=>{try{await c.query('rollback');}finally{await c.end();}}));
}
