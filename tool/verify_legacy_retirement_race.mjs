// Demonstrates why the review-only hold must not be deployed as a safety gate.
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const pg = await import(pathToFileURL(path.resolve(process.argv[3])).href);
const Client = pg.Client ?? pg.default.Client;
const clients = Array.from({length:3},()=>new Client({connectionString:process.env.DATABASE_URL}));
await Promise.all(clients.map(c=>c.connect()));
const [a,b,c] = clients;
await c.query(`create role anon; create role authenticated; create role service_role;
 create table public.invoices(id uuid primary key,snapshot text);
 create table public.invoice_approvals(invoice_id uuid,status text);
 alter table public.invoices enable row level security;
 grant select on public.invoices to authenticated;
 create policy old_permissive on public.invoices for select to authenticated using(true);
 insert into public.invoices values('00000000-0000-0000-0000-000000000001','old'),('00000000-0000-0000-0000-000000000002','old2');
 insert into public.invoice_approvals values('00000000-0000-0000-0000-000000000001','approved'),('00000000-0000-0000-0000-000000000002','approved');`);
await c.query(await readFile(process.argv[2],'utf8'));
// Hold first: existing approval writer must wait, then fail.
await a.query('begin');
await a.query("select invoice_retirement_guard_candidate.activate('00000000-0000-0000-0000-000000000001')");
const pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
const blockedUpdate=b.query("update public.invoice_approvals set status='pending' where invoice_id='00000000-0000-0000-0000-000000000001'").then(()=>null,e=>e);
let blocked=false;
for(let i=0;i<100;i++) {
 if((await c.query('select cardinality(pg_blocking_pids($1))>0 blocked',[pid])).rows[0].blocked){blocked=true;break;}
 await new Promise(resolve=>setTimeout(resolve,30));
}
assert.equal(blocked,true);
await a.query('commit');
assert.match((await blockedUpdate)?.message ?? '', /invoice_retired/);
// Existing writer first: activation follows invoice -> approval ordering and
// waits, so the first write completes before the hold exists.
await a.query('begin');
await a.query("update public.invoice_approvals set status='pending' where invoice_id='00000000-0000-0000-0000-000000000002'");
const holdPid=(await c.query('select pg_backend_pid() pid')).rows[0].pid;
const activation=c.query("select invoice_retirement_guard_candidate.activate('00000000-0000-0000-0000-000000000002')");
let waiting=false;
for(let i=0;i<100;i++) {
 if((await b.query('select cardinality(pg_blocking_pids($1))>0 blocked',[holdPid])).rows[0].blocked){waiting=true;break;}
 await new Promise(resolve=>setTimeout(resolve,30));
}
assert.equal(waiting,true);
await a.query('commit'); await activation;
await assert.rejects(a.query("update public.invoice_approvals set status='approved' where invoice_id='00000000-0000-0000-0000-000000000002'"),/invoice_retired/);
// INSERT holds the invoice row shared before creating an approval, so
// activation must wait for the insert transaction before holding that ID.
await c.query("insert into public.invoices values('00000000-0000-0000-0000-000000000003','old3')");
await a.query('begin');
await a.query("insert into public.invoice_approvals values('00000000-0000-0000-0000-000000000003','pending')");
const insertActivation=c.query("select invoice_retirement_guard_candidate.activate('00000000-0000-0000-0000-000000000003')");
let insertWait=false;
for(let i=0;i<100;i++) {
 if((await b.query('select cardinality(pg_blocking_pids($1))>0 blocked',[holdPid])).rows[0].blocked){insertWait=true;break;}
 await new Promise(resolve=>setTimeout(resolve,30));
}
assert.equal(insertWait,true,'hold must wait for approval insert');
await a.query('commit'); await insertActivation;
await assert.rejects(a.query("insert into public.invoice_approvals values('00000000-0000-0000-0000-000000000003','pending')"),/invoice_retired/);
console.log('PASS: existing and newly inserted approval rows serialize with hold; other access paths remain unsafe');
await Promise.all(clients.map(c=>c.end()));
