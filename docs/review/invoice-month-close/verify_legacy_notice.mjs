import {readFile,writeFile,unlink} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const base=await readFile(process.env.SKO_LEGACY_TEST,'utf8');
const guard=await readFile(process.env.SKO_APPROVAL_GUARD_SQL,'utf8');
const replacements=await readFile(process.env.SKO_LEGACY_GUARD_SQL,'utf8');
const bodies=await readFile(process.env.SKO_NOTIFY_TRIGGER,'utf8');
const inject=`
await db.query('create role anon;create role authenticated;create role service_role;create schema invoice_month_close_candidate');
await db.query(${JSON.stringify(guard)});await db.query(${JSON.stringify(replacements)});
const insertManual=()=>db.query("insert into public.invoices(id,company_id,customer_id,billing_period_start,billing_period_end,automatic_calculation,snapshot) values($1,$2,$3,'2020-01-01','2020-01-31',false,$4)",[newInvoice,company,customer,JSON.stringify({days:7})]);
await insertManual();assert.equal((await db.query('select count(*)::int n from public.app_notifications where action_id=$1',[newInvoice])).rows[0].n,1);
await db.query('rollback to savepoint fixture_old');
// Reinstall after savepoint rollback; DDL itself is test-only and rolled back.
await db.query('create role anon;create role authenticated;create role service_role;create schema invoice_month_close_candidate');
await db.query(${JSON.stringify(guard)});await db.query(${JSON.stringify(replacements)});
await db.query('update invoice_month_close_candidate.approval_guard_settings set enabled=true');
await insertManual();assert.equal((await db.query('select count(*)::int n from public.invoice_approvals where invoice_id=$1',[newInvoice])).rows[0].n,1);
assert.equal((await db.query('select count(*)::int n from public.app_notifications where action_id=$1',[newInvoice])).rows[0].n,0);
assert.equal((await db.query('select public.enqueue_due_invoice_approval_notifications() n')).rows[0].n,0);
await db.query('rollback to savepoint fixture_old');
assert.deepEqual((await db.query('select * from public.invoices where id=$1',[oldInvoice])).rows[0],before);
assert.equal((await db.query('select count(*)::int n from public.app_notifications')).rows[0].n,beforeNotifications);
console.log(JSON.stringify({fixture_legacy_off_unchanged:true,fixture_legacy_on_suppressed:true,fixture_due_on_suppressed:true,pending_rows_retained:true,original_unchanged:true}));
`;
const marker='console.log(JSON.stringify({fixture_production_trigger_bodies_match:true';assert.equal(base.split(marker).length,2);
const generated=resolve(process.env.SKO_TEMP_DIR,'verify_legacy_notice.generated.mjs');
try{
 // Keep import.meta.url's adjacent body file expectation; write exact fixture data.
 await writeFile(resolve(process.env.SKO_TEMP_DIR,'integration_trigger_bodies.sql.review-only'),bodies);
 await writeFile(generated,base.replace(marker,()=>inject+marker));
 const result=spawnSync(process.execPath,[generated],{stdio:'inherit',env:process.env});process.exitCode=result.status??1;
}finally{await unlink(generated).catch(()=>{});await unlink(resolve(process.env.SKO_TEMP_DIR,'integration_trigger_bodies.sql.review-only')).catch(()=>{});}
