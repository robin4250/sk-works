create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid not null,not_after timestamptz);
create function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('role',coalesce(nullif(current_setting('test.role',true),''),'authenticated'),'is_anonymous',coalesce(nullif(current_setting('test.anonymous',true),''),'false'),'session_id',coalesce(nullif(current_setting('test.session',true),''),'40000000-0000-0000-0000-000000000001'))$$;
create function private.account_deletion_barrier_key(uuid) returns bigint language sql immutable as $$ select hashtextextended($1::text,0) $$;
insert into auth.users(id) values ('20000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000002'),('20000000-0000-0000-0000-000000000003');
insert into auth.sessions(id,user_id) values ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001'),('40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002');
