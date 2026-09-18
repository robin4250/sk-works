create table if not exists public.communication_messages (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  group_id uuid not null references public.communication_groups(id) on delete cascade,
  body text not null check (length(btrim(body)) between 1 and 5000),
  origin text not null default 'sko' check (origin in ('sko', 'line', 'import')),
  external_message_id text,
  external_sender_name text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists communication_messages_group_created_idx
  on public.communication_messages(group_id, created_at);
create index if not exists communication_messages_company_created_idx
  on public.communication_messages(company_id, created_at desc);
create unique index if not exists communication_messages_external_unique_idx
  on public.communication_messages(company_id, origin, external_message_id)
  where external_message_id is not null;

alter table public.communication_messages enable row level security;

create policy "company members can read communication messages"
on public.communication_messages
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = communication_messages.company_id
      and cm.user_id = auth.uid()
  )
  and exists (
    select 1 from public.communication_groups cg
    where cg.id = communication_messages.group_id
      and cg.company_id = communication_messages.company_id
  )
);

create policy "company members can send sko messages"
on public.communication_messages
for insert
to authenticated
with check (
  origin = 'sko'
  and created_by = auth.uid()
  and exists (
    select 1 from public.company_members cm
    where cm.company_id = communication_messages.company_id
      and cm.user_id = auth.uid()
  )
  and exists (
    select 1 from public.communication_groups cg
    where cg.id = communication_messages.group_id
      and cg.company_id = communication_messages.company_id
  )
);

create policy "authors can update own sko messages"
on public.communication_messages
for update
to authenticated
using (
  origin = 'sko'
  and created_by = auth.uid()
  and exists (
    select 1 from public.company_members cm
    where cm.company_id = communication_messages.company_id
      and cm.user_id = auth.uid()
  )
)
with check (
  origin = 'sko'
  and created_by = auth.uid()
  and exists (
    select 1 from public.company_members cm
    where cm.company_id = communication_messages.company_id
      and cm.user_id = auth.uid()
  )
  and exists (
    select 1 from public.communication_groups cg
    where cg.id = communication_messages.group_id
      and cg.company_id = communication_messages.company_id
  )
);

create policy "authors can delete own sko messages"
on public.communication_messages
for delete
to authenticated
using (
  origin = 'sko'
  and created_by = auth.uid()
  and exists (
    select 1 from public.company_members cm
    where cm.company_id = communication_messages.company_id
      and cm.user_id = auth.uid()
  )
);

-- Enable Postgres Changes for the chat table when the standard Supabase
-- realtime publication exists. This is guarded so repeated deploys stay safe.
do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'communication_messages'
  ) then
    alter publication supabase_realtime add table public.communication_messages;
  end if;
end $$;
