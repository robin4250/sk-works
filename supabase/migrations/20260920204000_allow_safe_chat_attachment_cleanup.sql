drop policy if exists "authors can delete own chat attachments"
  on public.chat_attachments;
create policy "authors can delete own chat attachments"
on public.chat_attachments
for delete
to authenticated
using (
  uploaded_by = auth.uid()
  and private.can_access_communication_group(communication_group_id)
);

drop policy if exists "chat_attachments_storage_delete"
  on storage.objects;
create policy "chat_attachments_storage_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'chat-attachments'
  and exists (
    select 1
    from public.chat_attachments ca
    where ca.storage_path = storage.objects.name
      and ca.uploaded_by = auth.uid()
      and private.can_access_communication_group(ca.communication_group_id)
  )
);
