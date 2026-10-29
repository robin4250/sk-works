-- Disposable real GoTrue/Native PG harness only. Keep actual auth tables/functions.
-- No registration API: protected byte descriptor records are synthetic test seeds.
create schema private;
create table private.account_deletion_access_restrictions(user_id uuid primary key);
create table private.master_admins(user_id uuid primary key,enabled boolean not null);
create table public.company_members(company_id uuid,user_id uuid,role text,primary key(company_id,user_id));
create table public.user_secondary_credentials(user_id uuid primary key,password_hash text,
 failed_attempts integer default 0,locked_until timestamptz,updated_at timestamptz);
alter table public.company_members enable row level security;
alter table public.user_secondary_credentials enable row level security;
revoke all on public.company_members,public.user_secondary_credentials from public,anon,authenticated,service_role;
revoke all on schema private from public,anon,authenticated,service_role;
create function private.account_deletion_barrier_key(p uuid)returns bigint language sql immutable
as $$select hashtextextended(p::text,781)$$;
