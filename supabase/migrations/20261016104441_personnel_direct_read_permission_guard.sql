begin;
set local lock_timeout='5s';
-- Match the existing canonical employee-personnel read RPC, including its
-- intentional read-only viewer scope, while retaining employees' own records.
-- No INSERT/UPDATE/DELETE grants, helpers, business rows or payroll are changed.
drop policy "personnel profile read" on public.worker_personnel_profiles;
create policy "personnel profile read" on public.worker_personnel_profiles
for select to authenticated using (
  private.account_access_allowed()
  and exists (
    select 1 from public.workers w
    where w.id=worker_personnel_profiles.worker_id
      and w.company_id=worker_personnel_profiles.company_id
      and (w.user_id=auth.uid()
        or (private.personnel_view_allowed(worker_personnel_profiles.company_id)
          and (w.status::text='active' or exists (
            select 1 from public.company_members m
            where m.company_id=worker_personnel_profiles.company_id
              and m.user_id=auth.uid()
              and m.role::text in ('owner','admin','manager')
          ))))
  )
);
drop policy "worker family members read" on public.worker_family_members;
create policy "worker family members read" on public.worker_family_members
for select to authenticated using (
  private.account_access_allowed()
  and exists (
    select 1 from public.workers w
    where w.id=worker_family_members.worker_id
      and w.company_id=worker_family_members.company_id
      and (w.user_id=auth.uid()
        or (private.personnel_view_allowed(worker_family_members.company_id)
          and (w.status::text='active' or exists (
            select 1 from public.company_members m
            where m.company_id=worker_family_members.company_id
              and m.user_id=auth.uid()
              and m.role::text in ('owner','admin','manager')
          ))))
  )
);
commit;
