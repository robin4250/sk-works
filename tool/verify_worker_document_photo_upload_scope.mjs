// Synthetic disposable database only; actual source DDL and role/path operations.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {validatePaidLeaveFixtureUrl} from './paid_leave_pg17_database_guard.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const source=read('supabase/migrations/20261011033201_worker_document_photo_upload_scope.sql');
const body=source.replace(/^begin;\n/, '').replace(/\ncommit;\n$/, '');
let db;
if(process.argv[3]==='--pg17') {
 const module=await import(pathToFileURL(path.resolve(process.argv[2])).href);const Client=module.Client??module.default?.Client;
 db=new Client({connectionString:validatePaidLeaveFixtureUrl(process.env.SKO_PAID_LEAVE_FIXTURE_URL)});await db.connect();db.exec=q=>db.query(q);db.close=()=>db.end();
 assert.equal(Math.floor(Number((await db.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 assert.equal((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth','storage') and c.relkind in ('r','v','m')")).rows[0].n,0,'Empty fixture only');
} else {const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new PGlite();}
const c='10000000-0000-0000-0000-000000000001',foreign='10000000-0000-0000-0000-000000000002';
const own='20000000-0000-0000-0000-000000000001',manager='20000000-0000-0000-0000-000000000002',coworker='20000000-0000-0000-0000-000000000003',outsider='20000000-0000-0000-0000-000000000004';
const worker='30000000-0000-0000-0000-000000000001',otherWorker='30000000-0000-0000-0000-000000000002';
const req='40000000-0000-0000-0000-000000000001',foreignReq='40000000-0000-0000-0000-000000000002',inactiveReq='40000000-0000-0000-0000-000000000003',generalReq='40000000-0000-0000-0000-000000000004';
const status='50000000-0000-0000-0000-000000000001',otherStatus='50000000-0000-0000-0000-000000000002';
const object=(requirement=req,slot='own-upload',filename='photo.jpg',company=c,w=worker)=>`${company}/${w}/${requirement}/${slot}/${filename}`;
let checks=0;
const snapshot=async()=>({
 data:await Promise.all(['worker_document_statuses','worker_document_status_history'].map(async t=>(await db.query(`select to_jsonb(s) row from public.${t} s order by id`)).rows)),
 objects:(await db.query('select to_jsonb(s) row from storage.objects s order by id')).rows,
 pilots:(await db.query('select to_jsonb(s) row from private.license_document_upload_pilots s order by company_id,requirement_id')).rows,
 acl:(await db.query("select oid::regclass::text table_name,relacl::text acl from pg_class where oid in ('public.workers'::regclass,'public.document_requirements'::regclass,'public.worker_document_statuses'::regclass,'storage.objects'::regclass) order by oid")).rows,
 guard:(await db.query("select polname,polroles::text,polpermissive,polcmd,pg_get_expr(polqual,polrelid) u,pg_get_expr(polwithcheck,polrelid) c from pg_policy where polrelid='storage.objects'::regclass and polname not in ('license_document_pilot_insert_scope','worker_document_photo_self_insert') order by polname")).rows,
 helper:(await db.query("select pg_get_functiondef('private.license_document_upload_allowed(text)'::regprocedure) definition")).rows
});
async function attempt(label,uid,bucket,name,allowed,setup='') {
 await db.exec('begin');
 try {
  if(setup)await db.exec(setup);
  await db.exec("select set_config('fixture.uid','"+uid+"',true)");await db.exec('set local role authenticated');
  if(allowed) await db.exec(`insert into storage.objects(bucket_id,name,payload) values('${bucket}','${name}','${label}')`);
  else await assert.rejects(db.exec(`insert into storage.objects(bucket_id,name,payload) values('${bucket}','${name}','${label}')`),e=>e.code==='42501',label);
  checks++;
 } finally {await db.exec('rollback');}
}
try {
 await db.exec(read('supabase/tests/license_document_upload_pilot_assertions.sql').split('-- PRODUCT_ASSERTIONS')[0]);
 await db.exec(read('supabase/migrations/20261009111338_license_document_upload_pilot_contract.sql'));
 await db.exec(`alter table public.worker_document_statuses add column attachment_paths text[] not null default '{}';alter table public.worker_document_status_history add column attachment_paths text[] not null default '{}';insert into public.document_requirements(id,company_id,is_active,name) values('${generalReq}','${c}',true,'Synthetic residence certificate');`);
 const before=await snapshot();
 for(const mutation of [
  'alter table public.worker_document_statuses drop column attachment_paths',
  'alter policy license_document_pilot_insert_scope on storage.objects with check(true)',
  "alter policy license_document_pilot_insert_scope on storage.objects to anon",
  "alter policy license_document_pilot_insert_scope on storage.objects with check(bucket_id<>'qualification-certificates' or private.license_document_upload_allowed(name))"
 ]) {
  await db.exec('begin');try{await db.exec(mutation);await assert.rejects(db.exec(body),e=>e.code==='55000');}finally{await db.exec('rollback');}
  assert.deepEqual(await snapshot(),before,'Rejected deployment changed evidence');
 }
 // Execute the real transaction, with failure after ALTER POLICY. Nothing may leak.
 const originalScope=(await db.query("select pg_get_expr(polwithcheck,polrelid) e from pg_policy where polname='license_document_pilot_insert_scope'")).rows[0].e;
 await db.exec("create policy worker_document_photo_self_insert on storage.objects for insert to authenticated with check(false)");
 await assert.rejects(db.exec(source),e=>e.code==='42710');
 await db.exec('rollback');
 assert.equal((await db.query("select pg_get_expr(polwithcheck,polrelid) e from pg_policy where polname='license_document_pilot_insert_scope'")).rows[0].e,originalScope,'Late failure leaked restrictive policy change');
 assert.equal((await db.query("select to_regprocedure('private.worker_document_photo_upload_allowed(text)') f")).rows[0].f,null,'Late failure leaked helper');
 await db.exec('drop policy worker_document_photo_self_insert on storage.objects');
 assert.deepEqual(await snapshot(),before,'Late deployment failure changed evidence');
 // Both approved bucket extensions compose, and unknown broadening fails closed.
 await db.exec('begin');
 try {
  await db.exec('create function private.qualification_photo_draft_upload_allowed(text) returns boolean language sql stable as $$select false$$');
  const original=(await db.query("select pg_get_expr(polwithcheck,polrelid) e from pg_policy where polname='license_document_pilot_insert_scope'")).rows[0].e;
  await db.exec(`alter policy license_document_pilot_insert_scope on storage.objects with check((${original}) or (bucket_id='qualification-certificates' and private.qualification_photo_draft_upload_allowed(name)))`);
  await db.exec(body);
  const actual=(await db.query("select pg_get_expr(polwithcheck,polrelid) e from pg_policy where polname='license_document_pilot_insert_scope'")).rows[0].e;
  assert.ok(actual.includes('private.qualification_photo_draft_upload_allowed(name)') && actual.includes('private.worker_document_photo_upload_allowed(name)'));
 } finally {await db.exec('rollback');}
 try{await db.exec(source);}catch(e){await db.exec('rollback');throw e;}
 assert.deepEqual(await snapshot(),before,'Feature DDL changed old rows, files, pilot settings, ACLs or old guards');
 const helper=(await db.query("select prosecdef,has_function_privilege('anon',oid,'EXECUTE') anon,has_function_privilege('authenticated',oid,'EXECUTE') actor from pg_proc where oid='private.worker_document_photo_upload_allowed(text)'::regprocedure")).rows[0];assert.deepEqual(helper,{prosecdef:false,anon:false,actor:true});
 await attempt('owner general first image',own,'worker-documents',object(generalReq),true);
 await attempt('manager assigned worker general image',manager,'worker-documents',object(generalReq),true);
 for(const ext of ['jpg','jpeg','png','pdf','heic','heif'])await attempt('supported '+ext,own,'worker-documents',object(req,status,'new.'+ext),true);
 for(let i=1;i<=20;i++)await attempt('ordered photo '+i,own,'worker-documents',object(generalReq,'own-upload',`photo_${i}.jpg`),true);
 await attempt('coworker cannot target another worker',coworker,'worker-documents',object(generalReq),false);
 await attempt('foreign company member cannot target',outsider,'worker-documents',object(generalReq),false);
 await attempt('spoofed company tuple',own,'worker-documents',object(req,'own-upload','p.jpg',foreign),false);
 await attempt('foreign requirement',own,'worker-documents',object(foreignReq),false);
 await attempt('inactive requirement',own,'worker-documents',object(inactiveReq),false);
 await attempt('wrong status worker tuple',own,'worker-documents',object(req,otherStatus),false);
 await attempt('wrong status requirement tuple',own,'worker-documents',object(generalReq,status),false);
 await attempt('unknown status',own,'worker-documents',object(req,'50000000-0000-0000-0000-000000000099'),false);
 await attempt('inactive worker',own,'worker-documents',object(req),false,`update public.workers set status='inactive' where id='${worker}'`);
 await attempt('blocked account',own,'worker-documents',object(req),false,`insert into private.restricted_users values('${own}')`);
 await attempt('no member',own,'worker-documents',object(req),false,`delete from public.company_members where user_id='${own}'`);
 for(const filename of ['bad.exe','../p.jpg','two/paths.jpg','file name.jpg'])await attempt('bad filename '+filename,own,'worker-documents',object(req,'own-upload',filename),false);
 for(const bucket of ['qualification-certificates','employee-onboarding-documents'])await attempt('preserved paused bucket '+bucket,own,bucket,object(generalReq),false);
 await db.exec('begin');try{await db.exec('set local role anon');await assert.rejects(db.exec(`insert into storage.objects(bucket_id,name,payload) values('worker-documents','${object()}','anonymous')`),e=>e.code==='42501');checks++;}finally{await db.exec('rollback');}
 // A known qualification extension added afterward leaves this worker branch intact.
 await db.exec('begin');try{
  await db.exec('create function private.qualification_photo_draft_upload_allowed(text) returns boolean language sql stable as $$select false$$');
  const original=(await db.query("select pg_get_expr(polwithcheck,polrelid) e from pg_policy where polname='license_document_pilot_insert_scope'")).rows[0].e;
  await db.exec(`alter policy license_document_pilot_insert_scope on storage.objects with check((${original}) or (bucket_id='qualification-certificates' and private.qualification_photo_draft_upload_allowed(name)))`);
  await db.exec(`select set_config('fixture.uid','${own}',true);set local role authenticated;insert into storage.objects(bucket_id,name,payload) values('worker-documents','${object(generalReq)}','after qualification');`);checks++;
 }finally{await db.exec('rollback');}
 assert.deepEqual(await snapshot(),before,'Role checks changed old evidence');
 console.log(`PASS exact worker photo feature: ${checks} real role/path INSERT checks; 4 drift rollbacks and late ALTER-policy rollback; qualification branch both orders preserved; pilot rows, old files/history, ACL and retention/account policies unchanged`);
} catch(e){console.error(e.code,e.message,e.where??'');process.exitCode=1;} finally {await db.close();}
