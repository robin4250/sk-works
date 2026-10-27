import { pathToFileURL } from 'node:url';
import path from 'node:path';
const { PGlite } = await import(pathToFileURL(path.resolve(process.argv[3])).href);
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const db = new PGlite();
await db.exec(`
 create role anon; create role authenticated; create role service_role;
 create table public.invoices(id uuid primary key, snapshot text);
 create table public.invoice_approvals(invoice_id uuid, status text);
 alter table public.invoices enable row level security;
 grant select on public.invoices to authenticated;
 create policy old_permissive on public.invoices for select to authenticated using(true);
 create function public.synthetic_definer_invoice(p_id uuid) returns text language sql security definer set search_path='' as $$select snapshot from public.invoices where id=p_id$$;
 revoke all on function public.synthetic_definer_invoice(uuid) from public;
 grant execute on function public.synthetic_definer_invoice(uuid) to authenticated;
 insert into public.invoices values('00000000-0000-0000-0000-000000000001','old'),('00000000-0000-0000-0000-000000000002','unrelated');
 insert into public.invoice_approvals values('00000000-0000-0000-0000-000000000001','approved'),('00000000-0000-0000-0000-000000000002','pending');
`);
await db.exec(await readFile(process.argv[2], 'utf8'));
await db.exec(`select invoice_retirement_guard_candidate.activate('00000000-0000-0000-0000-000000000001'); set role authenticated`);
assert.deepEqual((await db.query('select snapshot from public.invoices order by snapshot')).rows.map(r=>r.snapshot),['unrelated']);
// This intentional leak proves the RLS-only prototype is not deployable.
assert.equal((await db.query("select public.synthetic_definer_invoice('00000000-0000-0000-0000-000000000001') v")).rows[0].v,'old');
await db.exec('reset role');
for(const sql of [
 "update public.invoice_approvals set status='pending' where invoice_id='00000000-0000-0000-0000-000000000001'",
 "delete from public.invoice_approvals where invoice_id='00000000-0000-0000-0000-000000000001'",
 "insert into public.invoice_approvals values('00000000-0000-0000-0000-000000000001','pending')",
]) await assert.rejects(db.exec(sql),/invoice_retired/);
await db.exec("update public.invoice_approvals set status='approved' where invoice_id='00000000-0000-0000-0000-000000000002'");
assert.equal((await db.query("select status from public.invoice_approvals where invoice_id='00000000-0000-0000-0000-000000000001'")).rows[0].status,'approved');
console.log('PASS synthetic restrictive select and approval write hold; SECDEF reads and cached PDFs remain unprotected');
await db.close();
