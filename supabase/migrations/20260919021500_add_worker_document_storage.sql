insert into storage.buckets (id, name, public)
values ('worker-documents', 'worker-documents', false)
on conflict (id) do update set public = false;

drop policy if exists "worker_documents_read" on storage.objects;
create policy "worker_documents_read"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'worker-documents'
  and private.has_storage_company_access(name)
);

drop policy if exists "worker_documents_insert" on storage.objects;
create policy "worker_documents_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'worker-documents'
  and private.has_storage_company_access(name)
);

drop policy if exists "worker_documents_update" on storage.objects;
create policy "worker_documents_update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'worker-documents'
  and private.has_storage_company_access(name)
)
with check (
  bucket_id = 'worker-documents'
  and private.has_storage_company_access(name)
);

drop policy if exists "worker_documents_delete" on storage.objects;
create policy "worker_documents_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'worker-documents'
  and private.has_storage_company_access(name)
);
