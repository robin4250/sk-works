create table if not exists public.communication_notes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  group_id uuid not null references public.communication_groups(id) on delete cascade,
  title text not null,
  body text,
  is_pinned boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists communication_notes_company_id_idx
  on public.communication_notes(company_id);
create index if not exists communication_notes_group_id_idx
  on public.communication_notes(group_id);
create index if not exists communication_notes_group_pinned_created_idx
  on public.communication_notes(group_id, is_pinned desc, created_at desc);

alter table public.communication_notes enable row level security;

create policy "company members can manage communication notes"
on public.communication_notes
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = communication_notes.company_id
      and cm.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = communication_notes.company_id
      and cm.user_id = auth.uid()
  )
  and exists (
    select 1 from public.communication_groups cg
    where cg.id = communication_notes.group_id
      and cg.company_id = communication_notes.company_id
  )
);
