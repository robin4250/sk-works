-- Mirrors production migration 20261004161722.
-- Keep explicit-member access for direct/participant-only chats while
-- hardening the SECURITY DEFINER helper with an empty search_path.

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
  if v_user_id is null or p_group_id is null then return false; end if;

  select cg.company_id,cg.group_type,cg.participants_only
  into v_company_id,v_group_type,v_participants_only
  from public.communication_groups cg
  where cg.id=p_group_id;

  if v_company_id is null then return false; end if;

  if v_group_type='direct' or v_participants_only then
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
