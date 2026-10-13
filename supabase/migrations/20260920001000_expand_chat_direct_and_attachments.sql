alter table public.communication_groups
  add column if not exists last_activity_at timestamptz not null default now();

create table if not exists public.communication_group_members (
  group_id uuid not null references public.communication_groups(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key(group_id, user_id)
);

create index if not exists communication_group_members_user_idx
  on public.communication_group_members(user_id, group_id);

alter table public.communication_group_members enable row level security;

drop policy if exists "company members can read communication group members"
  on public.communication_group_members;
create policy "company members can read communication group members"
on public.communication_group_members
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = communication_group_members.company_id
      and cm.user_id = auth.uid()
  )
);

create table if not exists public.chat_attachments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  communication_group_id uuid not null references public.communication_groups(id) on delete cascade,
  message_id uuid references public.chat_messages(id) on delete cascade,
  storage_path text not null,
  original_filename text not null,
  mime_type text,
  attachment_type text not null default 'file'
    check (attachment_type in ('image','file')),
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists chat_attachments_group_created_idx
  on public.chat_attachments(communication_group_id, created_at);

alter table public.chat_attachments enable row level security;

drop policy if exists "company members can read chat attachments"
  on public.chat_attachments;
create policy "company members can read chat attachments"
on public.chat_attachments
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = chat_attachments.company_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "company members can insert chat attachments"
  on public.chat_attachments;
create policy "company members can insert chat attachments"
on public.chat_attachments
for insert
to authenticated
with check (
  uploaded_by = auth.uid()
  and exists (
    select 1 from public.company_members cm
    where cm.company_id = chat_attachments.company_id
      and cm.user_id = auth.uid()
  )
);

insert into storage.buckets (id, name, public)
values ('chat-attachments', 'chat-attachments', false)
on conflict (id) do update set public = false;

drop policy if exists "chat_attachments_storage_read" on storage.objects;
create policy "chat_attachments_storage_read"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'chat-attachments'
  and exists (
    select 1
    from public.company_members me
    where me.user_id = auth.uid()
      and me.company_id::text = split_part(name, '/', 1)
  )
);

drop policy if exists "chat_attachments_storage_insert" on storage.objects;
create policy "chat_attachments_storage_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'chat-attachments'
  and exists (
    select 1
    from public.company_members me
    where me.user_id = auth.uid()
      and me.company_id::text = split_part(name, '/', 1)
  )
);

create or replace function public.start_direct_chat(p_other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_other_name text;
  v_group_id uuid;
  v_pair_key text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_other_user_id = v_user_id then
    raise exception 'cannot start a direct chat with yourself';
  end if;

  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null then
    raise exception 'company membership not found';
  end if;

  if not exists (
    select 1
    from public.company_members cm
    where cm.company_id = v_company_id
      and cm.user_id = p_other_user_id
  ) then
    raise exception 'target user is not in the same company';
  end if;

  select coalesce(up.display_name, 'メンバー')
  into v_other_name
  from public.user_profiles up
  where up.user_id = p_other_user_id;

  v_pair_key := case
    when v_user_id::text < p_other_user_id::text
      then v_user_id::text || ':' || p_other_user_id::text
    else p_other_user_id::text || ':' || v_user_id::text
  end;

  select cg.id
  into v_group_id
  from public.communication_groups cg
  where cg.company_id = v_company_id
    and cg.group_type = 'direct'
    and cg.name = 'direct:' || v_pair_key
  limit 1;

  if v_group_id is null then
    insert into public.communication_groups(
      company_id,
      site_id,
      name,
      group_type,
      last_activity_at
    )
    values(
      v_company_id,
      null,
      'direct:' || v_pair_key,
      'direct',
      now()
    )
    returning id into v_group_id;

    insert into public.communication_group_members(
      group_id, company_id, user_id
    )
    values
      (v_group_id, v_company_id, v_user_id),
      (v_group_id, v_company_id, p_other_user_id)
    on conflict do nothing;
  end if;

  return v_group_id;
end;
$$;

revoke execute on function public.start_direct_chat(uuid) from public, anon;
grant execute on function public.start_direct_chat(uuid) to authenticated;

create or replace function public.touch_communication_group()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.communication_groups
  set last_activity_at = coalesce(new.sent_at, now())
  where id = new.communication_group_id;
  return new;
end;
$$;

drop trigger if exists touch_communication_group_after_message
  on public.chat_messages;
create trigger touch_communication_group_after_message
after insert on public.chat_messages
for each row execute function public.touch_communication_group();
