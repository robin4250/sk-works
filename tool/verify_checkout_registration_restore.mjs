// Focused disposable PG17 proof for exact product head1f16501. No production.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const expectedSources={
  "docs/candidates/checkout_report_registration.sql.review-only": "790330bc262b5c9b71c044db89f9500c19dbfb4b8c52fa8b375e91d3ebda3e67",
  "docs/candidates/checkout_report_registration_validators.sql.review-only": "029634ed18864cc3440b961f731bb130459b5e8c3ceda9270bcc54e96c2a1f40",
  "docs/candidates/checkout_report_registration_reminders.sql.review-only": "577d03e9109044c030cf71f7e564e8a997a081601d6a990e80604f493fb8fa37",
  "docs/candidates/checkout_report_registration_schedule.sql.review-only": "655b3bf9538b4ffa93a1dd86142a3ddb14852e64016568c5581429bf4fbeb7bd"
};
for(const [file,hash]of Object.entries(expectedSources))assert.equal(createHash('sha256').update(await readFile(file)).digest('hex'),hash,'Exact Native-tested product source: '+file);
const original=await readFile('tool/verify_checkout_registration.mjs','utf8');
const marker='\n} finally {await db.end();}';
assert.equal(original.split(marker).length,2,'Unique end of disposable original suite');
const extension=String.raw`

 // Explicit rollback proof runs only after the existing disposable fixture and
 // its used-state cases have passed. That suite hard-requires localhost, the
 // exact fixture-only database/password, CI linux and absence of production env.
 const restore=await readFile('docs/candidates/checkout_report_registration_restore_unused.sql.review-only','utf8');
 // Synthetic cron catalog only: no extension installation or scheduling.
 await db.query("create schema cron;create table cron.job(jobid bigint primary key,command text);create function cron.unschedule(bigint) returns boolean language sql as $$select false$$");

 const protectedState=async()=>{
  const rows=(await db.query("select n.nspname schema_name,c.relname table_name from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','auth') and c.relkind='r' order by n.nspname,c.relname")).rows;
  const tables={};
  for(const row of rows){
   const quote=v=>'"'+v.replaceAll('"','""')+'"';
   const qualified=quote(row.schema_name)+'.'+quote(row.table_name);
   tables[qualified]=await q("select md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,'[]')) v from "+qualified+' t');
  }
  const source=await q("select md5(coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'source',p.prosrc,'owner',p.proowner,'acl',p.proacl::text,'config',p.proconfig,'definer',p.prosecdef,'volatility',p.provolatile) order by p.oid::regprocedure::text)::text,'[]')) v from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname not in('pg_catalog','information_schema','checkout_report_registration_private') and not(n.nspname='public' and p.proname in('read_pending_checkout_report_registration','read_checkout_report_registration_notification'))");
  return {tables,source};
 };
 const beforeRestore=await protectedState();
 // A used deployment must refuse without dropping objects or touching data.
 await assert.rejects(()=>db.query(restore),/rollout_or_delivery_used_stop_unused_rollback/);
 await db.query('rollback');
 assert.ok(await q("select to_regnamespace('checkout_report_registration_private') is not null v"));
 assert.deepEqual(await protectedState(),beforeRestore,'Used-state refusal preserves every application/Auth row and existing source');
 // Clear ONLY newly created private fixture state to model the unused OFF
 // installation. Do not delete notifications, reports, payroll or Auth rows.
 await db.query('delete from checkout_report_registration_private.daily_deliveries');
 await db.query('delete from checkout_report_registration_private.rollout');
 await db.query("insert into cron.job values(1,'select checkout_report_registration_private.run_daily_step()')");
 await assert.rejects(()=>db.query(restore),/cron_job_present_stop_unused_rollback/);await db.query('rollback');
 assert.ok(await q("select to_regnamespace('checkout_report_registration_private') is not null v"));
 assert.deepEqual(await protectedState(),beforeRestore,'Cron-use refusal preserves protected application/Auth data and existing source');
 await db.query('delete from cron.job where jobid=1');

 await db.query(restore);
 assert.equal(await q("select to_regnamespace('checkout_report_registration_private') is null v"),true,'Exact unused-OFF rollback removes only its new namespace');
 assert.equal(await q("select to_regprocedure('public.read_pending_checkout_report_registration()') is null v"),true);
 assert.equal(await q("select to_regprocedure('public.read_checkout_report_registration_notification(uuid)') is null v"),true);
 assert.deepEqual(await protectedState(),beforeRestore,'RESTRICT rollback leaves all application/Auth rows and preexisting functions unchanged');
 console.log(JSON.stringify({pass:true,used_restore_refused:true,cron_use_restore_refused:true,unused_off_restore_applied:true,application_auth_rows_unchanged:true,preexisting_routines_unchanged:true,cascade_used:false,real_gotrue:false,production_changed:false}));

`;
const temp=await mkdtemp(join(tmpdir(),'checkout-registration-restore-proof-'));
try{
 const file=join(temp,'proof.mjs');await writeFile(file,original.replace(marker,()=>extension+marker));
 const result=spawnSync(process.execPath,[file,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally{await rm(temp,{recursive:true,force:true});}
