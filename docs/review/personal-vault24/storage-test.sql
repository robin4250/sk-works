\set ON_ERROR_STOP on
\i docs/review/personal-vault24/catalog-test.sql
create schema storage;
create table storage.objects(bucket_id text,name text,version text);
alter table storage.objects enable row level security;
grant usage on schema storage,auth to authenticated,anon;
grant execute on function auth.uid() to authenticated,anon;
grant select,insert,update,delete on storage.objects to authenticated,anon;
create policy fixture_permissive on storage.objects for all to public using(true) with check(true);
\i docs/review/personal-vault24/storage-access.sql.review-only
set fixture.live='true';set fixture.enabled='false';set fixture.actor='00000000-0000-0000-0000-000000000001';
insert into storage.objects values
('personal-pdf-vault','personal-vault/00000000-0000-0000-0000-000000000001/'||repeat('a',64)||'.pdf','v1'),
('personal-pdf-vault','personal-vault/00000000-0000-0000-0000-000000000001/'||repeat('a',64)||'.pdf','v2'),
('unrelated','fixture-unrelated','v1');
set role authenticated;
do $$begin
 assert (select count(*) from storage.objects where bucket_id='personal-pdf-vault')=1,'owner exact completed version only';
 assert (select count(*) from storage.objects where bucket_id='unrelated')=1,'unrelated unaffected';
 begin insert into storage.objects values('personal-pdf-vault','forged','v1');raise exception 'insert accepted';exception when insufficient_privilege then null;end;
 update storage.objects set version='tampered' where bucket_id='personal-pdf-vault';
 assert (select count(*) from storage.objects where bucket_id='personal-pdf-vault' and version='v1')=1,'no overwrite';
 delete from storage.objects where bucket_id='personal-pdf-vault';
 assert (select count(*) from storage.objects where bucket_id='personal-pdf-vault')=1,'no delete';
end $$;
set fixture.actor='00000000-0000-0000-0000-000000000002';
do $$begin assert (select count(*) from storage.objects where bucket_id='personal-pdf-vault')=0,'foreign user denied';end $$;
set fixture.actor='00000000-0000-0000-0000-000000000001';set fixture.live='false';
do $$begin
 begin perform count(*) from storage.objects where bucket_id='personal-pdf-vault';raise exception 'expired accepted';exception when others then if sqlerrm='expired accepted' then raise;end if;end;
end $$;
reset role;
