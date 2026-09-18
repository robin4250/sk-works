-- Master-data tables are readable by company members, while mutations are
-- restricted to owner/admin/manager roles.

alter table public.workers enable row level security;
alter table public.partner_companies enable row level security;
alter table public.sites enable row level security;
alter table public.site_worker_assignments enable row level security;

drop policy if exists "workers_company_access" on public.workers;
drop policy if exists "company members can read workers" on public.workers;
drop policy if exists "managers can manage workers" on public.workers;
create policy "company members can read workers"
on public.workers for select to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = workers.company_id
      and cm.user_id = auth.uid()
  )
);
create policy "managers can manage workers"
on public.workers for all to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = workers.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = workers.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
);

drop policy if exists "partner_companies_company_access" on public.partner_companies;
drop policy if exists "company members can read partner companies" on public.partner_companies;
drop policy if exists "managers can manage partner companies" on public.partner_companies;
create policy "company members can read partner companies"
on public.partner_companies for select to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = partner_companies.company_id
      and cm.user_id = auth.uid()
  )
);
create policy "managers can manage partner companies"
on public.partner_companies for all to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = partner_companies.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = partner_companies.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
);

drop policy if exists "sites_company_access" on public.sites;
drop policy if exists "company members can read sites" on public.sites;
drop policy if exists "managers can manage sites" on public.sites;
create policy "company members can read sites"
on public.sites for select to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = sites.company_id
      and cm.user_id = auth.uid()
  )
);
create policy "managers can manage sites"
on public.sites for all to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = sites.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = sites.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
);

drop policy if exists "site_worker_assignments_company_access"
  on public.site_worker_assignments;
drop policy if exists "company members can read site worker assignments"
  on public.site_worker_assignments;
drop policy if exists "managers can manage site worker assignments"
  on public.site_worker_assignments;
create policy "company members can read site worker assignments"
on public.site_worker_assignments for select to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = site_worker_assignments.company_id
      and cm.user_id = auth.uid()
  )
);
create policy "managers can manage site worker assignments"
on public.site_worker_assignments for all to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = site_worker_assignments.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = site_worker_assignments.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
  and exists (
    select 1 from public.workers w
    where w.id = site_worker_assignments.worker_id
      and w.company_id = site_worker_assignments.company_id
  )
  and exists (
    select 1 from public.sites s
    where s.id = site_worker_assignments.site_id
      and s.company_id = site_worker_assignments.company_id
  )
);
