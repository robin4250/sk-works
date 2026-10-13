drop policy if exists "communication_albums_read" on storage.objects;
drop policy if exists "communication_albums_insert" on storage.objects;
drop policy if exists "communication_albums_update" on storage.objects;
drop policy if exists "communication_albums_delete" on storage.objects;

create policy "communication_albums_read"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'communication-albums'
  and private.can_access_communication_group(
    private.try_uuid(split_part(name, '/', 2))
  )
);

create policy "communication_albums_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'communication-albums'
  and private.can_access_communication_group(
    private.try_uuid(split_part(name, '/', 2))
  )
);

create policy "communication_albums_update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'communication-albums'
  and private.can_access_communication_group(
    private.try_uuid(split_part(name, '/', 2))
  )
)
with check (
  bucket_id = 'communication-albums'
  and private.can_access_communication_group(
    private.try_uuid(split_part(name, '/', 2))
  )
);

create policy "communication_albums_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'communication-albums'
  and private.can_access_communication_group(
    private.try_uuid(split_part(name, '/', 2))
  )
);
