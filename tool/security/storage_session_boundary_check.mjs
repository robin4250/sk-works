import fs from 'node:fs';
import assert from 'node:assert/strict';
import {pathToFileURL,fileURLToPath} from 'node:url';
import path from 'node:path';
const here=path.dirname(fileURLToPath(import.meta.url));
const capture=JSON.parse(fs.readFileSync(path.join(here,'storage_session_catalog.json'),'utf8'));
let db;
if(process.argv[3]==='--pg17'){
 const url=new URL(process.env.SKO_STORAGE_SESSION_FIXTURE_URL??'');
 assert.ok(['127.0.0.1','localhost'].includes(url.hostname)&&url.pathname==='/sko_storage_session_fixture','Disposable loopback database only');
 const mod=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new (mod.Client??mod.default.Client)({connectionString:url.href});await db.connect();db.exec=q=>db.query(q);db.close=()=>db.end();
 assert.equal(Math.floor(Number((await db.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 assert.equal((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth','storage') and c.relkind in ('r','v','m')")).rows[0].n,0);
}else{const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new PGlite();}
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const company=id(1),worker=id(2),requirement=id(3),own=id(10),manager=id(11),admin=id(12),other=id(13),viewer=id(14),owner=id(15);
const photo=`${company}/${worker}/${requirement}/${id(4)}/document.jpg`;
const otherPhoto=`${company}/${worker}/${requirement}/${id(4)}/unlinked.jpg`;
let checks=0;
const q=s=>"'"+s.replaceAll("'","''")+"'";
async function visible(actor,expected,name=photo,setup=''){
 await db.exec('begin');try{if(setup)await db.exec(setup);await db.exec(`select set_config('fixture.uid',${q(actor??'')},true);set local role ${actor?'authenticated':'anon'}`);
 assert.equal((await db.query(`select count(*)::int n from storage.objects where name=${q(name)}`)).rows[0].n,expected);checks++;
 }finally{await db.exec('rollback');}
}
const snapshot=async()=>(await db.query(`select jsonb_build_object('objects',(select jsonb_agg(to_jsonb(o) order by name) from storage.objects o),'statuses',(select jsonb_agg(to_jsonb(s)) from public.worker_document_statuses s),'workers',(select jsonb_agg(to_jsonb(w)) from public.workers w))::text digest`)).rows[0].digest;
try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;create schema storage;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.uid',true),'')::uuid$$;
 create table private.account_deletion_access_restrictions(user_id uuid);
 create type public.app_role as enum ('owner','admin','manager','worker','viewer');
 create table public.company_members(company_id uuid,user_id uuid,role public.app_role);
 create table public.member_feature_permissions(company_id uuid,user_id uuid,can_view_invoices boolean default false,can_manage_invoices boolean default false,can_manage_payroll boolean default false,can_manage_people boolean default false,can_manage_attendance boolean default false,can_approve_daily_report_edits boolean default false,can_manage_partner_chat boolean default false);
 create table public.workers(id uuid,company_id uuid,user_id uuid);
 create table public.document_requirements(id uuid,company_id uuid,is_active boolean,name text,scope text,sort_order integer);
 create table public.worker_document_statuses(id uuid,company_id uuid,worker_id uuid,requirement_id uuid,attachment_path text,attachment_paths text[],status text);
 create table private.document_submissions(company_id uuid,worker_id uuid,requested_by uuid,status text,upload_path text,attachment_path text,previous jsonb);
 create table public.company_approval_assignees(company_id uuid,user_id uuid);
 create table storage.objects(bucket_id text,name text,payload text);
 grant usage on schema auth,private,storage to anon,authenticated;grant select on all tables in schema public,storage to anon,authenticated;`);
 for(const f of capture.functions)await db.exec(f.definition);
 for(const table of ['workers','company_members','document_requirements','worker_document_statuses'])await db.exec(`alter table public.${table} enable row level security`);
 for(const p of capture.business_read_policy_inventory){
  // Owner-manage duplicates member-self access for these fixture actors; its unrelated helper is outside this selected fixture.
  if(p.policyname==='company_members_owner_manage')continue;
  await db.exec(`create policy ${JSON.stringify(p.policyname)} on public.${p.tablename} as ${p.permissive} for select to authenticated using (${p.qual})`);
 }
 await db.exec('alter table storage.objects enable row level security');
 for(const p of capture.storage_read_policy_inventory.filter(p=>p.policyname==='account_deletion_access_guard'||p.qual?.includes("bucket_id = 'worker-documents'"))){
  await db.exec(`create policy ${JSON.stringify(p.policyname)} on storage.objects as ${p.permissive} for select to authenticated using (${p.qual})`);
 }
 await db.exec(`insert into public.company_members values('${company}','${own}','worker'),('${company}','${manager}','manager'),('${company}','${admin}','admin'),('${id(99)}','${other}','admin'),('${company}','${viewer}','viewer'),('${company}','${owner}','owner');
 insert into public.member_feature_permissions(company_id,user_id,can_manage_people) values('${company}','${manager}',false);
 insert into public.workers values('${worker}','${company}','${own}');
 insert into public.document_requirements values('${requirement}','${company}',true,'免許証','internal',1);
 insert into public.worker_document_statuses values('${id(4)}','${company}','${worker}','${requirement}','${photo}',array['${photo}'],'submitted');
 insert into storage.objects values('worker-documents','${photo}','synthetic bytes unchanged'),('worker-documents','${otherPhoto}','synthetic unlinked');`);
 const before=await snapshot();
 // Reproduce observed role-only access before candidate; do not label this expected-denial success.
 await visible(manager,1);console.log('REPRODUCED live manager feature OFF reads referenced photo through permissive role policy');
 const candidate=fs.readFileSync(path.join(here,'storage_session_feature_boundary.sql.review-only'),'utf8');
 const policy=async()=>(await db.query("select pg_get_expr(polqual,polrelid) q from pg_policy where polname='worker_document_photo_managed_read'")).rows[0].q;
 const original=await policy();
 await assert.rejects(db.exec(candidate.replace('commit;',"do $$begin raise exception 'fixture late failure';end$$;commit;")));
 await db.exec('rollback');assert.equal(await policy(),original);assert.equal(await snapshot(),before);
 await db.exec('begin;alter policy worker_document_photo_managed_read on storage.objects using(false);');
 await assert.rejects(db.exec(candidate.replace('begin;','')),e=>e.code==='55000');await db.exec('rollback');
 assert.equal(await policy(),original);
 await db.exec(candidate);
 await visible(null,0);await visible(other,0);await visible(viewer,0);await visible(manager,0);
 await visible(manager,1,photo,`update public.member_feature_permissions set can_manage_people=true`);
 await visible(own,1);await visible(admin,1);await visible(owner,1);await visible(manager,0,otherPhoto);
 await visible(manager,0,photo,`insert into private.account_deletion_access_restrictions values('${manager}');update public.member_feature_permissions set can_manage_people=true`);
 await visible(own,0,photo,`insert into private.account_deletion_access_restrictions values('${own}')`);
 // Same JWT subject, fresh DB feature state: revoke permission without pretending the JWT was revoked.
 await db.exec(`update public.member_feature_permissions set can_manage_people=true`);await visible(manager,1);
 await db.exec(`update public.member_feature_permissions set can_manage_people=false`);await visible(manager,0);
 assert.deepEqual(await snapshot(),before,'Existing rows/object payloads were rewritten');
 // No auth.sessions check exists in the actual account guard: do not claim old JWT invalidation.
 const guard=capture.functions.find(f=>f.proname==='account_access_allowed').definition;
 assert.ok(!guard.includes('auth.sessions'));assert.match(guard,/account_deletion_access_restrictions/);
 console.log(`PASS ${checks} actual selected RLS checks; source policy reproduced; candidate denies feature-OFF; own/admin/feature-ON and rows preserved. Storage HTTP signed URL expiry/revocation and GoTrue JWT revocation UNVERIFIED.`);
}catch(e){console.error(e.code??'',e.message);process.exitCode=1;}finally{await db.close();}
