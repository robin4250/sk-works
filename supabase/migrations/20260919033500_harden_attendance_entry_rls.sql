alter table public.attendance_entries enable row level security;

drop policy if exists "attendance_entries_company_access"
  on public.attendance_entries;
drop policy if exists "company members can read attendance entries"
  on public.attendance_entries;
drop policy if exists "managers can manage attendance entries"
  on public.attendance_entries;

create policy "company members can read attendance entries"
on public.attendance_entries
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = attendance_entries.company_id
      and cm.user_id = auth.uid()
  )
);

create policy "managers can manage attendance entries"
on public.attendance_entries
for all
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = attendance_entries.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin', 'manager')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = attendance_entries.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin', 'manager')
  )
  and exists (
    select 1
    from public.workers w
    where w.id = attendance_entries.worker_id
      and w.company_id = attendance_entries.company_id
  )
  and exists (
    select 1
    from public.sites s
    where s.id = attendance_entries.site_id
      and s.company_id = attendance_entries.company_id
  )
);
