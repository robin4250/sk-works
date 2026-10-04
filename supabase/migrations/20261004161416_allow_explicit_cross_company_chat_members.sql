-- Mirrors production migration 20261004161416.
-- Explicit direct/participants-only membership is allowed across companies
-- without widening ordinary company/site/partner chat access.

alter table private.chat_group_invites
  drop constraint if exists chat_group_invites_group_id_invitee_user_id_status_key;

create unique index if not exists chat_group_invites_one_pending_idx
on private.chat_group_invites(group_id,invitee_user_id)
where status='pending';

create or replace function private.can_access_communication_group(p_group_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = 'public','private','pg_temp'
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_group_type text;
  v_role text;
  v_participants_only boolean;
begin
  if v_user_id is null or p_group_id is null then return false; end if;

  select cg.company_id,cg.group_type,cg.participants_only
  into v_company_id,v_group_type,v_participants_only
  from public.communication_groups cg
  where cg.id=p_group_id;

  if v_company_id is null then return false; end if;

  if v_group_type='direct' or v_participants_only then
    return exists(
      select 1 from public.communication_group_members cgm
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

  if v_group_type='partner' then
    if v_role in ('owner','admin') then return true; end if;
    return exists(
      select 1 from public.member_feature_permissions mfp
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
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_result jsonb;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  if not private.can_access_communication_group(p_group_id) then
    raise exception 'このグループを確認できません';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id',gm.user_id,
    'display_name',coalesce(nullif(up.display_name,''),'SKOユーザー'),
    'joined_at',gm.joined_at,
    'is_creator',(g.created_by=gm.user_id)
  ) order by (g.created_by=gm.user_id) desc, up.display_name),'[]'::jsonb)
  into v_result
  from public.communication_group_members gm
  join public.communication_groups g on g.id=gm.group_id
  left join public.user_profiles up on up.user_id=gm.user_id
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
