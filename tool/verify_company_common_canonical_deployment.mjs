// Disposable synthetic fixture only. Never uses hosted project endpoints.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
if(process.env.SKO_COMMON_LEGACY_PRIVATE_FIXTURE)throw Error('synthetic deployment proof forbids private-rate input');
const base=fileURLToPath(new URL('../',import.meta.url));
const read=p=>fs.readFileSync(new URL(p,new URL('../',import.meta.url)),'utf8');
let db;const temp=fs.mkdtempSync(path.join(os.tmpdir(),'sko-canonical-deployment-fixture-'));
function prepare(args){const p=spawnSync('python3',[path.join(base,'tool/security/prepare_common_canonical_deployment_review.py'),...args],{encoding:'utf8'});assert.equal(p.status,0,p.stderr||p.stdout);}
try {
 if(process.argv[3]==='postgres') {
  const pg=(await import(process.argv[2])).default,url=new URL(process.env.SKO_COMMON_LEGACY_FIXTURE_URL??'');
  if(!['127.0.0.1','localhost'].includes(url.hostname)||url.pathname!=='/sko_common_legacy_fixture')throw Error('owned disposable loopback fixture required');
  const client=new pg.Client({connectionString:url.href});await client.connect();db={query:(...a)=>client.query(...a),exec:s=>client.query(s),close:()=>client.end()};
 } else {const {PGlite}=await import(process.argv[2]);db=new PGlite();}
 const version=Number((await db.query('show server_version_num')).rows[0].server_version_num);assert.ok(version>=170000&&version<180000,'PG17 fixture required');
 process.chdir(base);await setupPayrollScopeFixture(db);
 for(const p of ['20261009171504_payroll_refresh_scope_order.sql','20261009151946_company_payroll_rate_registry.sql','20261010030208_connect_payroll_tax_calculation.sql','20261013175452_payroll_unit_conditions.sql'])await db.exec(read('supabase/migrations/'+p));
 const cid='10000000-0000-0000-0000-000000000001';
 await db.exec(`reset role;create role service_role nologin;delete from public.attendance_entries;delete from public.payroll_statements;delete from public.payroll_adjustments;
 alter table public.companies add column if not exists default_welfare_rate numeric default 0,add column if not exists tax_rate numeric default 10,add column if not exists updated_at timestamptz;
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create function auth.jwt() returns jsonb language sql as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 alter table public.worker_payroll_settings add column if not exists allowance_name_2 text,add column if not exists allowance_2 numeric default 0,add column if not exists allowance_name_3 text,add column if not exists allowance_3 numeric default 0;`);
 const fixture=read('supabase/tests/company_allowance_identity_access_fixture.sql');
 await db.exec(fixture.slice(fixture.indexOf('create table public.company_rate_settings('),fixture.indexOf('create table public.payroll_statements')));
 await db.query('insert into public.company_rate_settings(company_id) values($1)',[cid]);
 for(const p of ['20260922020000_add_company_rate_settings_management.sql','20261003002700_add_attendance_allowance_display_units.sql','20261008043823_atomic_company_rate_and_allowance_units_save.sql','20261009201229_company_allowance_identity_lifecycle.sql'])await db.exec(read('supabase/migrations/'+p));
 for(const p of ['tool/staged_company_common_allowances.sql.review-only','docs/candidates/company_common_payroll_bridge_20261020.sql.review-only','docs/candidates/company_common_payroll_effective_20261020.sql.review-only'])await db.exec(read(p));
 const observerPath=path.join(temp,'observer.sql');prepare(['--observer-output',observerPath]);
 const observerSQL=fs.readFileSync(observerPath,'utf8');
 const observerBlock=observerSQL.slice(observerSQL.indexOf('do $sko_observe$'),observerSQL.indexOf("select current_setting('sko.canonical_observation')"));
 assert.ok(observerBlock.startsWith('do $sko_observe$')&&observerBlock.endsWith('\n'));
 async function observe(){await db.exec("begin isolation level repeatable read read only;set local search_path='';");try{await db.exec(observerBlock);const value=(await db.query("select current_setting('sko.canonical_observation')::jsonb v")).rows[0].v;await db.exec('commit');return value;}catch(error){await db.exec('rollback');throw error;}}
 const before=await observe();assert.equal(before.schema,1);assert.ok(Object.keys(before.routines).length>20);assert.ok(before.relations['public.payroll_statements']);
 assert.equal(before.impact.companies,2);assert.equal(before.impact.activated_companies,0);
 await db.exec('alter table public.payroll_audit rename to synthetic_missing_payroll_audit');
 await assert.rejects(observe(),/required canonical baseline relation or schema missing/);
 await db.exec('alter table public.synthetic_missing_payroll_audit rename to payroll_audit');
 assert.deepEqual(await observe(),before,'missing mandatory relation refuses; restoring fixture name leaves exact original inventory');
 const beforeFile=path.join(temp,'install-before.json'),installFile=path.join(temp,'install.sql');fs.writeFileSync(beforeFile,JSON.stringify(before));
 prepare(['--before',beforeFile,'--install-output',installFile]);const installer=fs.readFileSync(installFile,'utf8');
 assert.ok(!installer.includes(before.routines['payroll_unit_private.common_state(uuid,uuid,date)'].definition),'installer embeds original observation digest, not private original definitions');
 const originalName=(await db.query('select name from public.companies where id=$1',[cid])).rows[0].name;
 await db.query('update public.companies set name=$2 where id=$1',[cid,'Synthetic stale install']);const staleInstall=await observe();
 await assert.rejects(db.exec(installer),/canonical install original observation changed/);await db.exec('rollback');assert.deepEqual(await observe(),staleInstall,'stale before observation refuses before any DDL');
 await db.query('update public.companies set name=$2 where id=$1',[cid,originalName]);assert.deepEqual(await observe(),before);
 const badAfter=installer.replace('-- Begin post-install observation',"update public.companies set name='Synthetic after corruption';\n-- Begin post-install observation");
 assert.notEqual(badAfter,installer);await assert.rejects(db.exec(badAfter),/canonical install changed protected originals or object inventory/);await db.exec('rollback');assert.deepEqual(await observe(),before,'after guard failure rolls back original-row mutation and all three units');
 await db.exec(installer);const after=await observe();
 function restoreSQL(old,installed,label){const b=path.join(temp,label+'-before.json'),a=path.join(temp,label+'-after.json'),s=path.join(temp,label+'-restore.sql');fs.writeFileSync(b,JSON.stringify(old));fs.writeFileSync(a,JSON.stringify(installed));prepare(['--before',b,'--after',a,'--restore-output',s]);return fs.readFileSync(s,'utf8');}
 const restore=restoreSQL(before,after,'first');await db.exec(restore);assert.deepEqual(await observe(),before,'unused restore exactly returns all observed catalogs and protected data');
 // Reinstall only after exact unused restoration; new object OIDs are captured anew.
 await db.exec(installer);const second=await observe(),secondRestore=restoreSQL(before,second,'second');
 const name=(await db.query('select name from public.companies where id=$1',[cid])).rows[0].name;
 await db.query('update public.companies set name=$2 where id=$1',[cid,'Synthetic stale original']);const stale=await observe();
 await assert.rejects(db.exec(secondRestore),/post-install catalog\/data changed; restore refused/);await db.exec('rollback');assert.deepEqual(await observe(),stale,'stale financial/source observation refuses without partial restore');
 await db.query('update public.companies set name=$2 where id=$1',[cid,name]);assert.deepEqual(await observe(),second);
 const helper='company_common_canonical_review_private.snapshot_plan(uuid,text,bigint,jsonb,jsonb,text)';
 await db.exec('grant execute on function '+helper+' to authenticated');const changedACL=await observe();
 await assert.rejects(db.exec(secondRestore),/post-install catalog\/data changed; restore refused/);await db.exec('rollback');assert.deepEqual(await observe(),changedACL,'changed function ACL refuses without partial restore');
 await db.exec('revoke execute on function '+helper+' from authenticated');assert.deepEqual(await observe(),second);
 const owner='00000000-0000-0000-0000-000000000001';
 await db.query("insert into company_common_allowance_private.payroll_activation_modes(company_id,mode,actor_id,request_id) values($1,'per_type',$2,'80000000-0000-0000-0000-000000000111')",[cid,owner]);
 const used=await observe();await assert.rejects(db.exec(secondRestore),/post-install catalog\/data changed; restore refused/);await db.exec('rollback');assert.deepEqual(await observe(),used,'used activation refuses without deleting immutable metadata or functions');
 console.log(JSON.stringify({synthetic_only:true,observer_parser_runtime:true,protected_catalog_and_data_roundtrip:true,missing_baseline_refused:true,stale_state_refused:true,changed_acl_refused:true,used_activation_refused:true,pinned_three_units:true,exact_generated_installer:true,stale_install_refused:true,install_after_failure_full_rollback:true,production_changed:false}));
}catch(error){console.error(error.stack??error.message);process.exitCode=1;}finally{if(db)await db.close();fs.rmSync(temp,{recursive:true,force:true});}
