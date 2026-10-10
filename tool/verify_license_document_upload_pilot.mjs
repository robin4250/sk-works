// Exact deployable SQL, synthetic disposable data only. No Supabase credentials.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {validatePaidLeaveFixtureUrl} from './paid_leave_pg17_database_guard.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const source=read('supabase/migrations/20261009111338_license_document_upload_pilot_contract.sql');
const [bootstrap,assertions]=read('supabase/tests/license_document_upload_pilot_assertions.sql').split('-- PRODUCT_ASSERTIONS');
assert.ok(bootstrap&&assertions,'Fixture section markers required');
let db;
if(process.argv[3]==='--pg17') {
 const m=await import(pathToFileURL(path.resolve(process.argv[2])).href);const Client=m.Client??m.default?.Client;
 db=new Client({connectionString:validatePaidLeaveFixtureUrl(process.env.SKO_PAID_LEAVE_FIXTURE_URL)});
 await db.connect();db.exec=q=>db.query(q);db.close=()=>db.end();
 assert.equal((Number((await db.query('show server_version_num')).rows[0].server_version_num)/10000)|0,17);
 assert.equal((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth','storage') and c.relkind in ('r','v','m')")).rows[0].n,0,'Only empty disposable fixture accepted');
} else {const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new PGlite();}
const protectedSnapshot=async()=>({
 statuses:(await db.query('select to_jsonb(s) row from public.worker_document_statuses s order by id')).rows,
 history:(await db.query('select to_jsonb(h) row from public.worker_document_status_history h order by id')).rows,
 objects:(await db.query('select to_jsonb(o) row from storage.objects o order by id')).rows,
 triggers:(await db.query("select oid,tgname,tgenabled,pg_get_triggerdef(oid) definition from pg_trigger where not tgisinternal order by oid")).rows,
 guards:(await db.query("select polname,polroles::text roles,polpermissive,polcmd,pg_get_expr(polqual,polrelid) using_expr,pg_get_expr(polwithcheck,polrelid) check_expr from pg_policy where polrelid='storage.objects'::regclass and polname in ('account_deletion_access_guard','official_document_history_no_delete','official_document_history_no_overwrite','initial_beta_official_documents_update_pause') order by polname")).rows,
 helpers:(await db.query("select p.oid::regprocedure::text signature,pg_get_functiondef(p.oid) definition,p.proacl::text acl,p.prosecdef,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='private' and p.proname in ('account_access_allowed','has_company_feature','try_uuid','official_document_path_is_retained','document_submission_access')) or (n.nspname='auth' and p.proname='uid') order by p.oid")).rows,
 workerAcl:(await db.query("select relacl::text table_acl,(select jsonb_agg(jsonb_build_object('column',attname,'acl',attacl::text) order by attnum) from pg_attribute where attrelid='public.workers'::regclass and attnum>0 and not attisdropped) columns from pg_class where oid='public.workers'::regclass")).rows
});
try {
 await db.exec(bootstrap);
 // A PUBLIC restrictive expression must preserve legacy nonofficial behavior,
 // including anon sessions without EXECUTE on the new authenticated helper.
 await db.exec("create policy fixture_legacy_nonofficial_insert on storage.objects for insert to anon,authenticated with check(bucket_id='fixture-nonofficial-allowed')");
 const nonofficialMatrix=async()=>{
  const result=[];
  for(const role of ['anon','authenticated']) for(const permitted of [true,false]) {
   await db.exec('begin');
   try {
    await db.exec('set local role '+role);
    if(role==='authenticated') await db.exec("select set_config('fixture.uid','20000000-0000-0000-0000-000000000001',true)");
    const bucket=permitted?'fixture-nonofficial-allowed':'fixture-nonofficial-denied';
    try {await db.exec(`insert into storage.objects(bucket_id,name,payload) values('${bucket}','synthetic.jpg','legacy')`);result.push({role,permitted,allowed:true});}
    catch(e) {assert.equal(e.code,'42501');assert.ok(!/permission denied for function/.test(e.message),'Nonofficial INSERT planned a forbidden helper');result.push({role,permitted,allowed:false});}
   } finally {await db.exec('rollback');}
  }
  for(const row of result) assert.equal(row.allowed,row.permitted,'Unexpected legacy nonofficial authorization');
  return result;
 };
 const legacyNonofficial=await nonofficialMatrix();
 const before=await protectedSnapshot();
 const attacks=[
  ['missing insert pause','drop policy initial_beta_official_documents_insert_pause on storage.objects'],
  ['altered insert pause','alter policy initial_beta_official_documents_insert_pause on storage.objects with check(true)'],
  ['altered insert pause roles','alter policy initial_beta_official_documents_insert_pause on storage.objects to authenticated'],
  ['missing guard','drop policy official_document_history_no_delete on storage.objects'],
  ['missing helper','drop function private.official_document_path_is_retained(text,text) cascade'],
  ['missing worker column ACL','revoke select(user_id) on public.workers from authenticated'],
  ['missing requirement table ACL','revoke select on public.document_requirements from authenticated']
 ];
 for(const name of ['account_deletion_access_guard','official_document_history_no_delete','official_document_history_no_overwrite','initial_beta_official_documents_update_pause']) {
  attacks.push([name+' using weakened',`alter policy ${name} on storage.objects using(true)`]);
  attacks.push([name+' roles weakened',`alter policy ${name} on storage.objects to anon`]);
  if(name!=='official_document_history_no_delete') attacks.push([name+' check weakened',`alter policy ${name} on storage.objects with check(true)`]);
 }
 for(const [label,mutation] of attacks) {
  await db.exec('begin');
  try {
   await db.exec(mutation);
   await assert.rejects(db.exec(source),e=>/Unexpected|Required|contract missing/.test(e.message),'Migration accepted '+label);
  } finally {await db.exec('rollback');}
  assert.deepEqual(await protectedSnapshot(),before,'Rollback changed registered evidence after '+label);
  assert.equal((await db.query("select to_regclass('private.license_document_upload_pilots') is null absent")).rows[0].absent,true,'Failed DDL left pilot schema');
 }
 await db.exec('begin');
 try {await db.exec(source);await db.exec('commit');}catch(e){await db.exec('rollback');throw e;}
 assert.deepEqual(await nonofficialMatrix(),legacyNonofficial,'Migration changed legacy anon/auth nonofficial INSERT');
 assert.deepEqual(await protectedSnapshot(),before,'Schema-only migration changed saved evidence, trigger/hold or worker ACL');
 assert.equal((await db.query('select count(*)::int n from private.license_document_upload_pilots')).rows[0].n,0,'Migration inserted pilot rows');
 const helper=(await db.query("select prosecdef,proconfig,has_function_privilege('anon',oid,'EXECUTE') anon_execute,has_function_privilege('authenticated',oid,'EXECUTE') authenticated_execute from pg_proc where oid='private.license_document_upload_allowed(text)'::regprocedure")).rows[0];
 assert.equal(helper.prosecdef,false);assert.equal(helper.anon_execute,false);assert.equal(helper.authenticated_execute,true);
 await db.exec(assertions);
 const n=(await db.query('select count(*)::int n from fixture_checks')).rows[0].n;
 assert.equal(n,55,'Incomplete actual product policy matrix');
 const after=await protectedSnapshot();
 assert.deepEqual(after.statuses,before.statuses);assert.deepEqual(after.history,before.history);assert.deepEqual(after.triggers,before.triggers);assert.deepEqual(after.guards,before.guards);assert.deepEqual(after.workerAcl,before.workerAcl);assert.deepEqual(after.helpers,before.helpers);
 for(const old of before.objects) assert.ok(after.objects.some(row=>JSON.stringify(row)===JSON.stringify(old)),'Old retained object lost or overwritten');
 console.log(`PASS exact license pilot SQL: ${attacks.length} failed precondition rollbacks; ${n} role/path/hold checks; 4 legacy anon/auth nonofficial before/after checks; all old statuses/history/objects/triggers/ACL retained; SHA256 ${createHash('sha256').update(source).digest('hex')}`);
} catch(e){console.error(e.code,e.message,e.where??'');process.exitCode=1;}
finally {await db.close();}
