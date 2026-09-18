insert into storage.buckets (id, name, public)
values ('qualification-certificates', 'qualification-certificates', false)
on conflict (id) do update set public = false;

create policy "qualification_certificates_read"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'qualification-certificates'
  and private.has_storage_company_access(name)
);

create policy "qualification_certificates_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'qualification-certificates'
  and private.has_storage_company_access(name)
);

create policy "qualification_certificates_update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'qualification-certificates'
  and private.has_storage_company_access(name)
)
with check (
  bucket_id = 'qualification-certificates'
  and private.has_storage_company_access(name)
);

create policy "qualification_certificates_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'qualification-certificates'
  and private.has_storage_company_access(name)
);
