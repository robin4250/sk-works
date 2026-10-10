-- Synthetic Storage rows/operation helper only, never Storage service byte proof.
create schema storage;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(bucket_id text references storage.buckets(id),name text,primary key(bucket_id,name));
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated,anon;
grant select,insert,update,delete on storage.objects to authenticated,anon;
create function storage.allow_any_operation(expected_operations text[]) returns boolean language sql stable security invoker as $$
 select exists(select 1 from unnest(expected_operations) op
 where (case when left(op,8)='storage.' then substring(op from 9) else op end)=
  (case when left(current_setting('storage.operation',true),8)='storage.' then substring(current_setting('storage.operation',true) from 9) else current_setting('storage.operation',true) end))
$$;
-- Deliberately broad existing permissive policy: dedicated restrictive guards
-- must still deny the new bucket while leaving unrelated bucket access unchanged.
create policy fixture_broad_storage on storage.objects for all to authenticated,anon using(true) with check(true);
insert into storage.buckets values('other-bucket','other-bucket',false,null,null);
