alter table public.communication_messages
  add column if not exists external_sender_id text;

create index if not exists communication_messages_external_sender_idx
  on public.communication_messages(company_id, origin, external_sender_id)
  where external_sender_id is not null;

create table if not exists public.line_group_bindings (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  communication_group_id uuid not null references public.communication_groups(id) on delete cascade,
  line_group_id text not null,
  display_name text,
  is_enabled boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (communication_group_id),
  unique (line_group_id)
);

create index if not exists line_group_bindings_company_idx
  on public.line_group_bindings(company_id, is_enabled);

alter table public.line_group_bindings enable row level security;

create policy "company members can read line group bindings"
on public.line_group_bindings
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = line_group_bindings.company_id
      and cm.user_id = auth.uid()
  )
  and exists (
    select 1 from public.communication_groups cg
    where cg.id = line_group_bindings.communication_group_id
      and cg.company_id = line_group_bindings.company_id
  )
);

-- Writes intentionally remain service-role/admin-only in the first bridge release.
-- This prevents ordinary authenticated members from rebinding a LINE group to a
-- different SKO communication group before a dedicated admin UI/role policy exists.
