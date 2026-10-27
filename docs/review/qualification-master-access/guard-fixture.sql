\set ON_ERROR_STOP on
create role authenticated nologin;
create schema auth; create schema private;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.qualification_master(id uuid primary key,company_id uuid not null,category text);
create table public.worker_qualifications(id uuid primary key,qualification_master_id uuid references public.qualification_master(id) on delete restrict);
create table public.qualification_master_aliases(id uuid primary key,qualification_master_id uuid references public.qualification_master(id) on delete cascade);
create table private.qualification_submissions(id uuid primary key,qualification_master_id uuid references public.qualification_master(id));
alter table public.qualification_master enable row level security;
create policy read_member on public.qualification_master for select to authenticated using (exists(select 1 from public.company_members cm where cm.company_id=qualification_master.company_id and cm.user_id=auth.uid()));
create policy admin_all on public.qualification_master for all to authenticated using(exists(select 1 from public.company_members cm where cm.company_id=qualification_master.company_id and cm.user_id=auth.uid() and cm.role in ('owner','admin'))) with check(exists(select 1 from public.company_members cm where cm.company_id=qualification_master.company_id and cm.user_id=auth.uid() and cm.role in ('owner','admin')));
insert into public.qualification_master values ('00000000-0000-0000-0000-000000000021','00000000-0000-0000-0000-000000000001','synthetic');
insert into public.qualification_master_aliases values ('00000000-0000-0000-0000-000000000031','00000000-0000-0000-0000-000000000021');
