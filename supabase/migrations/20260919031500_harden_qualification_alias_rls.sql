alter table public.qualification_master_aliases enable row level security;

drop policy if exists "company members can manage qualification aliases"
  on public.qualification_master_aliases;
drop policy if exists "company members can read qualification aliases"
  on public.qualification_master_aliases;
drop policy if exists "owners and admins can manage qualification aliases"
  on public.qualification_master_aliases;

create policy "company members can read qualification aliases"
on public.qualification_master_aliases
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = qualification_master_aliases.company_id
      and cm.user_id = auth.uid()
  )
);

create policy "owners and admins can manage qualification aliases"
on public.qualification_master_aliases
for all
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = qualification_master_aliases.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = qualification_master_aliases.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin')
  )
  and exists (
    select 1
    from public.qualification_master qm
    where qm.id = qualification_master_aliases.qualification_master_id
      and qm.company_id = qualification_master_aliases.company_id
  )
);
