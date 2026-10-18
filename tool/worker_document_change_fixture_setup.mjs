// Shared synthetic foundations; no production connection, user or object data.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
export const uid=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
export const [company,worker,requirement,owner,reviewer,outsider,target]=[1,2,3,4,5,6,7].map(uid);
export const photo=`${company}/${worker}/${requirement}/own-upload/front.jpg`;
const source=name=>fs.readFileSync(path.join(root,name),'utf8');
export async function setupWorkerDocumentChangeFixture(db,{applyCandidate=true}={}) {
 await db.exec(`create schema auth;create schema private;create schema storage;
 create role anon;create role authenticated;create role service_role;
 create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.uid',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql stable as $$select coalesce(current_setting('fixture.blocked',true),'')<>'yes'$$;
 create table public.companies(id uuid primary key);
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.company_approval_assignees(company_id uuid,user_id uuid);
 create table public.workers(id uuid primary key,company_id uuid,user_id uuid);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
 alter table storage.objects enable row level security;
 create policy fixture_read on storage.objects for select to authenticated using(true);
 create policy fixture_delete on storage.objects for delete to authenticated using(true);
 create policy fixture_update on storage.objects for update to authenticated using(true) with check(true);
 grant usage on schema auth,private,storage to authenticated;
 grant select,update,delete on storage.objects to authenticated;
 insert into public.companies values('${company}');
 insert into auth.users values('${owner}'),('${reviewer}'),('${outsider}');
 insert into public.company_members values('${company}','${owner}','member'),('${company}','${reviewer}','admin');
 insert into public.workers values('${worker}','${company}','${owner}');`);
 for(const migration of ['20260918133000_add_worker_document_checklist.sql','20260918144500_add_worker_document_status_history.sql','20260919023500_harden_worker_document_rls.sql','20261003121632_allow_self_document_registration.sql','20261010222524_worker_document_multiple_photos.sql']) await db.exec(source(`supabase/migrations/${migration}`));
 await db.exec(`grant select on public.companies,public.company_members,public.workers,public.document_requirements,public.worker_document_status_history to authenticated;
 grant select,insert,update,delete on public.worker_document_statuses to authenticated;
 insert into public.document_requirements(id,company_id,name) values('${requirement}','${company}','Synthetic document');`);
 if(applyCandidate)await db.exec(source('docs/candidates/worker_document_change_20261019.sql.review-only'));
}
