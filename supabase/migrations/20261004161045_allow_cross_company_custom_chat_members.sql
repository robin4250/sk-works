-- Mirrors production migration 20261004161045.
-- Participant-only custom chat groups may include SKO friends from other companies.
-- Access remains explicit-membership-only and ordinary company/site/partner rules are unchanged.

create or replace function private.can_access_communication_group(p_group_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_group_type text;
  v_role text;
  v_participants_only boolean;
begin
  if v_user_id is null or p_group_id is null then
    return false;
  end if;

  select cg.company_id,cg.group_type,cg.participants_only
  into v_company_id,v_group_type,v_participants_only
  from public.communication_groups cg
  where cg.id=p_group_id;

  if v_company_id is null then return false; end if;

  if v_participants_only then
    return exists(
      select 1
      from public.communication_group_members cgm
      where cgm.group_id=p_group_id
        and cgm.user_id=v_user_id
    );
  end if;

  select cm.role::text into v_role
  from public.company_members cm
  where cm.company_id=v_company_id and cm.user_id=v_user_id
  limit 1;

  if v_role is null then return false; end if;

  if v_group_type='site' and v_role in ('owner','admin','manager') then
    return true;
  end if;

  if v_group_type='direct' then
    return exists(
      select 1
      from public.communication_group_members cgm
      where cgm.group_id=p_group_id
        and cgm.user_id=v_user_id
    );
  end if;

  if v_group_type='partner' then
    if v_role in ('owner','admin') then return true; end if;
    return exists(
      select 1
      from public.member_feature_permissions mfp
      where mfp.company_id=v_company_id
        and mfp.user_id=v_user_id
        and mfp.can_manage_partner_chat=true
    );
  end if;

  return v_group_type='company';
end
$$;

create or replace function private.custom_chat_group_members(p_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_result jsonb;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  if not private.can_access_communication_group(p_group_id) then
    raise exception 'このグループを表示できません';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'user_id', gm.user_id,
        'display_name', coalesce(nullif(up.display_name,''),'SKOユーザー'),
        'company_name', coalesce(c.name,''),
        'is_creator', gm.user_id = g.created_by,
        'joined_at', gm.joined_at,
        'last_message_at', (
          select max(m.sent_at)
          from public.chat_messages m
          where m.communication_group_id = gm.group_id
            and m.sender_user_id = gm.user_id
        )
      )
      order by
        (
          select max(m.sent_at)
          from public.chat_messages m
          where m.communication_group_id = gm.group_id
            and m.sender_user_id = gm.user_id
        ) desc nulls last,
        coalesce(nullif(up.display_name,''),'SKOユーザー')
    ),
    '[]'::jsonb
  )
  into v_result
  from public.communication_group_members gm
  join public.communication_groups g on g.id=gm.group_id
  left join public.user_profiles up on up.user_id=gm.user_id
  left join public.company_members cm on cm.user_id=gm.user_id
  left join public.companies c on c.id=cm.company_id
  where gm.group_id=p_group_id;

  return v_result;
end
$$;

create or replace function public.custom_chat_group_members(p_group_id uuid)
returns jsonb
language sql
set search_path = ''
as $$ select private.custom_chat_group_members(p_group_id) $$;

revoke execute on function public.custom_chat_group_members(uuid) from public, anon;
grant execute on function public.custom_chat_group_members(uuid) to authenticated;
