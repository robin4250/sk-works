drop policy if exists "attendance_evidence_read" on storage.objects;
drop policy if exists "attendance_evidence_insert" on storage.objects;
drop policy if exists "attendance_evidence_update" on storage.objects;
drop policy if exists "attendance_evidence_delete" on storage.objects;

create policy "attendance_evidence_read"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'attendance-evidence'
  and exists (
    select 1
    from public.workers w
    where w.id = private.try_uuid(split_part(storage.objects.name, '/', 4))
      and w.company_id = private.try_uuid(split_part(storage.objects.name, '/', 1))
      and (
        w.user_id = auth.uid()
        or private.has_company_feature(w.company_id, 'can_manage_attendance')
      )
  )
);

create policy "attendance_evidence_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'attendance-evidence'
  and exists (
    select 1
    from public.workers w
    where w.id = private.try_uuid(split_part(name, '/', 4))
      and w.company_id = private.try_uuid(split_part(name, '/', 1))
      and (
        w.user_id = auth.uid()
        or private.has_company_feature(w.company_id, 'can_manage_attendance')
      )
  )
);

create policy "attendance_evidence_update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'attendance-evidence'
  and private.has_company_feature(
    private.try_uuid(split_part(name, '/', 1)),
    'can_manage_attendance'
  )
)
with check (
  bucket_id = 'attendance-evidence'
  and private.has_company_feature(
    private.try_uuid(split_part(name, '/', 1)),
    'can_manage_attendance'
  )
);

create policy "attendance_evidence_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'attendance-evidence'
  and private.has_company_feature(
    private.try_uuid(split_part(name, '/', 1)),
    'can_manage_attendance'
  )
);
