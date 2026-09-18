alter table public.qualification_master enable row level security;
alter table public.worker_qualifications enable row level security;

drop policy if exists "qualification_master_company_access"
  on public.qualification_master;
drop policy if exists "company members can read qualification master"
  on public.qualification_master;
drop policy if exists "owners and admins can manage qualification master"
  on public.qualification_master;

create policy "company members can read qualification master"
on public.qualification_master
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = qualification_master.company_id
      and cm.user_id = auth.uid()
  )
);

create policy "owners and admins can manage qualification master"
on public.qualification_master
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = qualification_master.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = qualification_master.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin')
  )
);

drop policy if exists "worker_qualifications_company_access"
  on public.worker_qualifications;
drop policy if exists "company members can read worker qualifications"
  on public.worker_qualifications;
drop policy if exists "managers can manage worker qualifications"
  on public.worker_qualifications;

create policy "company members can read worker qualifications"
on public.worker_qualifications
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = worker_qualifications.company_id
      and cm.user_id = auth.uid()
  )
);

create policy "managers can manage worker qualifications"
on public.worker_qualifications
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = worker_qualifications.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin', 'manager')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = worker_qualifications.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin', 'manager')
  )
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
