// Shared synthetic foundations; no production connection, user or object data.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
export const uid=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
export const [company,worker,requirement,owner,reviewer,outsider,target]=[1,2,3,4,5,6,7].map(uid);
export const photo=`${company}/${worker}/${requirement}/own-upload/front.jpg`;
const source=name=>fs.readFileSync(path.join(root,name),'utf8');
export async function setupWorkerDocumentChangeFixture(db) {
 await db.exec(`create schema auth;create schema private;create schema storage;
 create role anon;create role authenticated;create role service_role;
 create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz);
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('role','authenticated','is_anonymous',false,'session_id',case when current_setting('fixture.session',true)='live' then current_setting('fixture.uid',true) else null end)$$;
 create function private.account_deletion_barrier_key(uuid) returns bigint language sql immutable as $$select 1::bigint$$;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.uid',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql stable as $$select coalesce(current_setting('fixture.blocked',true),'')<>'yes'$$;
CREATE OR REPLACE FUNCTION private.require_reauthentication_session()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid();sid uuid;
begin
 if actor is null or auth.jwt()->>'role' is distinct from 'authenticated'
  or coalesce(auth.jwt()->>'is_anonymous','false')<>'false'
  or not private.account_access_allowed() then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 begin sid:=(auth.jwt()->>'session_id')::uuid;
 exception when invalid_text_representation then raise sqlstate '42501' using message='reauthentication_required';end;
 if sid is null or not pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(actor)) then
  raise sqlstate '42501' using message='reauthentication_required';end if;
 perform 1 from auth.users where id=actor and not coalesce(is_anonymous,false)
  and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 perform 1 from auth.sessions where id=sid and user_id=actor
  and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 return sid;
end $function$;

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
 insert into auth.users(id) values('${owner}'),('${reviewer}'),('${outsider}');
 insert into auth.sessions(id,user_id) values('${owner}','${owner}'),('${reviewer}','${reviewer}'),('${outsider}','${outsider}');
 insert into public.company_members values('${company}','${owner}','member'),('${company}','${reviewer}','admin');
 insert into public.workers values('${worker}','${company}','${owner}');`);
 for(const migration of ['20260918133000_add_worker_document_checklist.sql','20260918144500_add_worker_document_status_history.sql','20260919023500_harden_worker_document_rls.sql','20261003121632_allow_self_document_registration.sql','20261010222524_worker_document_multiple_photos.sql']) await db.exec(source(`supabase/migrations/${migration}`));
 await db.exec(`grant select on public.companies,public.company_members,public.workers,public.document_requirements,public.worker_document_status_history to authenticated;
 grant select,insert,update,delete on public.worker_document_statuses to authenticated;
 insert into public.document_requirements(id,company_id,name) values('${requirement}','${company}','Synthetic document');`);
 await db.exec(`create table private.document_submissions(
 id uuid primary key default gen_random_uuid(),company_id uuid,worker_id uuid,requirement_id uuid,requested_by uuid,
 previous jsonb,attachment_path text,upload_path text,notes text,expires_at date,status text default 'draft',
 reason text,reviewed_by uuid,reviewed_at timestamptz,created_at timestamptz default now());
 create function private.has_company_feature(uuid,text) returns boolean language sql stable as $$select true$$;`);
 await db.exec(source('docs/review/worker-document-change-live-session/personal-submission-before.sql.review-only'));
 await db.exec(source('docs/review/worker-document-change-live-session/candidate.sql.review-only'));
}
