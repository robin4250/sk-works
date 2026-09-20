create or replace function private.can_access_communication_group(
  p_group_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_group_type text;
  v_role text;
begin
  if v_user_id is null or p_group_id is null then
    return false;
  end if;

  select cg.company_id, cg.group_type
  into v_company_id, v_group_type
  from public.communication_groups cg
  where cg.id = p_group_id;

  if v_company_id is null then
    return false;
  end if;

  select cm.role::text
  into v_role
  from public.company_members cm
  where cm.company_id = v_company_id
    and cm.user_id = v_user_id
  limit 1;

  if v_role is null then
    return false;
  end if;

  if v_group_type = 'direct' then
    return exists (
      select 1
      from public.communication_group_members cgm
      where cgm.group_id = p_group_id
        and cgm.company_id = v_company_id
        and cgm.user_id = v_user_id
    );
  end if;

  if v_group_type = 'partner' then
    if v_role in ('owner', 'admin') then
      return true;
    end if;

    return exists (
      select 1
      from public.member_feature_permissions mfp
      where mfp.company_id = v_company_id
        and mfp.user_id = v_user_id
        and mfp.can_manage_partner_chat = true
    );
  end if;

  return v_group_type in ('company', 'site');
end;
$$;

create or replace function private.can_manage_communication_group(
  p_group_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_group_type text;
  v_role text;
begin
  if v_user_id is null or p_group_id is null then
    return false;
  end if;

  select cg.company_id, cg.group_type
  into v_company_id, v_group_type
  from public.communication_groups cg
  where cg.id = p_group_id;

  if v_company_id is null then
    return false;
  end if;

  select cm.role::text
  into v_role
  from public.company_members cm
  where cm.company_id = v_company_id
    and cm.user_id = v_user_id
  limit 1;

  if v_role in ('owner', 'admin') then
    return true;
  end if;

  if v_group_type in ('company', 'site') and v_role = 'manager' then
    return true;
  end if;

  if v_group_type = 'partner' then
    return exists (
      select 1
      from public.member_feature_permissions mfp
      where mfp.company_id = v_company_id
        and mfp.user_id = v_user_id
        and mfp.can_manage_partner_chat = true
    );
  end if;

  return false;
end;
$$;

create or replace function private.try_uuid(p_value text)
returns uuid
language plpgsql
immutable
as $$
begin
  return p_value::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

-- Communication groups: direct chats are visible only to participants.
drop policy if exists "company members can manage communication groups"
  on public.communication_groups;
drop policy if exists "company members can read communication groups"
  on public.communication_groups;
drop policy if exists "accessible members can read communication groups"
  on public.communication_groups;
drop policy if exists "company members can create non-direct communication groups"
  on public.communication_groups;
drop policy if exists "authorized managers can update communication groups"
  on public.communication_groups;
drop policy if exists "authorized managers can delete communication groups"
  on public.communication_groups;

create policy "accessible members can read communication groups"
on public.communication_groups
for select
to authenticated
using (private.can_access_communication_group(id));

create policy "company members can create non-direct communication groups"
on public.communication_groups
for insert
to authenticated
with check (
  group_type in ('company', 'site')
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = communication_groups.company_id
      and cm.user_id = auth.uid()
  )
);

create policy "authorized managers can update communication groups"
on public.communication_groups
for update
to authenticated
using (private.can_manage_communication_group(id))
with check (private.can_manage_communication_group(id));

create policy "authorized managers can delete communication groups"
on public.communication_groups
for delete
to authenticated
using (private.can_manage_communication_group(id));

-- Direct-chat member rows are visible only when the caller may access that group.
drop policy if exists "company members can read communication group members"
  on public.communication_group_members;
drop policy if exists "accessible members can read communication group members"
  on public.communication_group_members;

create policy "accessible members can read communication group members"
on public.communication_group_members
for select
to authenticated
using (private.can_access_communication_group(group_id));

-- Chat messages inherit the access rules of their communication group.
drop policy if exists "company members can read chat messages"
  on public.chat_messages;
drop policy if exists "company members can send sko chat messages"
  on public.chat_messages;
drop policy if exists "authors can update own sko chat messages"
  on public.chat_messages;
drop policy if exists "authors can delete own sko chat messages"
  on public.chat_messages;

create policy "accessible members can read chat messages"
on public.chat_messages
for select
to authenticated
using (
  private.can_access_communication_group(communication_group_id)
);

create policy "accessible members can send sko chat messages"
on public.chat_messages
for insert
to authenticated
with check (
  origin = 'sk_works'
  and sender_user_id = auth.uid()
  and private.can_access_communication_group(communication_group_id)
);

create policy "authors can update own accessible chat messages"
on public.chat_messages
for update
to authenticated
using (
  origin = 'sk_works'
  and sender_user_id = auth.uid()
  and private.can_access_communication_group(communication_group_id)
)
with check (
  origin = 'sk_works'
  and sender_user_id = auth.uid()
  and private.can_access_communication_group(communication_group_id)
);

create policy "authors can delete own accessible chat messages"
on public.chat_messages
for delete
to authenticated
using (
  origin = 'sk_works'
  and sender_user_id = auth.uid()
  and private.can_access_communication_group(communication_group_id)
);

-- Attachment metadata follows the same group access.
drop policy if exists "company members can read chat attachments"
  on public.chat_attachments;
drop policy if exists "company members can insert chat attachments"
  on public.chat_attachments;

create policy "accessible members can read chat attachments"
on public.chat_attachments
for select
to authenticated
using (
  private.can_access_communication_group(communication_group_id)
);

create policy "accessible members can insert chat attachments"
on public.chat_attachments
for insert
to authenticated
with check (
  uploaded_by = auth.uid()
  and private.can_access_communication_group(communication_group_id)
);

-- Notes inherit group access, including direct-chat privacy.
drop policy if exists "company members can manage communication notes"
  on public.communication_notes;
create policy "accessible members can manage communication notes"
on public.communication_notes
for all
to authenticated
using (
  private.can_access_communication_group(group_id)
)
with check (
  private.can_access_communication_group(group_id)
);

-- Albums and album items inherit group access.
drop policy if exists "company members can manage communication albums"
  on public.communication_albums;
create policy "accessible members can manage communication albums"
on public.communication_albums
for all
to authenticated
using (
  private.can_access_communication_group(group_id)
)
with check (
  private.can_access_communication_group(group_id)
);

drop policy if exists "company members can manage communication album items"
  on public.communication_album_items;
create policy "accessible members can manage communication album items"
on public.communication_album_items
for all
to authenticated
using (
  private.can_access_communication_group(group_id)
)
with check (
  private.can_access_communication_group(group_id)
  and exists (
    select 1
    from public.communication_albums ca
    where ca.id = communication_album_items.album_id
      and ca.company_id = communication_album_items.company_id
      and ca.group_id = communication_album_items.group_id
  )
);

-- Storage objects use company/group/message/file paths.
drop policy if exists "chat_attachments_storage_read" on storage.objects;
drop policy if exists "chat_attachments_storage_insert" on storage.objects;

create policy "chat_attachments_storage_read"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'chat-attachments'
  and private.can_access_communication_group(
    private.try_uuid(split_part(name, '/', 2))
  )
);

create policy "chat_attachments_storage_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'chat-attachments'
  and private.can_access_communication_group(
    private.try_uuid(split_part(name, '/', 2))
  )
);

revoke all on function private.can_access_communication_group(uuid)
  from anon;
revoke all on function private.can_manage_communication_group(uuid)
  from anon;
revoke all on function private.try_uuid(text)
  from anon;
