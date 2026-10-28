-- Disposable GoTrue stack fixtures only; retain real auth.uid/jwt/users/sessions.
create schema private;
create table private.account_deletion_access_restrictions(user_id uuid primary key);
create table private.fixture_master_owners(user_id uuid primary key);
create table private.master_devices(id uuid primary key default gen_random_uuid(),master_user_id uuid not null,
 device_key text not null,device_name text not null,device_type text not null,last_used_at timestamptz,
 platform text,is_locked boolean not null default false,revoked_by uuid,
 revoked_at timestamptz, unique(master_user_id,device_key));
create table public.user_secondary_credentials(user_id uuid primary key,password_hash text,
 failed_attempts int not null default 0,locked_until timestamptz,updated_at timestamptz);
alter table public.user_secondary_credentials enable row level security;
revoke all on public.user_secondary_credentials from public,anon,authenticated;
create function private.account_access_allowed() returns boolean language sql as $$
 select not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid()) $$;
create function private.account_deletion_barrier_key(uuid) returns bigint language sql immutable as $$
 select hashtextextended($1::text,0) $$;
create function public.is_current_user_master_admin() returns boolean language sql security invoker set search_path='' as $$
 select exists(select 1 from private.fixture_master_owners where user_id=auth.uid()) $$;
revoke all on function public.is_current_user_master_admin() from public,anon,authenticated;
revoke all on schema private from public,anon,authenticated;
