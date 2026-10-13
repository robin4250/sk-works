create role anon;create role authenticated;create role service_role;
create schema private;create schema auth;create schema storage;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create table public.companies(id uuid primary key);
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.company_approval_assignees(company_id uuid,user_id uuid);
create table public.workers(id uuid primary key,company_id uuid,user_id uuid,name text);
create table public.qualification_master(id uuid primary key,company_id uuid,name text,expiry_required boolean default false);
create table public.worker_qualifications(
 id uuid primary key,company_id uuid not null,worker_id uuid not null,qualification_master_id uuid not null,
 certificate_number text,issuer text,issued_at date,expires_at date,attachment_path text,attachment_back_path text,
 notes text,updated_at timestamptz default now()
);
alter table public.worker_qualifications enable row level security;
create policy own_read on public.worker_qualifications for select to authenticated
 using(exists(select 1 from public.workers w where w.id=worker_id and w.company_id=worker_qualifications.company_id and w.user_id=auth.uid()));
grant select,update on public.worker_qualifications to authenticated;
grant select on public.workers to authenticated;
create table private.qualification_submissions(
 id uuid primary key default gen_random_uuid(),company_id uuid not null,worker_id uuid not null,
 qualification_master_id uuid not null,target_id uuid not null,certificate_number text,issuer text,
 issued_at date,requested_by uuid,previous jsonb,attachment_path text,upload_path text,notes text,expires_at date,
 status text not null default 'draft' check(status in ('draft','pending','approved','rejected')),
 reason text,created_at timestamptz not null default now(),reviewed_by uuid,reviewed_at timestamptz,
 retained_requested_by uuid,check(num_nonnulls(requested_by,retained_requested_by)=1),
 check(retained_requested_by is null or status in ('approved','rejected'))
);
alter table private.qualification_submissions enable row level security;
revoke all on private.qualification_submissions from public,anon,authenticated;
create table private.document_delivery_items(bucket text,path text);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text not null,name text not null,unique(bucket_id,name));
alter table storage.objects enable row level security;
grant usage on schema private,auth,storage to authenticated;
grant select,insert,update,delete on storage.objects to authenticated;
create policy fixture_update on storage.objects for update to authenticated using(true) with check(true);
create policy fixture_delete on storage.objects for delete to authenticated using(true);
