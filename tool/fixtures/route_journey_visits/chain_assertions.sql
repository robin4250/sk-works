-- Run after the existing actual GPS/capture/management regression harness.
reset role;
create schema storage;
grant usage on schema storage to authenticated;
create table storage.buckets(id text primary key,name text,public boolean);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
alter table storage.objects enable row level security;
grant select,insert,update,delete on storage.objects to authenticated;
alter table workers add primary key(id);
alter table route_stops add column site_id uuid;
alter table route_stops add column stop_order integer not null default 1;

create or replace function private.try_uuid(p text) returns uuid language plpgsql immutable as $$begin return p::uuid; exception when invalid_text_representation then return null; end$$;
