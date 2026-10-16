-- Disposable application prerequisites only, not a production schema snapshot.
-- Real GoTrue owns auth.users/auth.sessions/auth.uid/auth.jwt/auth.role unchanged.
create schema private;
create table public.companies(id uuid primary key,name text not null,is_active boolean not null default true);
create table public.company_members(company_id uuid references public.companies(id),user_id uuid references auth.users(id),role text not null,primary key(company_id,user_id));
create table private.account_deletion_access_restrictions(user_id uuid primary key references auth.users(id));
-- Minimal fixture deletion barrier/account guard: this does not certify all live
-- account-deletion controls, company RLS, configuration, or business migrations.
create function private.account_deletion_barrier_key(p_actor uuid) returns bigint language sql immutable set search_path='' as $$select hashtextextended('isolated-account:'||p_actor::text,0)$$;
create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())$$;
create table public.user_secondary_credentials(user_id uuid primary key references auth.users(id),password_hash text not null,failed_attempts integer not null default 0,locked_until timestamptz,updated_at timestamptz);
create table private.master_feature_settings(feature_key text primary key,enabled boolean not null,updated_at timestamptz,updated_by uuid);
create function public.current_master_feature_flags() returns jsonb language sql security definer set search_path='' as $$select coalesce(jsonb_object_agg(feature_key,enabled),'{}'::jsonb) from private.master_feature_settings$$;
revoke all on public.user_secondary_credentials,private.account_deletion_access_restrictions,private.master_feature_settings from public,anon,authenticated,service_role;
grant usage on schema private to service_role;
