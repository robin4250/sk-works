alter table public.document_requirements enable row level security;
alter table public.worker_document_statuses enable row level security;

drop policy if exists "company members can manage document requirements"
  on public.document_requirements;
drop policy if exists "company members can read document requirements"
  on public.document_requirements;
drop policy if exists "owners and admins can manage document requirements"
  on public.document_requirements;

create policy "company members can read document requirements"
on public.document_requirements
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = document_requirements.company_id
      and cm.user_id = auth.uid()
  )
);

create policy "owners and admins can manage document requirements"
on public.document_requirements
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = document_requirements.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = document_requirements.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin')
  )
);

drop policy if exists "company members can manage worker document statuses"
  on public.worker_document_statuses;
drop policy if exists "company members can read worker document statuses"
  on public.worker_document_statuses;
drop policy if exists "managers can manage worker document statuses"
  on public.worker_document_statuses;

create policy "company members can read worker document statuses"
on public.worker_document_statuses
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = worker_document_statuses.company_id
      and cm.user_id = auth.uid()
  )
);

create policy "managers can manage worker document statuses"
on public.worker_document_statuses
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = worker_document_statuses.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin', 'manager')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = worker_document_statuses.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin', 'manager')
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
