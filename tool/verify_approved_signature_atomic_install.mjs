// Native PG17 atomic code-install proof. Synthetic auth/provider and explicit-finalization surroundings.
// No product UI changes, no production connection accepted.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const atomic=await readFile('docs/review/approved-signature-atomic-install/atomic-core.sql.review-only','utf8');
const old=await readFile('docs/review/approved-edit-allowance-reset/approved-edit-allowance-reset.sql.review-only','utf8');
const start=atomic.indexOf('create function shared_report_edit_private.resume_original_signatures');
assert.ok(start>0);
assert.equal(atomic.slice(atomic.indexOf('set local lock_timeout'),start),old.slice(old.indexOf('set local lock_timeout'),old.lastIndexOf('commit;')),'The four-CASE source is reused byte-for-byte');
const core=atomic.slice(start,atomic.lastIndexOf('commit;'));
assert.equal(createHash('sha256').update(core).digest('hex'),'572c3cdd0bf6abf4218144f82b5befea72f1006dfd72e8978dddb612bf75c26d','Exact canonical recovery source from PR1636 head209fee');
let original=await readFile('tool/verify_approved_edit_allowance_reset.mjs','utf8');
const atomicMarker=" await exec(await readFile('docs/review/approved-edit-allowance-reset/approved-edit-allowance-reset.sql.review-only','utf8'));";
assert.equal(original.split(atomicMarker).length,2,'Exact future-start install anchor');
const atomicInstall=String.raw`
 await exec('create schema if not exists explicit_report_finalization_private;create table if not exists explicit_report_finalization_private.events(report_id uuid,kind text);create table if not exists explicit_report_finalization_private.management_reports(report_id uuid);');
 phase='atomic-future-start-and-existing-session-recovery';
 const atomicBefore=await q("select jsonb_build_object('reports',(select jsonb_agg(to_jsonb(x) order by id) from daily_reports x),'workers',(select jsonb_agg(to_jsonb(x) order by report_id,worker_id) from daily_report_workers x),'requests',(select jsonb_agg(to_jsonb(x) order by id) from daily_report_edit_requests x),'sessions',(select jsonb_agg(to_jsonb(x) order by report_id) from shared_report_edit_private.sessions x),'payroll',(select jsonb_agg(to_jsonb(x) order by id) from payroll_statements x)) v");
 const atomicWriterAttrs=await q("select to_jsonb(p)-'prosrc' v from pg_proc p where oid='public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'::regprocedure");
 const atomicCore=await readFile('docs/review/approved-signature-atomic-install/atomic-core.sql.review-only','utf8');
 await exec('create role fixture_atomic_unknown_executor;alter default privileges for role postgres in schema public grant execute on functions to fixture_atomic_unknown_executor');
 let atomicFailed;
 try{await exec(atomicCore);}catch(error){atomicFailed=error;}
 await exec('rollback');
 assert.ok(atomicFailed,'Unknown post-create privilege aborts the complete writer+RPC install');
 assert.match(atomicFailed.message,/new_function_attributes_differ/);
 eq(await q("select md5(prosrc) v from pg_proc where oid='public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'::regprocedure"),'bf537e2cac395236c2f8d3d245ffc639','Late RPC failure rolls the writer back to its exact old body');
 eq(await q("select to_jsonb(p)-'prosrc' v from pg_proc p where oid='public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'::regprocedure"),atomicWriterAttrs,'Late rollback preserves every old writer catalog attribute');
 eq(await q("select to_regprocedure('public.resume_approved_daily_report_signatures(uuid,uuid,timestamptz,text)') is null v"),true,'Late rollback leaves no half-installed new public RPC');
 await exec('alter default privileges for role postgres in schema public revoke execute on functions from fixture_atomic_unknown_executor');
 await exec(atomicCore);
 eq(await q("select md5(prosrc) v from pg_proc where oid='public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'::regprocedure"),'075b62ee12e02f4aeb04f6c20bbfd3d3','Future four-CASE fix and recovery install in one successful transaction');
 eq(await q("select jsonb_build_object('reports',(select jsonb_agg(to_jsonb(x) order by id) from daily_reports x),'workers',(select jsonb_agg(to_jsonb(x) order by report_id,worker_id) from daily_report_workers x),'requests',(select jsonb_agg(to_jsonb(x) order by id) from daily_report_edit_requests x),'sessions',(select jsonb_agg(to_jsonb(x) order by report_id) from shared_report_edit_private.sessions x),'payroll',(select jsonb_agg(to_jsonb(x) order by id) from payroll_statements x)) v"),atomicBefore,'Installing code does not repair or alter any historical business row');
 // Rehearse code-only restoration inside a disposable savepoint, then roll it
 // back. This is not an instruction to undo an online production correction.
 await exec('begin;savepoint unused_code_restore');
 await exec('drop function public.resume_approved_daily_report_signatures(uuid,uuid,timestamptz,text);drop function shared_report_edit_private.resume_original_signatures(uuid,uuid,timestamptz,text)');
 await exec(resetSource.function.definition);
 eq(await q("select md5(prosrc) v from pg_proc where oid='public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'::regprocedure"),'bf537e2cac395236c2f8d3d245ffc639','Unused source-only restoration recovers the original writer');
 await exec('rollback');
 eq(await q("select md5(prosrc) v from pg_proc where oid='public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'::regprocedure"),'075b62ee12e02f4aeb04f6c20bbfd3d3','Rehearsal rollback preserves the successful atomic candidate');
 console.log(JSON.stringify({pass:true,atomic_writer_and_resume:true,late_unknown_acl_full_rollback:true,original_writer_all_catalog_preserved:true,historical_rows_unchanged:true,unused_code_only_restore_rehearsed:true,production_changed:false}));
`;

original=original.replace(atomicMarker,()=>atomicInstall);
const folder=await mkdtemp(join(tmpdir(),'approved-signature-atomic-'));
try {
 const file=join(folder,'proof.mjs');await writeFile(file,original);
 const result=spawnSync(process.execPath,[file,...process.argv.slice(2)],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally{await rm(folder,{recursive:true,force:true});}
