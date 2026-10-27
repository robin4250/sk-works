\set ON_ERROR_STOP on
create schema private; create schema auth;
do $$begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon;end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated;end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role;end if;
end $$;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql as $$select coalesce(nullif(current_setting('test.jwt',true),'')::jsonb,'{}')$$;
create table auth.users(id uuid primary key,is_anonymous boolean,banned_until timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
create table private.master_admins(user_id uuid primary key,enabled boolean);
create table private.account_deletion_access_restrictions(user_id uuid primary key);
create table public.company_members(user_id uuid,role text,company_id uuid);
create function private.account_deletion_barrier_key(uuid) returns bigint language sql immutable as $$select hashtextextended($1::text,0)$$;
create function private.account_access_allowed() returns boolean language sql as $$select not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())$$;


create function private.reauthentication_required(text) returns boolean language sql as $$select false$$;
create function private.consume_reauthentication_proof(text,jsonb,text) returns void language plpgsql as $$begin if not public.is_current_user_master_admin() then raise sqlstate '42501';end if;end$$;
create table private.master_feature_settings(feature_key text primary key,enabled boolean not null,updated_at timestamptz,updated_by uuid, constraint master_feature_settings_feature_key_check check(feature_key in('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop')));

\i native-auth-functions.sql
\i extension.sql.review-only
\i operation-guard.sql.review-only
\i change-audit.sql.review-only
