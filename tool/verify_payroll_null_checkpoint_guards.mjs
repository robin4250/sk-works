// Disposable synthetic PGlite only. No real checkpoint input or network.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const temporary=await fs.mkdtemp(path.join(os.tmpdir(),'sko-payroll-code-guard-'));
const signature='private.refresh_automatic_payroll_internal(uuid,uuid,date)';
try {
 await setupPayrollScopeFixture(db);
 for(const file of ['20261009171504_payroll_refresh_scope_order.sql','20261009151946_company_payroll_rate_registry.sql','20261010030208_connect_payroll_tax_calculation.sql','20261013175452_payroll_unit_conditions.sql','20261014033249_payroll_fixed_deduction_overrides.sql']) await db.exec(await fs.readFile('supabase/migrations/'+file,'utf8'));
 // Synthetic explicit owner-only ACL mirrors the reviewed metadata shape.
 await db.exec(`revoke all on function ${signature} from public,anon,authenticated;grant execute on function ${signature} to postgres`);
 const checkpoint=(await db.query(`select 1 checkpoint_schema,p.oid::text oid,pg_get_function_identity_arguments(p.oid) identity_arguments,pg_get_functiondef(p.oid) definition,md5(p.prosrc) source_md5,pg_get_userbyid(p.proowner) owner,p.proacl::text acl,p.proconfig,p.prosecdef,p.provolatile,p.proparallel,p.proisstrict,p.proleakproof,l.lanname language,pg_get_function_result(p.oid) result_type from pg_proc p join pg_language l on l.oid=p.prolang where p.oid=$1::regprocedure`,[signature])).rows[0];
 checkpoint.signature=signature;checkpoint.definition_sha256=crypto.createHash('sha256').update(checkpoint.definition).digest('hex');
 const triggers=(await db.query(`select t.oid::text oid,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid,true) definition,n.nspname function_schema,p.proname function_name,md5(p.prosrc) function_source_md5 from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace where t.tgrelid='public.payroll_statements'::regclass and not t.tgisinternal order by t.oid`)).rows;
 const plainTriggers=(await db.query(`select t.oid::text oid,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid,false) definition,n.nspname function_schema,p.proname function_name,md5(p.prosrc) function_source_md5 from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace where t.tgrelid='public.payroll_statements'::regclass and not t.tgisinternal order by t.oid`)).rows;
 assert.ok(triggers.some((t,i)=>t.definition!==plainTriggers[i].definition),'regression must exercise a meaningful pretty/plain definition difference');
 assert.equal((await db.query('select count(*)::int n from pg_event_trigger')).rows[0].n,0);await fs.writeFile(path.join(temporary,'events.json'),'[]');
 await fs.writeFile(path.join(temporary,'checkpoint.json'),JSON.stringify(checkpoint));await fs.writeFile(path.join(temporary,'triggers.json'),JSON.stringify(triggers));
 execFileSync('python3',['tool/payroll_null_category_checkpoint.py','--checkpoint',path.join(temporary,'checkpoint.json'),'--triggers',path.join(temporary,'triggers.json'),'--event-triggers',path.join(temporary,'events.json'),'--output',path.join(temporary,'generated')],{stdio:'pipe'});
 const forward=await fs.readFile(path.join(temporary,'generated/guarded_forward.sql.review-only'),'utf8');const restore=await fs.readFile(path.join(temporary,'generated/guarded_restore.sql.review-only'),'utf8');
 const definition=async()=>(await db.query('select pg_get_functiondef($1::regprocedure) d',[signature])).rows[0].d;
 const before=await definition();
 await fs.writeFile(path.join(temporary,'plain-triggers.json'),JSON.stringify(plainTriggers));
 execFileSync('python3',['tool/payroll_null_category_checkpoint.py','--checkpoint',path.join(temporary,'checkpoint.json'),'--triggers',path.join(temporary,'plain-triggers.json'),'--event-triggers',path.join(temporary,'events.json'),'--output',path.join(temporary,'plain-generated')],{stdio:'pipe'});
 await assert.rejects(db.exec(await fs.readFile(path.join(temporary,'plain-generated/guarded_forward.sql.review-only'),'utf8')),/trigger checkpoint mismatch/);await db.exec('rollback');assert.equal(await definition(),before,'plain checkpoint must not pass pretty guard');
 await db.exec(forward);assert.equal(await definition(),before.replace('category:=a.work_category;',"category:=coalesce(a.work_category,'day');"));
 await db.exec(restore);assert.equal(await definition(),before);
 await assert.rejects(db.exec(restore),/checkpoint restore before mismatch/);await db.exec('rollback');assert.equal(await definition(),before);
 await db.exec(forward);
 await db.exec(`create or replace function ${signature.replace('(uuid,uuid,date)','(cid uuid,wid uuid,day date)')} returns void language plpgsql security definer set search_path='' as $$begin return;end$$`);
 const unknown=await definition();await assert.rejects(db.exec(restore),/checkpoint restore before mismatch/);await db.exec('rollback');assert.equal(await definition(),unknown,'unknown later source must remain untouched');
 await db.exec(before);
 const firstTrigger=triggers[0];await db.exec(`alter table public.payroll_statements disable trigger "${firstTrigger.tgname.replaceAll('"','""')}"`);
 await assert.rejects(db.exec(forward),/trigger checkpoint mismatch/);await db.exec('rollback');assert.equal(await definition(),before,'trigger drift must block replacement');
 await db.exec(`alter table public.payroll_statements enable trigger "${firstTrigger.tgname.replaceAll('"','""')}"`);
 await db.exec("create function public.synthetic_event_guard() returns event_trigger language plpgsql as $$begin return;end$$;create event trigger synthetic_event_drift on sql_drop execute function public.synthetic_event_guard()");
 await assert.rejects(db.exec(forward),/event trigger checkpoint mismatch/);await db.exec('rollback');assert.equal(await definition(),before,'event drift must block replacement');
 console.log('PASS synthetic exact forward/restore, repeated restore refusal, unknown later body refusal, trigger pretty/plain mismatch refusal, trigger drift and empty-baseline event drift refusal; no database URL or real checkpoint used');
} catch(error) { console.error(error.message);process.exitCode=1; } finally {await db.close();await fs.rm(temporary,{recursive:true,force:true});}
