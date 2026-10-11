// Synthetic empty databases only. Actual candidate DDL and authenticated RLS.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {validatePaidLeaveFixtureUrl} from './paid_leave_pg17_database_guard.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const source=read('supabase/migrations/20261011053526_worker_document_managed_photo_storage.sql');
const body=source.replace(/^begin;\n/,'').replace(/\ncommit;\n$/,'');
let db;
if(process.argv[3]==='--pg17') {
 const module=await import(pathToFileURL(path.resolve(process.argv[2])).href);const Client=module.Client??module.default?.Client;
 db=new Client({connectionString:validatePaidLeaveFixtureUrl(process.env.SKO_PAID_LEAVE_FIXTURE_URL)});await db.connect();db.exec=q=>db.query(q);db.close=()=>db.end();
 assert.equal(Math.floor(Number((await db.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 assert.equal((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth','storage') and c.relkind in ('r','v','m')")).rows[0].n,0,'Empty fixture only');
} else {const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new PGlite();}
const company='10000000-0000-0000-0000-000000000001';
const own='20000000-0000-0000-0000-000000000001',manager='20000000-0000-0000-0000-000000000002',viewer='20000000-0000-0000-0000-000000000003',foreign='20000000-0000-0000-0000-000000000004';
const worker='30000000-0000-0000-0000-000000000001',other='30000000-0000-0000-0000-000000000002';
const requirement='40000000-0000-0000-0000-000000000001',inactive='40000000-0000-0000-0000-000000000003',foreignRequirement='40000000-0000-0000-0000-000000000002';
const status='50000000-0000-0000-0000-000000000001',otherStatus='50000000-0000-0000-0000-000000000002';
const object=(w=worker,r=requirement,s=status,f='new.jpg',c=company)=>`${c}/${w}/${r}/${s}/${f}`;
let checks=0;
const snapshot=async()=>({
 rows:await Promise.all(['public.worker_document_statuses','public.worker_document_status_history','public.workers','public.document_requirements','public.company_members','storage.objects','private.license_document_upload_pilots'].map(async t=>(await db.query(`select to_jsonb(t) row from ${t} t order by to_jsonb(t)::text`)).rows)),
 acl:(await db.query("select oid::regclass::text n,relacl::text a,relrowsecurity from pg_class where oid in ('public.workers'::regclass,'public.document_requirements'::regclass,'public.worker_document_statuses'::regclass,'storage.objects'::regclass) order by n")).rows,
 policies:(await db.query("select polrelid::regclass::text t,polname,polcmd,polpermissive,polroles::text,pg_get_expr(polqual,polrelid) u,pg_get_expr(polwithcheck,polrelid) c from pg_policy where polname not in ('worker_document_photo_managed_insert','worker_document_photo_managed_read') order by t,polname")).rows,
 functions:(await db.query("select oid::regprocedure::text n,prosrc,proacl::text,prosecdef,provolatile,proconfig from pg_proc where pronamespace in ('private'::regnamespace,'auth'::regnamespace) and oid<>'private.worker_document_photo_upload_allowed(text)'::regprocedure order by n")).rows,
 helperAcl:(await db.query("select proacl::text,prosecdef,provolatile,proconfig from pg_proc where oid='private.worker_document_photo_upload_allowed(text)'::regprocedure")).rows
});
async function withActor(uid,fn,setup='') {await db.exec('begin');try{if(setup)await db.exec(setup);await db.exec(`select set_config('fixture.uid','${uid}',true);set local role authenticated`);await fn();checks++;}finally{await db.exec('rollback');}}
async function insert(label,uid,name,allowed,setup='') {await withActor(uid,async()=>{const sql=`insert into storage.objects(bucket_id,name,payload) values('worker-documents','${name}','${label}')`;if(allowed)await db.exec(sql);else await assert.rejects(db.exec(sql),e=>e.code==='42501',label);},setup);}
async function visible(uid,name,expected,setup='') {await withActor(uid,async()=>assert.equal((await db.query(`select count(*)::int n from storage.objects where bucket_id='worker-documents' and name='${name}'`)).rows[0].n,expected),setup);}
try {
 await db.exec(read('supabase/tests/license_document_upload_pilot_assertions.sql').split('-- PRODUCT_ASSERTIONS')[0]);
 // Model observed production role-based business-table read, keeping the worker
 // column-only ACL and Storage feature-based policies that caused the defect.
 await db.exec(`create type public.app_role as enum ('owner','admin','manager','viewer','worker');alter table public.company_members add column role public.app_role not null default 'worker';update public.company_members set role='manager' where user_id='${manager}';update public.company_members set role='viewer' where user_id='${viewer}';update public.company_members set role='admin' where user_id='${foreign}';delete from private.feature_grants;
 create policy fixture_existing_document_manager_read on public.worker_document_statuses for select to authenticated using(exists(select 1 from public.company_members m where m.company_id=worker_document_statuses.company_id and m.user_id=auth.uid() and m.role in ('owner','admin','manager')));
 drop policy fixture_authenticated_read on storage.objects;
 create policy fixture_authenticated_read on storage.objects for select to authenticated using(bucket_id='worker-documents' and (private.has_company_feature(private.try_uuid(split_part(name,'/',1)),'can_manage_people') or exists(select 1 from public.workers w where w.id=private.try_uuid(split_part(storage.objects.name,'/',2)) and w.company_id=private.try_uuid(split_part(storage.objects.name,'/',1)) and w.user_id=auth.uid())));
 alter table public.worker_document_statuses add column attachment_paths text[] not null default '{}';alter table public.worker_document_status_history add column attachment_paths text[] not null default '{}';`);
 await db.exec(read('supabase/migrations/20261009111338_license_document_upload_pilot_contract.sql'));
 // Production restrictive policy contains the already deployed qualification
 // branch before worker-photo extension. Candidate must leave it byte-for-byte.
 await db.exec('create function private.qualification_photo_draft_upload_allowed(text) returns boolean language sql stable as $$select false$$');
 let original=(await db.query("select pg_get_expr(polwithcheck,polrelid) e from pg_policy where polname='license_document_pilot_insert_scope'")).rows[0].e;
 await db.exec(`alter policy license_document_pilot_insert_scope on storage.objects with check((${original}) or (bucket_id='qualification-certificates' and private.qualification_photo_draft_upload_allowed(name)))`);
 await db.exec(read('supabase/migrations/20261011033201_worker_document_photo_upload_scope.sql'));
 const old=object(worker,requirement,status,'old.jpg'),extra=object(worker,requirement,status,'extra.png'),unlinked=object(worker,requirement,status,'unlinked.jpg');
 await db.exec(`update public.worker_document_statuses set attachment_paths=array['${old}','${extra}'] where id='${status}';insert into storage.objects(bucket_id,name,payload) values('worker-documents','${extra}','saved-extra'),('worker-documents','${unlinked}','unlinked');insert into private.retained_objects values('${extra}');`);
 const before=await snapshot();
 await insert('manager-feature-false-before',manager,object(),false);
 await visible(manager,old,0);await visible(manager,extra,0);
 for(const mutation of [
  'create or replace function private.worker_document_photo_upload_allowed(p_path text) returns boolean language sql stable security invoker set search_path=\'\' as $$select true$$',
  'alter function private.worker_document_photo_upload_allowed(text) security definer',
  'alter function private.worker_document_photo_upload_allowed(text) set search_path=public',
  'alter function private.worker_document_photo_upload_allowed(text) reset search_path',
  'grant execute on function private.worker_document_photo_upload_allowed(text) to anon',
  'alter policy license_document_pilot_insert_scope on storage.objects with check(true)',
  'alter table public.worker_document_statuses drop column attachment_paths'
 ]) {await db.exec('begin');try{await db.exec(mutation);await assert.rejects(db.exec(body),e=>e.code==='55000');}finally{await db.exec('rollback');}assert.deepEqual(await snapshot(),before);}
 const oldHelper=(await db.query("select prosrc from pg_proc where oid='private.worker_document_photo_upload_allowed(text)'::regprocedure")).rows[0].prosrc;
 await db.exec('create policy worker_document_photo_managed_read on storage.objects for select to authenticated using(false)');
 await assert.rejects(db.exec(source),e=>e.code==='42710');await db.exec('rollback');
 assert.equal((await db.query("select prosrc from pg_proc where oid='private.worker_document_photo_upload_allowed(text)'::regprocedure")).rows[0].prosrc,oldHelper);
 assert.equal((await db.query("select count(*)::int n from pg_policy where polname='worker_document_photo_managed_insert'")).rows[0].n,0);
 await db.exec('drop policy worker_document_photo_managed_read on storage.objects');assert.deepEqual(await snapshot(),before);
 await db.exec(source);assert.deepEqual(await snapshot(),before,'DDL changed old data/objects/policies/ACL/history/pilot settings');
 for(const role of ['owner','admin','manager']) {
  const setup=`update public.company_members set role='${role}' where user_id='${manager}'`;
  await insert(role+' first-upload',manager,object(worker,requirement,'own-upload'),true,setup);
  await insert(role+' existing-status',manager,object(),true,setup);
  await insert(role+' any same-company worker',manager,object(other,requirement,otherStatus),true,setup);
  await visible(manager,old,1,setup);await visible(manager,extra,1,setup);await visible(manager,unlinked,0,setup);
 }
 await insert('self-preserved',own,object(worker,requirement,'own-upload'),true);
 await insert('viewer-own-preserved',viewer,object(other,requirement,'own-upload'),true);
 await visible(manager,old,1,`update public.worker_document_statuses set attachment_paths='{}' where id='${status}'`);
 for(const uid of [viewer,foreign]) {await insert('non-manager',uid,object(),false);await visible(uid,old,0);await visible(uid,extra,0);}
 for(const filename of ['bad.exe','../a.jpg','a/b.jpg','name space.jpg'])await insert('invalid-filename',manager,object(worker,requirement,status,filename),false);
 await insert('foreign-requirement',manager,object(worker,foreignRequirement),false);
 await insert('inactive-requirement',manager,object(worker,inactive),false);
 await insert('wrong-status-worker',manager,object(worker,requirement,otherStatus),false);
 await insert('unknown-status',manager,object(worker,requirement,'50000000-0000-0000-0000-000000000099'),false);
 await insert('company-spoof',manager,object(worker,requirement,status,'new.jpg','10000000-0000-0000-0000-000000000002'),false);
 await insert('blocked-account',manager,object(),false,`insert into private.restricted_users values('${manager}')`);
 await visible(manager,old,0,`insert into private.restricted_users values('${manager}')`);
 await insert('inactive-worker',manager,object(),false,`update public.workers set status='inactive' where id='${worker}'`);
 await visible(manager,old,1,`update public.workers set status='inactive' where id='${worker}'`);
 await visible(manager,extra,1,`update public.document_requirements set is_active=false where id='${requirement}'`);
 await withActor(manager,async()=>{assert.equal((await db.query(`update storage.objects set payload='overwrite' where name='${old}' returning id`)).rows.length,0);assert.equal((await db.query(`delete from storage.objects where name='${old}' returning id`)).rows.length,0);});
 await db.exec('begin');try{await db.exec('set local role anon');await assert.rejects(db.exec(`insert into storage.objects(bucket_id,name,payload) values('worker-documents','${object()}','anonymous')`),e=>e.code==='42501');checks++;}finally{await db.exec('rollback');}
 assert.deepEqual(await snapshot(),before,'Role checks changed existing evidence');
 console.log(`PASS managed worker document photos: ${checks} authenticated role/path INSERT/read/retention checks, 7 drift rejections, late rollback; same-company owner/admin/manager without feature grants; old rows/files/history/ACL/pilot/other policies preserved`);
} catch(e){console.error(e.code,e.message,e.where??'');process.exitCode=1;}finally{await db.close();}
