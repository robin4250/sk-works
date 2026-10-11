-- Preserve the existing upload scope; qualify the object path so workers.name
-- cannot shadow it inside the worker lookup. Leave SELECT/UPDATE/DELETE intact.
alter policy attendance_evidence_insert on storage.objects
with check (
 bucket_id = 'attendance-evidence'
 and exists (
  select 1 from public.workers w
  where w.id = private.try_uuid(split_part(storage.objects.name, '/', 4))
   and w.company_id = private.try_uuid(split_part(storage.objects.name, '/', 1))
   and (w.user_id = auth.uid() or private.has_company_feature(w.company_id, 'can_manage_attendance'))
 )
);
