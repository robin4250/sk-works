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
 insert into public.invoices values('00000000-0000-0000-0000-000000000001','old');
 insert into public.invoice_approvals values('00000000-0000-0000-0000-000000000001','approved');`);
await c.query(await readFile(process.argv[2],'utf8'));
await a.query('begin');
await a.query('select * from public.invoice_approvals for update');
const pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
const blockedUpdate=b.query("update public.invoice_approvals set status='pending'");
let blocked=false;
for(let i=0;i<100;i++) {
 if((await c.query('select cardinality(pg_blocking_pids($1))>0 blocked',[pid])).rows[0].blocked){blocked=true;break;}
 await new Promise(resolve=>setTimeout(resolve,30));
}
assert.equal(blocked,true,'approval update must really wait on the other transaction');
await c.query("insert into invoice_retirement_guard_candidate.holds values('00000000-0000-0000-0000-000000000001')");
await a.query('commit');
await blockedUpdate;
assert.equal((await c.query('select status from public.invoice_approvals')).rows[0].status,'pending');
console.log('PASS unsafe race reproduced: statement snapshot may permit stale old approval mutation; do not deploy');
await Promise.all(clients.map(c=>c.end()));
