insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'vehicle-documents',
  'vehicle-documents',
  false,
  52428800,
  array['application/pdf','image/jpeg','image/png','image/heic','image/heif']
)
on conflict(id) do update
set public=false,
    file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "vehicle documents read" on storage.objects;
create policy "vehicle documents read"
on storage.objects for select
using (
  bucket_id='vehicle-documents'
  and private.can_manage_vehicle_routes(
    private.try_uuid(split_part(name,'/',1)),
    'vehicle'
  )
);

drop policy if exists "vehicle documents insert" on storage.objects;
create policy "vehicle documents insert"
on storage.objects for insert
with check (
  bucket_id='vehicle-documents'
  and private.can_manage_vehicle_routes(
    private.try_uuid(split_part(name,'/',1)),
    'vehicle'
  )
);

drop policy if exists "vehicle documents update" on storage.objects;
create policy "vehicle documents update"
on storage.objects for update
using (
  bucket_id='vehicle-documents'
  and private.can_manage_vehicle_routes(
    private.try_uuid(split_part(name,'/',1)),
    'vehicle'
  )
)
with check (
  bucket_id='vehicle-documents'
  and private.can_manage_vehicle_routes(
    private.try_uuid(split_part(name,'/',1)),
    'vehicle'
  )
);

drop policy if exists "vehicle documents delete" on storage.objects;
create policy "vehicle documents delete"
on storage.objects for delete
using (
  bucket_id='vehicle-documents'
  and private.can_manage_vehicle_routes(
    private.try_uuid(split_part(name,'/',1)),
    'vehicle'
  )
);
