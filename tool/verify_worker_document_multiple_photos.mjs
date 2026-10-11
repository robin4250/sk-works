// Disposable synthetic PostgreSQL fixture. Never opens a production connection.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let db;
if (process.argv[3] === '--pg17') {
 const {validatePaidLeaveFixtureUrl}=await import('./paid_leave_pg17_database_guard.mjs');
 const module=await import(pathToFileURL(path.resolve(process.argv[2])).href);
 const Client=module.Client??module.default?.Client;
 db=new Client({connectionString:validatePaidLeaveFixtureUrl(process.env.SKO_PAID_LEAVE_FIXTURE_URL)});
 await db.connect();db.exec=q=>db.query(q);db.close=()=>db.end();
 assert.equal(Math.floor(Number((await db.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 assert.equal((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth','storage') and c.relkind in ('r','v','m')")).rows[0].n,0,'Only empty disposable fixture accepted');
} else {
 const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
 db=new PGlite();
}
const company='10000000-0000-0000-0000-000000000001';
const worker='10000000-0000-0000-0000-000000000002';
const requirement='10000000-0000-0000-0000-000000000003';
const user='10000000-0000-0000-0000-000000000004';
const prefix=`${company}/${worker}/${requirement}/own-upload`;
const first=`${prefix}/front.jpg`,second=`${prefix}/back.jpg`,third=`${prefix}/extra.jpg`;
try {
 await db.exec(`create schema auth;create schema private;create schema storage;
 create role anon;create role authenticated;create role service_role;
 create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.uid',true),'')::uuid$$;
 create table public.companies(id uuid primary key);
 create table public.company_members(company_id uuid,user_id uuid);
 create table public.worker_document_statuses(id uuid primary key default gen_random_uuid(),company_id uuid,
 worker_id uuid,requirement_id uuid,status text,expires_at date,original_verified boolean default false,
 attachment_path text,notes text,updated_by uuid);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
 alter table storage.objects enable row level security;
 create policy fixture_read on storage.objects for select to authenticated using(true);
 create policy fixture_delete on storage.objects for delete to authenticated using(true);
 create policy fixture_update on storage.objects for update to authenticated using(true) with check(true);
 grant usage on schema auth,private,storage to authenticated;
 grant select,delete,update on storage.objects to authenticated;
 insert into public.companies values('${company}');
 insert into auth.users values('${user}');
 insert into public.company_members values('${company}','${user}');
 select set_config('fixture.uid','${user}',false);`);
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20260918144500_add_worker_document_status_history.sql'),'utf8'));
 await db.exec(`insert into public.worker_document_statuses(company_id,worker_id,requirement_id,status,attachment_path)
 values('${company}','${worker}','${requirement}','submitted','${first}')`);
 // Model a legacy row created before audit history existed.
 await db.exec('delete from public.worker_document_status_history');
 const original=(await db.query('select attachment_path from public.worker_document_statuses')).rows;
 const originalHistory=(await db.query('select attachment_path from public.worker_document_status_history')).rows;
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261010222524_worker_document_multiple_photos.sql'),'utf8'));
 assert.deepEqual((await db.query('select attachment_path from public.worker_document_statuses')).rows,original);
 assert.deepEqual((await db.query('select attachment_path from public.worker_document_status_history')).rows,originalHistory);
 assert.deepEqual((await db.query('select attachment_paths from public.worker_document_statuses')).rows[0].attachment_paths,[]);
 await db.exec("update public.worker_document_statuses set notes='metadata only'");
 assert.deepEqual((await db.query('select attachment_paths from public.worker_document_statuses')).rows[0].attachment_paths,[first]);
 assert.ok((await db.query('select attachment_path,attachment_paths from public.worker_document_status_history')).rows.some(r=>r.attachment_path===first && r.attachment_paths.length===0),'Unaudited original baseline retained');
 await db.exec(`update public.worker_document_statuses set attachment_paths=array['${first}','${second}','${third}']`);
 const row=(await db.query('select attachment_path,attachment_paths from public.worker_document_statuses')).rows[0];
 assert.equal(row.attachment_path,first);assert.deepEqual(row.attachment_paths,[first,second,third]);
 assert.ok((await db.query('select attachment_paths from public.worker_document_status_history')).rows.some(r=>r.attachment_paths.length===3));
 await db.exec(`update public.worker_document_statuses set attachment_paths=array['${third}','${first}'],attachment_path='${third}'`);
 // Removed back photo remains held by immutable history.
 assert.equal((await db.query(`select private.worker_document_photos_are_retained('${second}') held`)).rows[0].held,true);
 await db.exec(`insert into storage.objects(bucket_id,name) values('worker-documents','${second}')`);
 await db.exec('set role authenticated');
 await db.exec(`delete from storage.objects where name='${second}'`);
 assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,1);
 await db.exec(`update storage.objects set name='replacement.jpg' where name='${second}'`);
 assert.equal((await db.query('select name from storage.objects')).rows[0].name,second);
 await db.exec('reset role');
 for (const paths of [`array['${first}','${first}']`,`array[null]::text[]`,`array['foreign/company/worker/slot/photo.jpg']`]) {
  await assert.rejects(db.exec(`update public.worker_document_statuses set attachment_paths=${paths}`),e=>e.code==='22023');
 }
 await db.exec(`update public.worker_document_statuses set attachment_path='${second}'`);
 assert.deepEqual((await db.query('select attachment_paths from public.worker_document_statuses')).rows[0].attachment_paths,[second]);
 await db.exec('update public.worker_document_statuses set attachment_path=null,attachment_paths=array[]::text[]');
 assert.equal((await db.query('select attachment_path from public.worker_document_statuses')).rows[0].attachment_path,null);
 assert.equal((await db.query(`select private.worker_document_photos_are_retained('${third}') held`)).rows[0].held,true);
 console.log('PASS: preserved legacy rows, metadata normalization, all-photo audit, scope/duplicates, remove/reorder, history DELETE/UPDATE protection');
} finally {await db.close();}
