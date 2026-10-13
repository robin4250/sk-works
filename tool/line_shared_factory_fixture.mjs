import {readFile} from 'node:fs/promises';
export const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
export async function setup(db) {
await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create type public.app_role as enum('owner','admin','employee');
create table companies(id uuid primary key);create table company_members(company_id uuid,user_id uuid,role app_role);
create table communication_groups(id uuid primary key default gen_random_uuid(),company_id uuid,name text,group_type text,participants_only boolean,created_by uuid,last_activity_at timestamptz,archived_at timestamptz);
create table communication_group_members(group_id uuid,company_id uuid,user_id uuid,unique(group_id,user_id));
create table private.line_joined_groups(id uuid primary key,line_group_id text unique,display_name text,joined boolean);
create table line_group_bindings(id uuid default gen_random_uuid(),line_group_id text unique,company_id uuid,communication_group_id uuid,status text,display_name text,updated_at timestamptz);
create table private.line_chat_source_links(group_id uuid,directory_id uuid,company_id uuid,linked_by uuid,unique(group_id,directory_id));
create table line_binding_audit(binding_id uuid,company_id uuid,communication_group_id uuid,line_group_id text,action text,actor_user_id uuid,source text);
create function private.account_access_allowed() returns boolean language sql stable as $$select coalesce(current_setting('test.blocked',true),'')<>'true'$$;
create function public.is_current_user_master_admin() returns boolean language sql stable as $$select auth.uid()='${id(1)}'::uuid$$;
create function private.has_company_role(c uuid,r app_role[]) returns boolean language sql stable as $$select exists(select 1 from public.company_members where company_id=c and user_id=auth.uid() and role=any(r))$$;
create function private.can_access_communication_group(g uuid) returns boolean language sql stable as $$select exists(select 1 from public.communication_group_members where group_id=g and user_id=auth.uid())$$;
create function private.can_edit_custom_chat_photo(g uuid) returns boolean language sql stable as $$select exists(select 1 from public.communication_groups where id=g and created_by=auth.uid())$$;
grant usage on schema public,private,auth to authenticated,anon;
insert into companies values('${id(10)}'),('${id(11)}');insert into company_members values('${id(10)}','${id(1)}','owner'),('${id(11)}','${id(2)}','owner');
insert into private.line_joined_groups values('${id(20)}','source-a','Group A',true),('${id(21)}','source-b','Group B',true),('${id(22)}','source-left','Left',false);
select set_config('test.uid','${id(1)}',false);`);
await db.exec(await readFile(new URL('legacy_factory_prerequisites.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../supabase/migrations/20261013204713_line_shared_group_origins.sql',import.meta.url),'utf8'));
}
