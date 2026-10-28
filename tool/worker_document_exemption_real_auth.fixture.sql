-- Synthetic application tables only. auth.uid/auth.jwt/users/sessions remain real.
create schema private;
create table private.account_deletion_access_restrictions(user_id uuid primary key);
create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())
$$;
create function private.account_deletion_barrier_key(uuid) returns bigint language sql immutable set search_path='' as $$select hashtextextended($1::text,765)$$;
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.workers(id uuid primary key,company_id uuid,user_id uuid,status text);
create table public.document_requirements(id uuid primary key,company_id uuid,name text,is_active boolean,is_required boolean,sort_order integer);
create table public.worker_document_statuses(id uuid primary key,company_id uuid,worker_id uuid,requirement_id uuid,status text,attachment_path text);
create table public.worker_private_bank_accounts(worker_id uuid,company_id uuid);
revoke all on public.company_members,public.workers,public.document_requirements,public.worker_document_statuses,public.worker_private_bank_accounts from anon,authenticated;
revoke all on private.account_deletion_access_restrictions from public,anon,authenticated;
grant usage on schema private to authenticated;
