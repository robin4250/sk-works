drop policy if exists "worker can register own qualification"
  on public.worker_qualifications;

create policy "worker can register own qualification"
on public.worker_qualifications
for insert
to authenticated
with check (
  exists (
    select 1
    from public.workers w
    join public.company_members cm
      on cm.company_id = w.company_id
     and cm.user_id = (select auth.uid())
    where w.id = worker_qualifications.worker_id
      and w.company_id = worker_qualifications.company_id
      and w.user_id = (select auth.uid())
  )
  and exists (
    select 1
    from public.qualification_master qm
    where qm.id = worker_qualifications.qualification_master_id
      and qm.company_id = worker_qualifications.company_id
      and qm.is_active = true
  )
);
