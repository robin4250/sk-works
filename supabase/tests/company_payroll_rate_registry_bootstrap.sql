-- Synthetic prerequisites only. Never execute this bootstrap against a linked DB.
create role anon;
create role authenticated;
create schema auth;
create schema private;
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('test.actor',true),'')::uuid
$$;
create function private.account_access_allowed() returns boolean language sql stable as $$
 select coalesce(current_setting('test.account_allowed',true),'true')='true'
$$;
create table public.companies(id uuid primary key);
create table public.company_members(company_id uuid,user_id uuid,role text);
insert into public.companies values('10000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000001');
insert into public.company_members values
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000011','owner'),
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000012','admin'),
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000013','worker'),
 ('20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000012','admin');
