\set ON_ERROR_STOP on
create role anon; create role authenticated; create role service_role;
create schema auth; create schema private;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb$$;
create table auth.users(id uuid primary key,is_anonymous boolean default false,deleted_at timestamptz,banned_until timestamptz);
create table auth.identities(id uuid primary key,user_id uuid references auth.users,provider text,provider_id text,identity_data jsonb,unique(provider,provider_id));
create table public.company_members(user_id uuid,company_id uuid,role text);
create table private.account_deletion_access_restrictions(user_id uuid primary key);
\ir registered-apple-login.sql.review-only
create function public.expect(ok boolean,label text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'failed: %',label;end if;end$$;
insert into auth.users(id) values('00000000-0000-0000-0000-000000000001');
insert into auth.identities values
 ('00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000001','apple','registered','{"sub":"registered","email":"same@example.test"}'),
 ('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000001','google','existing-google','{"sub":"existing-google"}');
insert into company_members values('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000099','owner');
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select expect(resolve_existing_apple_login('registered') is null,'default OFF');
select expect(not has_function_privilege('anon','public.resolve_existing_apple_login(text)','EXECUTE'),'anon denied');
select expect(not has_function_privilege('authenticated','public.consume_existing_apple_login(text,text)','EXECUTE'),'authenticated denied');
select expect(not has_schema_privilege('service_role','apple_existing_login_private','USAGE'),'no service table access');
insert into apple_existing_login_private.rollout values(true,true);
select expect(resolve_existing_apple_login('registered')->>'user_id'='00000000-0000-0000-0000-000000000001','same UID');
select expect(resolve_existing_apple_login('same-email-new-subject') is null,'no email matching');
select expect(consume_existing_apple_login('registered',repeat('a',64)) is not null,'first token');
select expect(consume_existing_apple_login('registered',repeat('a',64)) is null,'replay denied');
select consume_existing_apple_login('registered',repeat(x,64)) from unnest(array['b','c','d','e']) x;
select expect(consume_existing_apple_login('registered',repeat('f',64)) is null,'per user limit');
insert into private.account_deletion_access_restrictions values('00000000-0000-0000-0000-000000000001');
select expect(resolve_existing_apple_login('registered') is null,'restricted denied');
delete from private.account_deletion_access_restrictions;
update auth.users set banned_until=now()+interval '1 day';
select expect(resolve_existing_apple_login('registered') is null,'banned denied');
update auth.users set banned_until=null,is_anonymous=true;
select expect(resolve_existing_apple_login('registered') is null,'anonymous denied');
update auth.users set is_anonymous=false,deleted_at=now();
select expect(resolve_existing_apple_login('registered') is null,'deleted denied');
update auth.users set deleted_at=null;
delete from company_members;
select expect(resolve_existing_apple_login('registered') is null,'no company denied');
select set_config('request.jwt.claims','{"role":"authenticated"}',false);
do $$begin begin perform public.resolve_existing_apple_login('registered');raise exception 'missing claim check';exception when insufficient_privilege then null;end;end$$;
select expect((select count(*)=1 from auth.users),'no account creation');
select expect((select count(*)=2 from auth.identities),'identities preserved');
