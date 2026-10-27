import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
let db;
if(process.argv.includes('--native')) {const pg=await import(pathToFileURL(path.resolve(process.argv[4])).href);const Client=pg.Client??pg.default.Client;const c=new Client({connectionString:process.env.DATABASE_URL});await c.connect();db={exec:s=>c.query(s),query:(s,p)=>c.query(s,p),close:()=>c.end()};}
else {const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[3])).href);db=new PGlite();}
await db.exec(`create role anon; create role authenticated; create role service_role; create schema private; create schema auth;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create function private.require_reauthentication_session() returns uuid language sql stable as $$select nullif(current_setting('test.sid',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql stable as $$select coalesce(nullif(current_setting('test.allowed',true),'')::boolean,false)$$;
 create function private.has_company_feature(c uuid,f text) returns boolean language sql stable as $$select coalesce(nullif(current_setting('test.manage',true),'')::boolean,false)$$;
 create table private.master_admins(user_id uuid primary key,enabled boolean);
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.member_feature_permissions(company_id uuid,user_id uuid,can_manage_invoices boolean);
 create table public.invoices(id uuid primary key,company_id uuid,snapshot jsonb);
 insert into private.master_admins values('00000000-0000-0000-0000-000000000003',true);
 insert into public.company_members values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','owner');
 insert into public.invoices values('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','{"days":5}');
 select set_config('test.uid','00000000-0000-0000-0000-000000000003',false),set_config('test.sid','00000000-0000-0000-0000-000000000004',false),set_config('test.allowed','true',false),set_config('test.manage','true',false);`);
await db.exec(await readFile(process.argv[2]+'/owner-preview.sql.review-only','utf8'));
const id='00000000-0000-0000-0000-000000000001';
const read=()=>db.query('select invoice_owner_preview_candidate.read($1) v',[id]);
await assert.rejects(read(),/preview_disabled/);
await db.exec('update invoice_owner_preview_candidate.settings set enabled=true');
await assert.rejects(read(),/preview_dependency_unavailable/);
await db.exec(`create schema invoice_correction_preview_private; create table invoice_correction_preview_private.fixture(v jsonb);
 create function invoice_correction_preview_private.preview(uuid) returns jsonb language sql as $$select v from invoice_correction_preview_private.fixture$$;`);
const proposal={original_invoice_id:id,original_invoice_fingerprint:'a'.repeat(64),source_fingerprint:'b'.repeat(64),calculation_blocked:false,proposed_snapshot:{sites:[{days:6},{days:1}]},subtotal:700,tax:70,welfare:0,grand_total:770};
const set=async p=>{await db.exec('delete from invoice_correction_preview_private.fixture');await db.query('insert into invoice_correction_preview_private.fixture values($1::jsonb)',[JSON.stringify(p)]);};
await set(proposal);const old=(await db.query('select snapshot from invoices')).rows[0].snapshot;
const result=(await read()).rows[0].v;assert.equal(result.status,'unissued_reference_only');assert.equal(result.grand_total,770);
for(const bad of [{...proposal,calculation_blocked:true},{...proposal,proposed_snapshot:{company_seal_snapshot:{}}},{...proposal,original_invoice_id:'different'},{...proposal,grand_total:null}]){await set(bad);await assert.rejects(read(),/preview_invalid/);}await set(proposal);
for(const [statement,error] of [["update private.master_admins set enabled=false",/preview_unavailable/],["select set_config('test.sid','',false)",/preview_unavailable/],["select set_config('test.manage','false',false)",/preview_unavailable/]]) {
 await db.exec(statement);await assert.rejects(read(),error);
 await db.exec("update private.master_admins set enabled=true;select set_config('test.sid','00000000-0000-0000-0000-000000000004',false),set_config('test.manage','true',false)");
}
assert.deepEqual((await db.query('select snapshot from invoices')).rows[0].snapshot,old);
for(const role of ['anon','authenticated','service_role']) assert.equal((await db.query("select has_function_privilege($1,'invoice_owner_preview_candidate.read(uuid)','EXECUTE') f",[role])).rows[0].f,false);
console.log('PASS owner-only disabled non-public provisional preview; auth fixture simulated');await db.close();
