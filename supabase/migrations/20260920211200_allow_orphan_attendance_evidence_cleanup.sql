drop policy if exists "attendance_evidence_delete" on storage.objects;

create policy "attendance_evidence_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'attendance-evidence'
  and (
    private.has_company_feature(
      private.try_uuid(split_part(name, '/', 1)),
      'can_manage_attendance'
    )
    or (
      exists (
        select 1
        from public.workers w
        where w.id = private.try_uuid(split_part(storage.objects.name, '/', 4))
          and w.company_id = private.try_uuid(split_part(storage.objects.name, '/', 1))
          and w.user_id = auth.uid()
      )
      and not exists (
        select 1
        from public.attendance_verifications av
        where av.photo_storage_path = storage.objects.name
      )
    )
  )
);
