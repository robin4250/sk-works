\set ON_ERROR_STOP on
create role authenticated nologin;
create schema auth; create schema private;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.qualification_master(id uuid primary key,company_id uuid not null,category text);
create table public.worker_qualifications(id uuid primary key,qualification_master_id uuid references public.qualification_master(id) on delete restrict);
alter table public.qualification_master enable row level security;
grant usage on schema public,auth to authenticated;
grant select on public.company_members to authenticated;
grant select,update,delete on public.qualification_master to authenticated;
create policy read_member on public.qualification_master for select to authenticated using (exists(select 1 from public.company_members cm where cm.company_id=qualification_master.company_id and cm.user_id=auth.uid()));
create policy admin_all on public.qualification_master for all to authenticated using(exists(select 1 from public.company_members cm where cm.company_id=qualification_master.company_id and cm.user_id=auth.uid() and cm.role in ('owner','admin'))) with check(exists(select 1 from public.company_members cm where cm.company_id=qualification_master.company_id and cm.user_id=auth.uid() and cm.role in ('owner','admin')));
insert into public.company_members values ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010','manager'),('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000010','manager'),('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000011','viewer'),('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000012','manager');
insert into public.qualification_master values ('00000000-0000-0000-0000-000000000021','00000000-0000-0000-0000-000000000001','old'),('00000000-0000-0000-0000-000000000022','00000000-0000-0000-0000-000000000001','old');
insert into public.worker_qualifications values ('00000000-0000-0000-0000-000000000031','00000000-0000-0000-0000-000000000021');
\i docs/review/qualification-master-access/policy.sql.review-only
set role authenticated;
select set_config('test.uid','00000000-0000-0000-0000-000000000010',false);
do $$ declare n int; begin update public.qualification_master set category='new' where id='00000000-0000-0000-0000-000000000021'; get diagnostics n=row_count; assert n=1,'manager edit failed'; begin update public.qualification_master set company_id='00000000-0000-0000-0000-000000000002' where id='00000000-0000-0000-0000-000000000021'; raise exception 'cross company move succeeded'; exception when insufficient_privilege then null; end; begin delete from public.qualification_master where id='00000000-0000-0000-0000-000000000021'; raise exception 'used master deleted'; exception when foreign_key_violation then null; end; delete from public.qualification_master where id='00000000-0000-0000-0000-000000000022'; get diagnostics n=row_count; assert n=1,'unused deletion failed'; end $$;
select set_config('test.uid','00000000-0000-0000-0000-000000000011',false);
do $$ declare n int; begin update public.qualification_master set category='bad'; get diagnostics n=row_count; assert n=0,'viewer edit'; delete from public.qualification_master; get diagnostics n=row_count; assert n=0,'viewer delete'; end $$;
select set_config('test.uid','00000000-0000-0000-0000-000000000012',false);
do $$ declare n int; begin update public.qualification_master set category='bad'; get diagnostics n=row_count; assert n=0,'other company edit'; delete from public.qualification_master; get diagnostics n=row_count; assert n=0,'other company delete'; end $$;
reset role;
do $$ begin assert (select category='new' from public.qualification_master where id='00000000-0000-0000-0000-000000000021'); assert (select count(*)=1 from public.worker_qualifications); end $$;
