create role anon; create role authenticated; create role service_role;
create schema auth; create schema private; create schema extensions;
create extension pgcrypto with schema extensions;
create table auth.users(id uuid primary key,is_anonymous boolean,banned_until timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
create table private.account_deletion_access_restrictions(user_id uuid primary key);
create table private.master_devices(id uuid primary key default gen_random_uuid(),master_user_id uuid not null,
 device_key text not null,device_name text not null,device_type text not null,last_used_at timestamptz,
 platform text,is_locked boolean not null default false,revoked_by uuid,
 revoked_at timestamptz, unique(master_user_id,device_key));
create table private.master_admin_audit_log(actor_user_id uuid,action text,target_user_id uuid,details jsonb);
create table public.user_secondary_credentials(user_id uuid primary key,password_hash text,
 failed_attempts int not null default 0,locked_until timestamptz,updated_at timestamptz);
create function auth.uid() returns uuid language sql as $$
 select nullif(current_setting('test.actor',true),'')::uuid $$;
create function auth.jwt() returns jsonb language sql as $$
 select coalesce(nullif(current_setting('test.jwt',true),'')::jsonb,'{}'::jsonb) $$;
create function private.account_access_allowed() returns boolean language sql as $$
 select not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid()) $$;
create function private.account_deletion_barrier_key(uuid) returns bigint language sql immutable as $$
 select hashtextextended($1::text,0) $$;
create function public.is_current_user_master_admin() returns boolean language sql as $$
 select auth.uid()='00000000-0000-0000-0000-000000000001'::uuid $$;
insert into auth.users values ('00000000-0000-0000-0000-000000000001',false,null),
 ('00000000-0000-0000-0000-000000000009',false,null);
insert into auth.sessions values ('00000000-0000-0000-0000-000000000002',
 '00000000-0000-0000-0000-000000000001',null);
insert into public.user_secondary_credentials(user_id,password_hash) values
 ('00000000-0000-0000-0000-000000000001',extensions.crypt('synthetic-correct',extensions.gen_salt('bf',4)));
select set_config('test.actor','00000000-0000-0000-0000-000000000001',false);
select set_config('test.jwt','{"role":"authenticated","session_id":"00000000-0000-0000-0000-000000000002","is_anonymous":false}',false);
