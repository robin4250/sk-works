-- Harden chat writes before rollout. Company members may read company
-- messages, but ordinary authenticated users may only create/update/delete
-- their own SKO-origin messages. LINE/import rows remain service-role managed.

alter table public.chat_messages enable row level security;

drop policy if exists "company members can manage chat messages"
  on public.chat_messages;
drop policy if exists "company members can send sko chat messages"
  on public.chat_messages;
drop policy if exists "authors can update own sko chat messages"
  on public.chat_messages;
drop policy if exists "authors can delete own sko chat messages"
  on public.chat_messages;

create policy "company members can send sko chat messages"
on public.chat_messages
for insert
to authenticated
with check (
  origin = 'sk_works'
  and sender_user_id = auth.uid()
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = chat_messages.company_id
      and cm.user_id = auth.uid()
  )
  and exists (
    select 1
    from public.communication_groups cg
    where cg.id = chat_messages.communication_group_id
      and cg.company_id = chat_messages.company_id
  )
);

create policy "authors can update own sko chat messages"
on public.chat_messages
for update
to authenticated
using (
  origin = 'sk_works'
  and sender_user_id = auth.uid()
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = chat_messages.company_id
      and cm.user_id = auth.uid()
  )
)
with check (
  origin = 'sk_works'
  and sender_user_id = auth.uid()
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = chat_messages.company_id
      and cm.user_id = auth.uid()
  )
  and exists (
    select 1
    from public.communication_groups cg
    where cg.id = chat_messages.communication_group_id
      and cg.company_id = chat_messages.company_id
  )
);

create policy "authors can delete own sko chat messages"
on public.chat_messages
for delete
to authenticated
using (
  origin = 'sk_works'
  and sender_user_id = auth.uid()
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = chat_messages.company_id
      and cm.user_id = auth.uid()
  )
);
