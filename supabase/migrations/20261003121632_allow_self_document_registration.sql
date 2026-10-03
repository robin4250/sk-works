drop policy if exists "worker can insert own document status"
  on public.worker_document_statuses;
drop policy if exists "worker can update own document status"
  on public.worker_document_statuses;

create policy "worker can insert own document status"
on public.worker_document_statuses
for insert
to authenticated
with check (
  exists (
    select 1
    from public.workers w
    join public.company_members cm
      on cm.company_id = w.company_id
     and cm.user_id = (select auth.uid())
    where w.id = worker_document_statuses.worker_id
      and w.company_id = worker_document_statuses.company_id
      and w.user_id = (select auth.uid())
  )
  and exists (
    select 1
    from public.document_requirements dr
    where dr.id = worker_document_statuses.requirement_id
      and dr.company_id = worker_document_statuses.company_id
      and dr.is_active = true
  )
);

create policy "worker can update own document status"
on public.worker_document_statuses
for update
to authenticated
using (
  exists (
    select 1
    from public.workers w
    where w.id = worker_document_statuses.worker_id
      and w.company_id = worker_document_statuses.company_id
      and w.user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.workers w
    where w.id = worker_document_statuses.worker_id
      and w.company_id = worker_document_statuses.company_id
      and w.user_id = (select auth.uid())
  )
  and exists (
    select 1
    from public.document_requirements dr
    where dr.id = worker_document_statuses.requirement_id
      and dr.company_id = worker_document_statuses.company_id
      and dr.is_active = true
  )
);
