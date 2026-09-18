-- Reconcile historical prototype migrations with the verified production
-- chat / LINE schema. This migration is intentionally additive and idempotent:
-- it does not drop the legacy communication_messages table or rewrite applied
-- migration history.

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  communication_group_id uuid not null references public.communication_groups(id) on delete cascade,
  sender_user_id uuid references auth.users(id) on delete set null,
  sender_display_name text,
  origin text not null default 'sk_works'
    check (origin in ('sk_works', 'line', 'import')),
  body text not null,
  external_event_id text,
  external_message_id text,
  sent_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (origin, external_event_id)
);

create unique index if not exists chat_messages_line_external_event_uidx
  on public.chat_messages(external_event_id)
  where origin = 'line' and external_event_id is not null;

alter table public.chat_messages enable row level security;

drop policy if exists "company members can read chat messages"
  on public.chat_messages;
create policy "company members can read chat messages"
on public.chat_messages
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = chat_messages.company_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "company members can manage chat messages"
  on public.chat_messages;
create policy "company members can manage chat messages"
on public.chat_messages
for all
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = chat_messages.company_id
      and cm.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = chat_messages.company_id
      and cm.user_id = auth.uid()
  )
);

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_messages'
  ) then
    alter publication supabase_realtime add table public.chat_messages;
  end if;
end $$;

-- The historical line_group_bindings migration required company/group IDs and
-- used is_enabled. Production supports an unclaimed pending state, so align a
-- fresh database without deleting the legacy column if it exists.
alter table public.line_group_bindings
  add column if not exists status text not null default 'pending',
  add column if not exists discovered_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

alter table public.line_group_bindings
  alter column company_id drop not null,
  alter column communication_group_id drop not null;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'line_group_bindings'
      and column_name = 'is_enabled'
  ) then
    execute $sql$
      update public.line_group_bindings
      set status = case
        when is_enabled then 'active'
        else 'disabled'
      end
      where status = 'pending'
        and company_id is not null
        and communication_group_id is not null
    $sql$;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.line_group_bindings'::regclass
      and conname = 'line_group_bindings_status_check'
  ) then
    alter table public.line_group_bindings
      add constraint line_group_bindings_status_check
      check (status in ('pending', 'active', 'disabled'));
  end if;
end $$;

alter table public.line_group_bindings enable row level security;

drop policy if exists "company members can read line group bindings"
  on public.line_group_bindings;
drop policy if exists "company members can read line bindings"
  on public.line_group_bindings;
create policy "company members can read line bindings"
on public.line_group_bindings
for select
to authenticated
using (
  company_id is not null
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = line_group_bindings.company_id
      and cm.user_id = auth.uid()
  )
);

-- Keep production's current direct-write behavior at this baseline point.
-- The later secure-claim migration removes this policy and moves activation /
-- disable writes behind owner/admin SECURITY DEFINER RPCs.
drop policy if exists "company members can manage line bindings"
  on public.line_group_bindings;
create policy "company members can manage line bindings"
on public.line_group_bindings
for all
to authenticated
using (
  company_id is not null
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = line_group_bindings.company_id
      and cm.user_id = auth.uid()
  )
)
with check (
  company_id is not null
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = line_group_bindings.company_id
      and cm.user_id = auth.uid()
  )
);

do $
begin
  if to_regclass('public.communication_messages') is not null then
    comment on table public.communication_messages is
      'Legacy prototype chat table. New application code must use public.chat_messages.';
  end if;
end $;
