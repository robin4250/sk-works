import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
let db;
if (process.argv.includes('--native')) {
 const pg = await import(pathToFileURL(path.resolve(process.argv[4])).href);
 const Client = pg.Client ?? pg.default.Client;
 const client = new Client({connectionString:process.env.DATABASE_URL});
 await client.connect();
 db={exec:sql=>client.query(sql),query:(sql,args)=>client.query(sql,args),close:()=>client.end()};
} else {
 const { PGlite } = await import(pathToFileURL(path.resolve(process.argv[3])).href);
 db=new PGlite();
}
await db.exec(`create role anon; create role authenticated; create role service_role;
 create schema private; create schema auth; create function auth.uid() returns uuid language sql stable as $$select '00000000-0000-0000-0000-000000000099'::uuid$$; create table public.companies(id uuid);
 create table public.invoices(id uuid primary key, snapshot text);
 create table public.invoice_approvals(invoice_id uuid,status text);
 alter table public.invoices enable row level security;
 grant select on public.invoices to authenticated;
 create policy old_permissive on public.invoices for select to authenticated using(true);
 insert into public.invoices values('00000000-0000-0000-0000-000000000001','old');`);
await db.exec(await readFile(process.argv[2]+'/legacy-retirement.sql.review-only','utf8'));
await db.exec(await readFile(process.argv[2]+'/approval-definers.fixture.sql','utf8'));
await db.exec(await readFile(process.argv[2]+'/trade-source-current.fixture.sql','utf8'));
await db.exec(`revoke all on function public.invoice_approval_history(uuid),public.invoice_approval_status_rows(uuid),public.invoice_approval_status_rows_v2(uuid) from public;
 grant execute on function public.invoice_approval_history(uuid),public.invoice_approval_status_rows(uuid),public.invoice_approval_status_rows_v2(uuid) to authenticated,service_role;
 revoke all on function private.trade_document_source(text,uuid,text) from public;`);
const sigs=['public.invoice_approval_history(uuid)','public.invoice_approval_status_rows(uuid)','public.invoice_approval_status_rows_v2(uuid)','private.trade_document_source(text,uuid,text)'];
const metadata=async()=> (await db.query(`select p.oid::int oid, p.proacl::text acl,p.proconfig,p.provolatile,p.prosecdef,md5(p.prosrc) hash from pg_proc p where p.oid = any($1::regprocedure[]) order by oid`,[sigs])).rows;
const before=await metadata();
const patch=await readFile(process.argv[2]+'/definer-hold.sql.review-only','utf8');
// A drift at the last target must roll back all previous patches and the helper.
await db.exec('grant execute on function private.trade_document_source(text,uuid,text) to authenticated');
await assert.rejects(db.exec(patch),/invoice_hold_definition_or_acl_drift/);
await db.exec('rollback');
assert.equal((await db.query("select to_regprocedure('invoice_retirement_guard_candidate.require_visible(uuid)')::text r")).rows[0].r,null);
await db.exec('revoke execute on function private.trade_document_source(text,uuid,text) from authenticated');
assert.deepEqual(await metadata(),before);
await db.exec(patch);
const after=await metadata();
assert.equal(after.length,4);
for(let i=0;i<4;i++) {
  assert.equal(after[i].oid,before[i].oid);assert.equal(after[i].acl,before[i].acl);
  assert.deepEqual(after[i].proconfig,before[i].proconfig);assert.equal(after[i].provolatile,before[i].provolatile);
  assert.equal(after[i].prosecdef,before[i].prosecdef);assert.notEqual(after[i].hash,before[i].hash);
}
await db.exec("select invoice_retirement_guard_candidate.activate('00000000-0000-0000-0000-000000000001')");
for(const sql of [
 "select * from public.invoice_approval_history('00000000-0000-0000-0000-000000000001')",
 "select * from public.invoice_approval_status_rows('00000000-0000-0000-0000-000000000001')",
 "select * from public.invoice_approval_status_rows_v2('00000000-0000-0000-0000-000000000001')",
 "select private.trade_document_source('invoice','00000000-0000-0000-0000-000000000001','x')",
]) await assert.rejects(db.exec(sql),/invoice_unavailable/);
console.log('PASS exact-catalog partial definer guards preserve OID/ACL/config and deny held ID; other routes remain unguarded');
await db.close();
