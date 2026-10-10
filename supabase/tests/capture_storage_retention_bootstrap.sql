-- All policies/functions/tables here exist only in the in-memory test database.
create role authenticated;
create schema auth; create schema private; create schema storage;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.actor',true),'')::uuid $$;
create function private.try_uuid(text) returns uuid language plpgsql as $$ begin return $1::uuid; exception when invalid_text_representation then return null; end $$;
create table public.workers(id uuid,company_id uuid,user_id uuid);
insert into public.workers values('10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000099');
create function private.has_company_feature(uuid,text) returns boolean language sql as $$ select $1='10000000-0000-0000-0000-000000000001'::uuid and auth.uid()='10000000-0000-0000-0000-000000000002'::uuid and $2='can_manage_attendance' $$;
create table public.attendance_verifications(photo_storage_path text);
create table private.fixture_archive(photo_storage_path text);
create table storage.objects(bucket_id text,name text);
alter table storage.objects enable row level security;
grant usage on schema storage,private,auth,public to authenticated;
grant select,delete on storage.objects to authenticated;
grant select on public.workers,public.attendance_verifications to authenticated;
-- This lookup is fixture-only: the role cannot query archive directly. An error
-- propagates; do not treat an inaccessible archive as an empty archive.
create function private.fixture_archive_referenced(text) returns boolean language plpgsql security definer set search_path='' as $$ begin
 if current_setting('test.archive_read_failure',true)='true' then raise exception 'synthetic archive lookup unavailable'; end if;
 return exists(select 1 from private.fixture_archive a where a.photo_storage_path=$1);
end $$;
revoke all on function private.fixture_archive_referenced(text) from public;
grant execute on function private.fixture_archive_referenced(text) to authenticated;
