drop policy if exists company_members_self_read
on public.company_members;

create policy company_members_self_read
on public.company_members
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "company members can read sites"
on public.sites;

create policy "company members can read sites"
on public.sites
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = sites.company_id
      and cm.user_id = (select auth.uid())
  )
);

drop policy if exists "managers can manage sites"
on public.sites;

create policy "managers can manage sites"
on public.sites
for all
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = sites.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = sites.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
);

drop policy if exists "company members can read workers"
on public.workers;

create policy "company members can read workers"
on public.workers
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = workers.company_id
      and cm.user_id = (select auth.uid())
  )
);
