drop policy if exists "company members can read worker document statuses"
  on public.worker_document_statuses;
drop policy if exists "managers can manage worker document statuses"
  on public.worker_document_statuses;

create policy "worker or people manager can read document statuses"
on public.worker_document_statuses
for select
to authenticated
using (
  exists (
    select 1
    from public.workers w
    where w.id = worker_document_statuses.worker_id
      and w.company_id = worker_document_statuses.company_id
      and w.user_id = auth.uid()
  )
  or private.has_company_feature(company_id, 'can_manage_people')
);

create policy "people managers can manage worker document statuses"
on public.worker_document_statuses
for all
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_people')
)
with check (
  private.has_company_feature(company_id, 'can_manage_people')
  and exists (
    select 1 from public.workers w
    where w.id = worker_document_statuses.worker_id
      and w.company_id = worker_document_statuses.company_id
  )
  and exists (
    select 1 from public.document_requirements dr
    where dr.id = worker_document_statuses.requirement_id
      and dr.company_id = worker_document_statuses.company_id
  )
);

drop policy if exists "company members can read worker document status history"
  on public.worker_document_status_history;
create policy "worker or people manager can read document status history"
on public.worker_document_status_history
for select
to authenticated
using (
  exists (
    select 1
    from public.workers w
    where w.id = worker_document_status_history.worker_id
      and w.company_id = worker_document_status_history.company_id
      and w.user_id = auth.uid()
  )
  or private.has_company_feature(company_id, 'can_manage_people')
);

drop policy if exists "company members can read worker qualifications"
  on public.worker_qualifications;
drop policy if exists "managers can manage worker qualifications"
  on public.worker_qualifications;

create policy "worker or people manager can read worker qualifications"
on public.worker_qualifications
for select
to authenticated
using (
  exists (
    select 1
    from public.workers w
    where w.id = worker_qualifications.worker_id
      and w.company_id = worker_qualifications.company_id
      and w.user_id = auth.uid()
  )
  or private.has_company_feature(company_id, 'can_manage_people')
);

create policy "people managers can manage worker qualifications"
on public.worker_qualifications
for all
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_people')
)
with check (
  private.has_company_feature(company_id, 'can_manage_people')
  and exists (
    select 1 from public.workers w
    where w.id = worker_qualifications.worker_id
      and w.company_id = worker_qualifications.company_id
  )
  and exists (
    select 1 from public.qualification_master qm
    where qm.id = worker_qualifications.qualification_master_id
      and qm.company_id = worker_qualifications.company_id
  )
);

drop policy if exists "worker_documents_read" on storage.objects;
drop policy if exists "worker_documents_insert" on storage.objects;
drop policy if exists "worker_documents_update" on storage.objects;
drop policy if exists "worker_documents_delete" on storage.objects;

create policy "worker_documents_read"
on storage.objects for select to authenticated
using (
  bucket_id = 'worker-documents'
  and exists (
    select 1
    from public.workers w
    where w.id = private.try_uuid(split_part(storage.objects.name, '/', 2))
      and w.company_id = private.try_uuid(split_part(storage.objects.name, '/', 1))
      and (
        w.user_id = auth.uid()
        or private.has_company_feature(w.company_id, 'can_manage_people')
      )
  )
);

create policy "worker_documents_insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'worker-documents'
  and private.has_company_feature(
    private.try_uuid(split_part(name, '/', 1)),
    'can_manage_people'
  )
);

create policy "worker_documents_update"
on storage.objects for update to authenticated
using (
  bucket_id = 'worker-documents'
  and private.has_company_feature(
    private.try_uuid(split_part(name, '/', 1)),
    'can_manage_people'
  )
)
with check (
  bucket_id = 'worker-documents'
  and private.has_company_feature(
    private.try_uuid(split_part(name, '/', 1)),
    'can_manage_people'
  )
);

create policy "worker_documents_delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'worker-documents'
  and private.has_company_feature(
    private.try_uuid(split_part(name, '/', 1)),
    'can_manage_people'
  )
);

drop policy if exists "qualification_certificates_read" on storage.objects;
drop policy if exists "qualification_certificates_insert" on storage.objects;
drop policy if exists "qualification_certificates_update" on storage.objects;
drop policy if exists "qualification_certificates_delete" on storage.objects;

create policy "qualification_certificates_read"
on storage.objects for select to authenticated
using (
  bucket_id = 'qualification-certificates'
  and exists (
    select 1
    from public.workers w
    where w.id = private.try_uuid(split_part(storage.objects.name, '/', 2))
      and w.company_id = private.try_uuid(split_part(storage.objects.name, '/', 1))
      and (
        w.user_id = auth.uid()
        or private.has_company_feature(w.company_id, 'can_manage_people')
      )
  )
);

create policy "qualification_certificates_insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'qualification-certificates'
  and private.has_company_feature(
    private.try_uuid(split_part(name, '/', 1)),
    'can_manage_people'
  )
);

create policy "qualification_certificates_update"
on storage.objects for update to authenticated
using (
  bucket_id = 'qualification-certificates'
  and private.has_company_feature(
    private.try_uuid(split_part(name, '/', 1)),
    'can_manage_people'
  )
)
with check (
  bucket_id = 'qualification-certificates'
  and private.has_company_feature(
    private.try_uuid(split_part(name, '/', 1)),
    'can_manage_people'
  )
);

create policy "qualification_certificates_delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'qualification-certificates'
  and private.has_company_feature(
    private.try_uuid(split_part(name, '/', 1)),
    'can_manage_people'
  )
);
