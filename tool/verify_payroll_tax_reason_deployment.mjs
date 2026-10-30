// Runs the existing reason boundary/concurrency suite unchanged, with only its
// installation input replaced by an offline-generated catalog-guarded bundle.
import {readFile, writeFile, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const temp=await mkdtemp(join(tmpdir(),'payroll-reason-review-'));
try {
 let source=await readFile('tool/verify_payroll_tax_adjustment_reason.mjs','utf8');
 const point=" const candidate=read('docs/candidates/payroll_tax_adjustment_reason.sql.review-only');";
 assert.equal(source.split(point).length,2);
 const injected=`
 await db.exec('alter default privileges for role postgres in schema public grant execute on functions to anon,authenticated,service_role');
 const out=${JSON.stringify(temp)};
 const capture=async()=>{
  const ids=(await db.query("select c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and n.nspname in ('public','private','payroll_tax_private','auth') order by c.oid")).rows.map(r=>r.oid);
  const m={};
  m.functions=(await db.query("select n.nspname schema,p.proname name,pg_get_function_identity_arguments(p.oid) identity,pg_get_functiondef(p.oid) definition,md5(p.prosrc) source_md5,to_jsonb(p)-'prosrc' attributes from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','payroll_tax_private','auth') order by p.oid")).rows;
  m.relations=(await db.query('select to_jsonb(c) item from pg_class c where c.oid=any($1::oid[]) order by c.oid',[ids])).rows.map(r=>r.item);
  m.columns=(await db.query('select to_jsonb(a) item from pg_attribute a where a.attrelid=any($1::oid[]) and a.attnum>0 and not a.attisdropped order by a.attrelid,a.attnum',[ids])).rows.map(r=>r.item);
  m.constraints=(await db.query("select jsonb_build_object('attrs',to_jsonb(c),'definition',pg_get_constraintdef(c.oid)) item from pg_constraint c where c.conrelid=any($1::oid[]) order by c.oid",[ids])).rows.map(r=>r.item);
  m.indexes=(await db.query("select jsonb_build_object('attrs',to_jsonb(i),'definition',pg_get_indexdef(i.indexrelid)) item from pg_index i where i.indrelid=any($1::oid[]) order by i.indexrelid",[ids])).rows.map(r=>r.item);
  m.triggers=(await db.query("select jsonb_build_object('attrs',to_jsonb(t),'definition',pg_get_triggerdef(t.oid)) item from pg_trigger t where t.tgrelid=any($1::oid[]) and not t.tgisinternal order by t.oid",[ids])).rows.map(r=>r.item);
  m.policies=(await db.query('select to_jsonb(p) item from pg_policy p where p.polrelid=any($1::oid[]) order by p.oid',[ids])).rows.map(r=>r.item);
  m.defaults=(await db.query("select jsonb_build_object('attrs',to_jsonb(d),'schema',coalesce(n.nspname,'')) item from pg_default_acl d left join pg_namespace n on n.oid=d.defaclnamespace where d.defaclrole=(select oid from pg_roles where rolname='postgres') and (d.defaclnamespace=0 or n.nspname in ('public','payroll_tax_private')) order by d.oid")).rows.map(r=>r.item);
  return m;
 };
 const make=async()=>{
  await fixtureWrite(out+'/catalog.json',JSON.stringify(await capture()));
  const built=fixtureSpawn('python3',[${JSON.stringify(resolve('tool/build_payroll_tax_reason_review.py'))},'--catalog',out+'/catalog.json','--source','docs/candidates/payroll_tax_adjustment_reason.sql.review-only','--output',out+'/bundle'],{encoding:'utf8'});
  assert.equal(built.status,0,built.stderr);
  return fixtureRead(out+'/bundle/guarded-forward.sql.review-only','utf8');
 };
 await db.exec('create role reason_unknown_default;alter default privileges for role postgres in schema public grant execute on functions to reason_unknown_default');
 let custom=await make();
 await assert.rejects(db.exec(custom),error=>error.message.includes('New payroll reason function contract/ACL differs'));await db.exec('rollback');
 assert.equal((await db.query("select to_regclass('payroll_tax_private.adjustment_reasons') value")).rows[0].value,null);groups++;
 await db.exec('alter default privileges for role postgres in schema public revoke execute on functions from reason_unknown_default;drop role reason_unknown_default');
 const candidate=await make();
 const committedFunctionCount=(await capture()).functions.length+6;
 const readReasonTableReceipt=async()=>(await db.query("select jsonb_build_object('class',to_jsonb(c),'constraints',(select coalesce(jsonb_agg(to_jsonb(k) order by k.oid),'[]'::jsonb) from pg_constraint k where k.conrelid=c.oid),'triggers',(select coalesce(jsonb_agg(to_jsonb(t) order by t.oid),'[]'::jsonb) from pg_trigger t where t.tgrelid=c.oid and not t.tgisinternal),'policies',(select coalesce(jsonb_agg(to_jsonb(pol) order by pol.oid),'[]'::jsonb) from pg_policy pol where pol.polrelid=c.oid)) v from pg_class c where c.oid='payroll_tax_private.adjustment_reasons'::regclass")).rows[0].v;
 await db.exec('begin;alter function private.payroll_settings_allowed(uuid,uuid,text) cost 101');
 await assert.rejects(db.exec(candidate),/Payroll reason dependency catalog changed/);await db.exec('rollback');groups++;
 const failPoint="end $reason_post$;";
 assert.equal(candidate.split(failPoint).length,2);
 await assert.rejects(db.exec(candidate.replace(failPoint,"raise exception 'fixture postflight failure';"+failPoint)),/fixture postflight failure/);await db.exec('rollback');
 assert.equal((await db.query("select to_regclass('payroll_tax_private.adjustment_reasons') value")).rows[0].value,null);
 assert.deepEqual(await metadata(),before);groups++;
 `;
 source="import {spawnSync as fixtureSpawn} from 'node:child_process';\nimport {readFile as fixtureRead,writeFile as fixtureWrite} from 'node:fs/promises';\n"+source.replace(point,injected);
 const installPoint=' await db.exec(candidate);';
 assert.equal(source.split(installPoint).length,2);
 source=source.replace(installPoint,` const installedStatements=await db.exec(candidate);
 const committedFunctionReceipt=installedStatements.find(result=>Array.isArray(result.rows)&&result.rows.length===committedFunctionCount&&result.rows.every(row=>row.definition&&row.attributes&&row.source_md5))?.rows;
 assert.equal(committedFunctionReceipt?.length,committedFunctionCount);
 const committedReasonTableReceipt=await readReasonTableReceipt();groups++;
 `);
 const end=" await db.exec('reset role');assert.deepEqual(await metadata(),before,'all original function metadata still unchanged after use');";
 assert.equal(source.split(end).length,2);
 source=source.replace(end,`
 await db.exec('reset role');
 const stateBeforePause=await snapshot();
 const entries=['public.payroll_tax_adjustment_reason_contract_version()','public.save_worker_payroll_tax_conditions_with_reason(uuid,uuid,date,bigint,jsonb,boolean,text)','payroll_tax_private.save_conditions_with_reason(uuid,uuid,date,bigint,jsonb,boolean,text)'];
 const aclBefore=(await db.query('select oid,proacl from pg_proc where oid=any($1::regprocedure[]) order by oid',[entries])).rows;
 // Use the actual guarded-forward return rows without synthesizing missing
 // fields. Table metadata is captured immediately after committed installation,
 // before any reason save, and retained as the separate table receipt.
 const receipt={functions:committedFunctionReceipt,reason_table:committedReasonTableReceipt};
 await fixtureWrite(out+'/pause-receipt.json',JSON.stringify(receipt));
 const paused=fixtureSpawn('python3',[${JSON.stringify(resolve('tool/build_payroll_tax_reason_pause.py'))},'--receipt',out+'/pause-receipt.json','--output',out+'/pause.sql.review-only'],{encoding:'utf8'});assert.equal(paused.status,0,paused.stderr);
 const pause=await fixtureRead(out+'/pause.sql.review-only','utf8');
 await assert.rejects(db.exec(pause),/Independently stopped reason writers/);await db.exec('rollback');groups++;
 // This declaration tests the SQL guard, not actual hosted quiescence.
 await db.exec("select set_config('sko.payroll_reason_writers_stopped','verified-no-inflight',false)");
 const pauseFail=pause.replace('end $pause_after$;',"raise exception 'fixture pause postflight';end $pause_after$;");
 await assert.rejects(db.exec(pauseFail),/fixture pause postflight/);await db.exec('rollback');
 assert.deepEqual((await db.query('select oid,proacl from pg_proc where oid=any($1::regprocedure[]) order by oid',[entries])).rows,aclBefore);groups++;
 await db.exec('begin;alter function private.payroll_settings_allowed(uuid,uuid,text) cost 101');
 await assert.rejects(db.exec(pause),/Reason pause committed function identity changed/);await db.exec('rollback');groups++;
 await db.exec(pause);
 await actor();await assert.rejects(db.query('select public.payroll_tax_adjustment_reason_contract_version()'),/permission denied/);
 await actor();await assert.rejects(save(6,profile),/permission denied/);
 await actor();assert.ok((await db.query('select public.read_worker_payroll_tax_adjustment_history($1,$2) value',[cid,wid])).rows[0].value.items.length>0);
 await db.exec('reset role');assert.deepEqual(await snapshot(),stateBeforePause);
 for(const entry of entries)await db.exec('grant execute on function '+entry+' to authenticated');
 assert.deepEqual((await db.query('select oid,proacl from pg_proc where oid=any($1::regprocedure[]) order by oid',[entries])).rows,aclBefore);groups++;
 `+end);
 const fixture=join(temp,'fixture.mjs');await writeFile(fixture,source);
 const result=spawnSync(process.execPath,[fixture,...process.argv.slice(2)],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;
 process.exitCode=result.status??1;
}finally{await rm(temp,{recursive:true,force:true});}
