// Dedicated offline restore producer for the seven initially-OFF checkout
// schemas. It never connects, learns an allowlist from arbitrary objects, or
// changes application data. Native and production observations stay separate.
import assert from 'node:assert/strict';

export const schemas = ['checkout_paid_hours_candidate_private','checkout_shared_hours_private','checkout_shared_managed_private','scheduled_checkout_private','shared_daily_report_private','shared_report_edit_private','shared_worker_facts_private'];
export const tables = ['checkout_paid_hours_candidate_private.drafts','checkout_paid_hours_candidate_private.ledger','checkout_shared_hours_private.approved_fact_copies','checkout_shared_hours_private.confirmations','checkout_shared_hours_private.ledger','checkout_shared_hours_private.materialization_permits','checkout_shared_hours_private.rollout','checkout_shared_hours_private.supervisor_contexts','checkout_shared_hours_private.work_protocol','checkout_shared_managed_private.adoption_events','checkout_shared_managed_private.adoptions','checkout_shared_managed_private.manager_receipts','scheduled_checkout_private.postponements','scheduled_checkout_private.rollout','scheduled_checkout_private.settings','scheduled_checkout_private.sources','shared_daily_report_private.clock_group_context','shared_daily_report_private.rollout','shared_daily_report_private.signature_events','shared_daily_report_private.work_protocol','shared_report_edit_private.sessions'];
export const originals = ['public.sign_daily_report(uuid, text, jsonb)','company_checkout_allowance_private.report_basis(uuid)','company_checkout_allowance_private.resolve(uuid, uuid, date, date)','public.force_manage_attendance(text, jsonb)'];
export const publicNames = ['read_checkout_paid_work_hours','save_checkout_paid_work_hours','confirm_managed_shared_work_hours','read_shared_worker_facts','confirm_shared_worker_facts','confirm_managed_shared_worker_facts','read_my_shared_daily_report','read_shared_daily_report_context','reuse_my_shared_daily_report','submit_shared_daily_report','collect_shared_report_supervisor_signature','manage_shared_report_supervisor_signature','manage_shared_report_signature','collect_approved_shared_report_supervisor_signature','save_my_gps_work_schedule','read_my_gps_work_schedule','read_my_scheduled_checkout','postpone_my_scheduled_checkout','read_my_scheduled_checkout_notification_plan','disable_my_gps_work_schedule'];
export const protectedRelations = ['company_checkout_allowance_private.receipts','public.daily_reports','public.daily_report_workers','public.daily_report_edit_requests','public.attendance_verifications','public.attendance_entries','public.payroll_statements','public.worker_payroll_settings','public.company_members','public.gps_auto_attendance_schedules','public.work_attendance_selections','public.work_vehicle_route_selections','checkout_report_registration_private.rollout','checkout_report_registration_private.daily_deliveries','checkout_report_registration_private.scheduler_state'];
const lit = value => "'" + String(value).replaceAll("'", "''") + "'";
const ident = value => '"' + value.replaceAll('"','""') + '"';
const qualified = value => value.split('.').map(ident).join('.');
const ns = schemas.map(lit).join(',');
const rpc = publicNames.map(lit).join(',');
const originalNames = ['sign_daily_report','report_basis','resolve','force_manage_attendance'];
const actualSignature = "n.nspname||'.'||p.proname||'('||oidvectortypes(p.proargtypes)||')'";
const procRecord = `jsonb_build_object('signature',${actualSignature},'definition',pg_get_functiondef(p.oid),'md5',md5(p.prosrc),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'config',p.proconfig,'definer',p.prosecdef,'volatility',p.provolatile,'strict',p.proisstrict,'parallel',p.proparallel,'leakproof',p.proleakproof,'cost',p.procost,'rows',p.prorows)`;
const moduleProcWhere = `(n.nspname in(${ns}) or(n.nspname='public' and p.proname in(${rpc})))`;
const isOriginal = "(n.nspname='public' and p.proname in('sign_daily_report','force_manage_attendance') or n.nspname='company_checkout_allowance_private' and p.proname in('report_basis','resolve'))";
const catalogExpression = `jsonb_build_object(
 'schemas',(select coalesce(jsonb_agg(jsonb_build_object('name',nspname,'owner',pg_get_userbyid(nspowner),'acl',nspacl::text) order by nspname),'[]') from pg_namespace where nspname in(${ns})),
 'routines',(select coalesce(jsonb_agg(${procRecord} order by ${actualSignature}),'[]') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where ${moduleProcWhere}),
 'classes',(select coalesce(jsonb_agg(jsonb_build_object('name',n.nspname||'.'||c.relname,'kind',c.relkind,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'options',c.reloptions,
  'columns',(select coalesce(jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'notnull',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum),'[]') from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
  'constraints',(select coalesce(jsonb_agg(pg_get_constraintdef(x.oid,true) order by x.conname),'[]') from pg_constraint x where x.conrelid=c.oid)) order by n.nspname,c.relname),'[]') from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in(${ns})),
 'types',(select coalesce(jsonb_agg(jsonb_build_object('name',n.nspname||'.'||t.typname,'kind',t.typtype,'owner',pg_get_userbyid(t.typowner),'acl',t.typacl::text) order by n.nspname,t.typname),'[]') from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname in(${ns})),
 'triggers',(select coalesce(jsonb_agg(jsonb_build_object('table',tn.nspname||'.'||c.relname,'name',t.tgname,'definition',pg_get_triggerdef(t.oid,true),'enabled',t.tgenabled,'constraint',t.tgconstraint<>0) order by tn.nspname,c.relname,t.tgname),'[]') from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace tn on tn.oid=c.relnamespace join pg_proc p on p.oid=t.tgfoid join pg_namespace fn on fn.oid=p.pronamespace where not t.tgisinternal and fn.nspname in(${ns})),
 'foreign_keys',(select coalesce(jsonb_agg(jsonb_build_object('child',cn.nspname||'.'||c.relname,'parent',pn.nspname||'.'||p.relname) order by cn.nspname,c.relname,pn.nspname,p.relname),'[]') from pg_constraint x join pg_class c on c.oid=x.conrelid join pg_namespace cn on cn.oid=c.relnamespace join pg_class p on p.oid=x.confrelid join pg_namespace pn on pn.oid=p.relnamespace where x.contype='f' and cn.nspname in(${ns}) and pn.nspname in(${ns})),
 'policies',(select coalesce(jsonb_agg(jsonb_build_object('table',n.nspname||'.'||c.relname,'name',p.polname,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) order by n.nspname,c.relname,p.polname),'[]') from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in(${ns}))
)`;
const oldRoutineHash = `(select md5(coalesce(jsonb_agg(${procRecord} order by ${actualSignature})::text,'[]')) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname not like 'pg_%' and n.nspname<>'information_schema' and not ${moduleProcWhere})`;
const oldTriggerHash = `(select md5(coalesce(jsonb_agg(jsonb_build_object('table',tn.nspname||'.'||c.relname,'name',t.tgname,'definition',pg_get_triggerdef(t.oid,true),'enabled',t.tgenabled) order by tn.nspname,c.relname,t.tgname)::text,'[]')) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace tn on tn.oid=c.relnamespace join pg_proc p on p.oid=t.tgfoid join pg_namespace fn on fn.oid=p.pronamespace where not t.tgisinternal and fn.nspname not in(${ns}))`;
const oldRelationHash = `(select md5(coalesce(jsonb_agg(jsonb_build_object('name',n.nspname||'.'||c.relname,'kind',c.relkind,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'options',c.reloptions,
 'columns',(select coalesce(jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'notnull',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum),'[]') from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
 'constraints',(select coalesce(jsonb_agg(pg_get_constraintdef(x.oid,true) order by x.conname),'[]') from pg_constraint x where x.conrelid=c.oid)) order by n.nspname,c.relname)::text,'[]')) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname not like 'pg_%' and n.nspname<>'information_schema' and n.nspname not in(${ns}))`;
const defaultAclHash = `(select md5(coalesce(jsonb_agg(to_jsonb(d) order by d.oid)::text,'[]')) from pg_default_acl d)`;
const fingerprintExpression = relations => "jsonb_build_object(" + relations.map(table => `${lit(table)},(select jsonb_build_object('count',count(*),'md5',md5(coalesce(string_agg(row_sha,'' order by row_sha),''))) from(select md5(to_jsonb(t)::text) row_sha from ${qualified(table)} t) row_hashes)`).join(',') + ')';
export function snapshotSQL({installed=false,nativeAuth=false}={}) {
 const relations = [...protectedRelations,...(nativeAuth?['auth.users','auth.sessions']:[])];
 const counts = installed ? `jsonb_build_object(${tables.map(t=>`${lit(t)},(select count(*) from ${qualified(t)})`).join(',')})` : "'{}'::jsonb";
 return `select jsonb_build_object('schema',1,'module_catalog',${catalogExpression},'originals',(select jsonb_agg(${procRecord} order by ${actualSignature}) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where ${isOriginal}),'old_routine_hash',${oldRoutineHash},'old_trigger_hash',${oldTriggerHash},'old_relation_hash',${oldRelationHash},'default_acl_hash',${defaultAclHash},'protected_relations',${fingerprintExpression(relations)},'new_counts',${counts}) as snapshot`;
}
export async function collectSnapshot(client,options={}) {
 return (await client.query(snapshotSQL(options))).rows[0].snapshot;
}
const hasExternalDependency = `with recursive seeds(classid,objid) as (
 select 'pg_namespace'::regclass,oid from pg_namespace where nspname in(${ns})
 union select 'pg_class'::regclass,c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in(${ns})
 union select 'pg_type'::regclass,t.oid from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname in(${ns})
 union select 'pg_proc'::regclass,p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where ${moduleProcWhere}
 union select 'pg_trigger'::regclass,t.oid from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace where not t.tgisinternal and n.nspname in(${ns})
), allowed(classid,objid) as(select classid,objid from seeds union select d.classid,d.objid from pg_depend d join allowed a on a.classid=d.refclassid and a.objid=d.refobjid where d.deptype in('a','i'))
select exists(select 1 from pg_depend d join allowed a on a.classid=d.refclassid and a.objid=d.refobjid where not exists(select 1 from allowed b where b.classid=d.classid and b.objid=d.objid))`;
function dropTableOrder(foreignKeys) {
 const remaining=new Set(tables),result=[];
 while(remaining.size){
  const ready=[...remaining].filter(parent=>!foreignKeys.some(x=>x.parent===parent&&x.child!==parent&&remaining.has(x.child))).sort();
  assert.ok(ready.length,'Reviewed new-table foreign keys must be acyclic');
  for(const table of ready){result.push(table);remaining.delete(table);}
 }
 return result;
}
export function buildRestoreSQL(before,installed,{nativeAuth=false}={}) {
 assert.equal(before.schema,1);assert.equal(installed.schema,1);
 assert.deepEqual(before.module_catalog.schemas,[],'New schemas must have been absent');
 assert.deepEqual(before.module_catalog.routines,[],'New public RPCs must have been absent');
 assert.deepEqual(installed.module_catalog.schemas.map(x=>x.name).sort(),schemas);
 const actualTables=installed.module_catalog.classes.filter(x=>['r','p'].includes(x.kind)).map(x=>x.name).sort();
 assert.deepEqual(actualTables,tables,'Exactly 21 reviewed new tables');
 assert.deepEqual(installed.new_counts,Object.fromEntries(tables.map(t=>[t,0])),'Only a never-used initial OFF observation can produce an unused restore');
 assert.deepEqual(installed.protected_relations,before.protected_relations,'Install cannot mutate existing application/foundation/Auth rows');
 assert.deepEqual(installed.originals.map(x=>x.signature).sort(),originals.slice().sort(),'Exactly four original routines are connected');
 assert.deepEqual(before.originals.map(x=>x.signature).sort(),originals.slice().sort());
 for(const b of before.originals){const a=installed.originals.find(x=>x.signature===b.signature);for(const key of ['owner','acl','config','definer','volatility','strict','parallel','leakproof','cost','rows'])assert.deepEqual(a[key],b[key],'Original routine attributes preserved: '+b.signature+' '+key);}
 assert.ok(installed.module_catalog.routines.every(x=>x.owner==='postgres'));
 const literal=value=>{const text=JSON.stringify(value);assert.ok(!text.includes('$restore_json$'));return '$restore_json$'+text+'$restore_json$::jsonb';};
 const protectedSQL=fingerprintExpression([...protectedRelations,...(nativeAuth?['auth.users','auth.sessions']:[])]);
 const counts=`jsonb_build_object(${tables.map(t=>`${lit(t)},(select count(*) from ${qualified(t)})`).join(',')})`;
 const originalSnapshot=`(select jsonb_agg(${procRecord} order by ${actualSignature}) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where ${isOriginal})`;
 let sql=`-- REVIEW ONLY. Exact never-used OFF restore; no application/Auth DML.\nbegin;\nset local lock_timeout='2s';\nset local statement_timeout='15s';\n`;
 // Fail immediately instead of creating a row/table lock cycle with a writer.
 for(const table of protectedRelations.slice().sort())sql+=`lock table ${qualified(table)} in share row exclusive mode nowait;\n`;
 for(const table of tables)sql+=`lock table ${qualified(table)} in access exclusive mode nowait;\n`;
 sql+=`do $unused_guard$ begin
 if ${counts} is distinct from ${literal(installed.new_counts)} then raise exception 'shared_checkout_restore_used_state';end if;
 if ${catalogExpression} is distinct from ${literal(installed.module_catalog)} then raise exception 'shared_checkout_restore_catalog_changed';end if;
 if ${originalSnapshot} is distinct from ${literal(installed.originals)} then raise exception 'shared_checkout_restore_original_connection_changed';end if;
 if (${hasExternalDependency}) then raise exception 'shared_checkout_restore_external_dependency';end if;
 if ${oldRoutineHash} is distinct from ${lit(installed.old_routine_hash)} or ${oldTriggerHash} is distinct from ${lit(installed.old_trigger_hash)} or ${oldRelationHash} is distinct from ${lit(installed.old_relation_hash)} or ${defaultAclHash} is distinct from ${lit(installed.default_acl_hash)} then raise exception 'shared_checkout_restore_existing_catalog_changed';end if;
 if ${protectedSQL} is distinct from ${literal(before.protected_relations)} then raise exception 'shared_checkout_restore_existing_data_changed';end if;
 if to_regclass('cron.job') is not null then
  if exists(select 1 from cron.job where command ~ '(checkout_report_registration_private|checkout_paid_hours_candidate_private|checkout_shared_hours_private|checkout_shared_managed_private|scheduled_checkout_private|shared_daily_report_private|shared_report_edit_private|shared_worker_facts_private)') then raise exception 'shared_checkout_restore_cron_present';end if;
 end if;
end $unused_guard$;\n`;
 for(const row of before.originals)sql+=row.definition.trim().replace(/;?$/,';')+'\n';
 for(const t of installed.module_catalog.triggers)sql+=`drop trigger ${ident(t.name)} on ${qualified(t.table)} restrict;\n`;
 for(const f of installed.module_catalog.routines.slice().reverse())sql+=`drop function ${f.signature} restrict;\n`;
 for(const table of dropTableOrder(installed.module_catalog.foreign_keys))sql+=`drop table ${qualified(table)} restrict;\n`;
 for(const name of schemas)sql+=`drop schema ${ident(name)} restrict;\n`;
 sql+=`do $restored_guard$ begin
 if ${catalogExpression} is distinct from ${literal(before.module_catalog)} or ${originalSnapshot} is distinct from ${literal(before.originals)} or ${oldRoutineHash} is distinct from ${lit(before.old_routine_hash)} or ${oldTriggerHash} is distinct from ${lit(before.old_trigger_hash)} or ${oldRelationHash} is distinct from ${lit(before.old_relation_hash)} or ${defaultAclHash} is distinct from ${lit(before.default_acl_hash)} then raise exception 'shared_checkout_restore_catalog_not_exact';end if;
 if ${protectedSQL} is distinct from ${literal(before.protected_relations)} then raise exception 'shared_checkout_restore_data_not_exact';end if;
end $restored_guard$;\ncommit;\n`;
 assert.ok(!/\bdrop\b[^;]*\bcascade\b/i.test(sql));
 return sql;
}

// Only reviewed module-level wrappers are removed; function bodies stay exact.
export function assembleOffInstallSQL(modules) {
 assert.equal(modules.length,14,'Exactly fourteen reviewed OFF modules');
 const bodies=modules.map(sql=>{
  const outer=/^((?:\s|--[^\n]*(?:\n|$))*)begin;([\s\S]*)commit;\s*$/i.exec(sql);
  const body=outer?outer[1]+outer[2]:sql;
  // These reviewed sources use bare BEGIN inside PL/pgSQL, never BEGIN;.
  assert.ok(!/^\s*(?:begin|commit|rollback)\s*;/im.test(body),'Unexpected transaction control in OFF module');
  return body;
 });
 return "begin;\nset local lock_timeout='2s';\n"+bodies.join('\n')+'\ncommit;\n';
}
