CREATE OR REPLACE FUNCTION private.link_line_source_to_chat(p_group_id uuid, p_directory_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v_group public.communication_groups%rowtype; v_directory private.line_joined_groups%rowtype; v_binding public.line_group_bindings%rowtype; begin
 if auth.uid() is null or not private.account_access_allowed() or not private.can_edit_custom_chat_photo(p_group_id) then raise exception 'normal group management required' using errcode='42501'; end if;
 select * into v_group from public.communication_groups where id=p_group_id for update;
 if not private.can_edit_custom_chat_photo(p_group_id) then raise exception 'normal group management required' using errcode='42501'; end if;
 select * into v_directory from private.line_joined_groups where id=p_directory_id for update;
 if not found or v_directory.joined is distinct from true then raise exception 'joined LINE group required'; end if;
 select * into v_binding from public.line_group_bindings where line_group_id=v_directory.line_group_id for update;
 if not found or v_binding.company_id is null then
  if not public.is_current_user_master_admin() or not private.has_company_role(v_group.company_id,array['owner'::public.app_role,'admin'::public.app_role]) then raise exception 'master and company administrator required' using errcode='42501'; end if;
  if exists(select 1 from public.line_group_bindings where communication_group_id=p_group_id and status='active' and line_group_id<>v_directory.line_group_id) then raise exception 'primary LINE source already assigned'; end if;
  insert into public.line_group_bindings(line_group_id,company_id,communication_group_id,status,display_name) values(v_directory.line_group_id,v_group.company_id,p_group_id,'active',v_directory.display_name)
  on conflict(line_group_id) do update set company_id=excluded.company_id,communication_group_id=excluded.communication_group_id,status='active',display_name=excluded.display_name,updated_at=now() returning * into v_binding;
  insert into public.line_binding_audit(binding_id,company_id,communication_group_id,line_group_id,action,actor_user_id,source) values(v_binding.id,v_group.company_id,p_group_id,v_directory.line_group_id,'activated',auth.uid(),'sko_admin');
 else
  if v_binding.company_id<>v_group.company_id or v_binding.status<>'active' or not private.can_access_communication_group(v_binding.communication_group_id) then raise exception 'active company LINE source required' using errcode='42501'; end if;
 end if;
 insert into private.line_chat_source_links(group_id,directory_id,company_id,linked_by) values(p_group_id,p_directory_id,v_group.company_id,auth.uid()) on conflict do nothing;
 end $function$;

CREATE OR REPLACE FUNCTION private.create_custom_chat_group(p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_company uuid;
  v_group uuid;
  v_name text := btrim(coalesce(p_name,''));
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  if v_name = '' then raise exception 'グループ名を入力してください'; end if;

  select cm.company_id into v_company
  from public.company_members cm
  where cm.user_id = v_user
  limit 1;
  if v_company is null then raise exception '会社情報が見つかりません'; end if;

  insert into public.communication_groups (
    company_id,name,group_type,participants_only,created_by,last_activity_at
  ) values (
    v_company,v_name,'company',true,v_user,now()
  )
  returning id into v_group;

  insert into public.communication_group_members(group_id,company_id,user_id)
  values (v_group,v_company,v_user)
  on conflict do nothing;

  return v_group;
end
$function$;

