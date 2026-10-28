\set ON_ERROR_STOP on
-- Synthetic Auth/session/permission fixture; candidate context SQL is real.
create schema auth;create schema private;create schema qr_attendance_private;
do $$begin
 if not exists(select from pg_roles where rolname='anon')then create role anon;end if;
 if not exists(select from pg_roles where rolname='authenticated')then create role authenticated;end if;
end$$;
create table auth.users(id uuid primary key,deleted_at timestamptz,banned_until timestamptz,is_anonymous boolean default false);
create table auth.sessions(id uuid primary key,user_id uuid references auth.users);
create table public.companies(id uuid primary key);
create table public.company_members(company_id uuid,user_id uuid);
create table public.workers(id uuid primary key,company_id uuid,user_id uuid,status text);
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('fixture.actor',true),'')::uuid$$;
create function private.require_reauthentication_session() returns uuid language plpgsql as $$begin
 if current_setting('fixture.live',true) is distinct from 'yes' then raise sqlstate '42501';end if;
 return nullif(current_setting('fixture.session',true),'')::uuid;end$$;
create function private.has_company_feature(uuid,text) returns boolean language sql as $$select current_setting('fixture.manage',true)='yes'$$;
create function qr_attendance_private.require_enabled() returns void language plpgsql as $$begin
 if current_setting('fixture.qr',true) is distinct from 'yes' then raise sqlstate '42501';end if;end$$;
\ir qr-scanner-context.sql.review-only
insert into auth.users(id) values('00000000-0000-4000-8000-000000000005'),('00000000-0000-4000-8000-000000000008');
insert into auth.sessions values('00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000005');
insert into public.companies values('00000000-0000-4000-8000-000000000001');
insert into public.company_members values('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000005');
insert into public.workers values('00000000-0000-4000-8000-000000000007','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000008','active');
insert into qr_attendance_private.registered_scanners(device_id,company_id,actor_id,public_key_der) values
 ('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000005',decode('302a300506032b6570032100'||repeat('ab',32),'hex'));
select set_config('fixture.actor','00000000-0000-4000-8000-000000000005',false),set_config('fixture.session','00000000-0000-4000-8000-000000000006',false),set_config('fixture.live','yes',false),set_config('fixture.manage','yes',false),set_config('fixture.qr','yes',false);
create function private.try_context(p_company uuid default '00000000-0000-4000-8000-000000000001',p_user uuid default '00000000-0000-4000-8000-000000000008') returns jsonb language sql as $$
 select qr_attendance_private.load_scanner_context(p_company,'00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000007',p_user)
$$;
do $$declare v jsonb;begin
 v:=private.try_context();
 if v->>'actor'<>'00000000-0000-4000-8000-000000000005' or v->>'session'<>'00000000-0000-4000-8000-000000000006' or (v->>'scannerAuthorized')::boolean is distinct from true then raise exception 'context missing';end if;
 begin perform private.try_context('00000000-0000-4000-8000-000000000099');raise exception 'foreign company accepted';exception when insufficient_privilege then null;end;
 begin perform private.try_context(p_user=>'00000000-0000-4000-8000-000000000005');raise exception 'wrong subject accepted';exception when insufficient_privilege then null;end;
 perform set_config('fixture.manage','no',false);
 begin perform private.try_context();raise exception 'unprivileged scanner accepted';exception when insufficient_privilege then null;end;
 perform set_config('fixture.manage','yes',false);perform set_config('fixture.live','no',false);
 begin perform private.try_context();raise exception 'expired accepted';exception when insufficient_privilege then null;end;
 perform set_config('fixture.live','yes',false);
 update qr_attendance_private.registered_scanners set revoked_at=clock_timestamp();
 begin perform private.try_context();raise exception 'revoked accepted';exception when insufficient_privilege then null;end;
 update qr_attendance_private.registered_scanners set revoked_at=null;
 update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id='00000000-0000-4000-8000-000000000008';
 begin perform private.try_context();raise exception 'banned subject accepted';exception when insufficient_privilege then null;end;
 update auth.users set banned_until=null;
 update public.workers set status='inactive';
 begin perform private.try_context();raise exception 'inactive subject accepted';exception when insufficient_privilege then null;end;
 update public.workers set status='active';delete from public.company_members;
 begin perform private.try_context();raise exception 'nonmember accepted';exception when insufficient_privilege then null;end;
 insert into public.company_members values('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000005');
 delete from auth.sessions;
 begin perform private.try_context();raise exception 'deleted session accepted';exception when insufficient_privilege then null;end;
 if has_table_privilege('authenticated','qr_attendance_private.registered_scanners','select') or has_function_privilege('authenticated','qr_attendance_private.load_scanner_context(uuid,uuid,uuid,uuid)','execute') then raise exception 'private context exposed';end if;
end$$;
