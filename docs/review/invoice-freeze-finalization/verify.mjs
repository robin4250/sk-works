import assert from 'node:assert/strict';
import {readFile,writeFile,unlink} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
const here=fileURLToPath(new URL('.',import.meta.url));
const root=resolve(here,'../explicit-finalization-candidate');
const path=resolve(root,'verify_ordinary_explicit_finalization.mjs');
const original=await readFile(path,'utf8');
const patched=await readFile(resolve(here,'patched.sql.review-only'),'utf8');
const installGuard=await readFile(resolve(here,'install.guarded.sql.review-only'),'utf8');
const restoreGuard=await readFile(resolve(here,'restore-unused.guarded.sql.review-only'),'utf8');
const guardFixture=JSON.parse(await readFile(resolve(here,'before.fixture.json'),'utf8')); 
const marker=" phase='ordinary-actual-producer-final-save';";
assert.equal(original.split(marker).length,2);
const payload=`
 phase='protected-invoice-synthetic-regression';
 await exec('create table if not exists public.invoice_approvals (invoice_id uuid,status text)');
 await client.query("insert into invoices(id,company_id,customer_id,billing_period_start,billing_period_end,status,automatic_calculation,calculation_blocked,snapshot) values($1,$2,$3,'2026-10-01','2026-10-31','draft',true,false,jsonb_build_object('sites',jsonb_build_array(jsonb_build_object('site_id',$4::text))))",[id(9905),A,customer,SITE]);
 await client.query('update invoices set invoice_seal_frozen=true where id=$1',[id(9905)]);
 await q('select explicit_report_finalization_private.assert_invoice($1,$2,$3,$4::date,$5::date) is null v',[rid,A,customer,'2026-10-01','2026-10-31']);

 await exec('create table if not exists public.invoice_detail_lines(id uuid primary key)');
 const guardFixture=${JSON.stringify(guardFixture)};
 const assertAttrs=await q("select md5((to_jsonb(p)-'prosrc')::text) v from pg_proc p where oid='explicit_report_finalization_private.assert_invoice(uuid,uuid,uuid,date,date)'::regprocedure");
 const refreshBody=await q("select md5(p.prosrc) v from pg_proc p where oid='private.refresh_automatic_invoice(uuid,uuid,date)'::regprocedure");
 const refreshAttrs=await q("select md5((to_jsonb(p)-'prosrc')::text) v from pg_proc p where oid='private.refresh_automatic_invoice(uuid,uuid,date)'::regprocedure");
 const historyValues={};for(const h of guardFixture.history){const row=(await client.query("select count(*)::int n,md5(coalesce(string_agg(h,'' order by h),'')) h from(select md5(to_jsonb(x)::text) h from explicit_report_finalization_private."+h.name+" x)t")).rows[0];historyValues[h.name]=row;}
 const adaptGuard=source=>{source=source.replaceAll(guardFixture.definitions.assert_invoice.attrs,assertAttrs).replaceAll(guardFixture.definitions.refresh_automatic_invoice.body,refreshBody).replaceAll(guardFixture.definitions.refresh_automatic_invoice.attrs,refreshAttrs);for(const h of guardFixture.history){const old="n="+h.n+" and h='"+h.h+"'";const next="n="+historyValues[h.name].n+" and h='"+historyValues[h.name].h+"'";assert.ok(source.includes(old));source=source.replace(old,next);}return source;};
 const guardedInstall=adaptGuard(${JSON.stringify(installGuard)}),guardedRestore=adaptGuard(${JSON.stringify(restoreGuard)});
 const baseSnapshot=await snapshot();await exec(guardedInstall);eq(await snapshot(),baseSnapshot,'Guarded install leaves all business and audit rows unchanged');
 await reject(()=>exec(guardedInstall),/invoice_guard_assert_drift/);await exec('rollback');
 await exec(guardedRestore);eq(await snapshot(),baseSnapshot,'Unused guarded restore preserves all rows');
 await reject(()=>exec(guardedRestore),/invoice_guard_assert_drift/);await exec('rollback');
 await exec(guardedInstall);
 const revBefore=await q('select revision v from explicit_report_finalization_private.states where report_id=$1',[rid]);
 await client.query('update explicit_report_finalization_private.states set revision=revision+1 where report_id=$1',[rid]);
 await reject(()=>exec(guardedRestore),/invoice_guard_history_changed/);await exec('rollback');
 await client.query('update explicit_report_finalization_private.states set revision=$2 where report_id=$1',[rid,revBefore]);
 eq(await snapshot(),baseSnapshot,'History-drift refusal preserves the original after fixture restoration');

 await exec("create function public.fixture_freeze_invoice_update() returns trigger language plpgsql as $fixture$begin if old.invoice_seal_frozen or old.approval_finalized_at is not null or exists(select 1 from public.invoice_approvals a where a.invoice_id=old.id and a.status='approved') then return null;end if;return new;end$fixture$;create trigger fixture_freeze_invoice before update on public.invoices for each row execute function public.fixture_freeze_invoice_update()");
 for(const kind of ['seal','approval_finalized','approved']){
   await exec('drop trigger fixture_freeze_invoice on public.invoices');
   await client.query('delete from public.invoice_approvals where invoice_id=$1',[id(9905)]);
   await client.query('update invoices set invoice_seal_frozen=false,approval_finalized_at=null where id=$1',[id(9905)]);
   if(kind==='seal')await client.query('update invoices set invoice_seal_frozen=true where id=$1',[id(9905)]);
   if(kind==='approval_finalized')await client.query('update invoices set approval_finalized_at=clock_timestamp() where id=$1',[id(9905)]);
   if(kind==='approved')await client.query("insert into public.invoice_approvals(invoice_id,status) values($1,'approved')",[id(9905)]);
   await exec('create trigger fixture_freeze_invoice before update on public.invoices for each row execute function public.fixture_freeze_invoice_update()');
   const protectedBefore=await snapshot();
   await reject(finish,/explicit_report_finalized_invoice_protected/);
   eq(await snapshot(),protectedBefore,'Protected invoice '+kind+' rolls back report, signatures, payroll and invoice');
 }
 await exec('drop trigger fixture_freeze_invoice on public.invoices;drop function public.fixture_freeze_invoice_update()');
 await client.query('delete from public.invoice_approvals where invoice_id=$1',[id(9905)]);
 await client.query('delete from public.invoices where id=$1',[id(9905)]);
`;
const output=resolve(root,'verify_invoice_freeze_guard.generated.mjs');
try {await writeFile(output,original.replace(marker,payload+marker));const r=spawnSync(process.execPath,[output,...process.argv.slice(2)],{stdio:'inherit',env:process.env});process.exitCode=r.status??1;}finally{await unlink(output).catch(()=>{});}
