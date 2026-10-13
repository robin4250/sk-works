drop policy if exists "managers can manage document requirements"
  on public.document_requirements;
drop policy if exists "managers can manage worker document statuses"
  on public.worker_document_statuses;

create policy "managers can manage document requirements"
on public.document_requirements
for all
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = document_requirements.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = document_requirements.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
);

create policy "managers can manage worker document statuses"
on public.worker_document_statuses
for all
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = worker_document_statuses.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = worker_document_statuses.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
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