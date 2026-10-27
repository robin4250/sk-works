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
// A new uncommitted approval has no existing row for the activator to lock.
// This deliberate counterexample keeps the entire candidate unpublishable.
await c.query("insert into public.invoices values('00000000-0000-0000-0000-000000000003','old3')");
await a.query('begin');
await a.query("insert into public.invoice_approvals values('00000000-0000-0000-0000-000000000003','pending')");
await c.query("select invoice_retirement_guard_candidate.activate('00000000-0000-0000-0000-000000000003')");
await a.query('commit');
assert.equal((await c.query("select count(*)::int n from public.invoice_approvals where invoice_id='00000000-0000-0000-0000-000000000003'")).rows[0].n,1);
console.log('PASS existing rows serialize; concurrent new approval INSERT remains unsafe: NO DEPLOY');
await Promise.all(clients.map(c=>c.end()));
