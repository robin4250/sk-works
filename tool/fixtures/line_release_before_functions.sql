CREATE OR REPLACE FUNCTION public.begin_line_group_claim(p_communication_group_id uuid)
 RETURNS TABLE(claim_code text, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_code text;
  v_expires_at timestamptz := now() + interval '15 minutes';
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select cg.company_id
    into v_company_id
  from public.communication_groups cg
  where cg.id = p_communication_group_id;

  if v_company_id is null then
    raise exception 'communication group not found';
  end if;

  if not exists (
    select 1
    from public.company_members cm
    where cm.company_id = v_company_id
      and cm.user_id = v_user_id
      and cm.role::text in ('owner', 'admin')
  ) then
    raise exception 'owner or admin role required';
  end if;

  if exists (
    select 1
    from public.line_group_bindings lgb
    where lgb.communication_group_id = p_communication_group_id
      and lgb.status = 'active'
  ) then
    raise exception 'communication group already has an active LINE binding';
  end if;

  update public.line_binding_claims
  set status = 'cancelled',
      cancelled_at = now()
  where communication_group_id = p_communication_group_id
    and status = 'pending';

  loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (
      select 1 from public.line_binding_claims c where c.claim_code = v_code
    );
  end loop;

  insert into public.line_binding_claims (
    company_id,
    communication_group_id,
    requested_by,
    claim_code,
    expires_at
  )
  values (
    v_company_id,
    p_communication_group_id,
    v_user_id,
    v_code,
    v_expires_at
  );

  return query select v_code, v_expires_at;
end;
$function$
;
revoke all on function public.begin_line_group_claim(uuid) from public,anon,authenticated,service_role;
grant execute on function public.begin_line_group_claim(uuid) to authenticated;
grant execute on function public.begin_line_group_claim(uuid) to service_role;
CREATE OR REPLACE FUNCTION public.disable_line_group_binding(p_binding_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_binding public.line_group_bindings%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select *
    into v_binding
  from public.line_group_bindings
  where id = p_binding_id
  for update;

  if not found or v_binding.company_id is null or v_binding.communication_group_id is null then
    raise exception 'LINE binding not found';
  end if;

  if not exists (
    select 1
    from public.company_members cm
    where cm.company_id = v_binding.company_id
      and cm.user_id = v_user_id
      and cm.role::text in ('owner', 'admin')
  ) then
    raise exception 'owner or admin role required';
  end if;

  if v_binding.status <> 'active' then
    return;
  end if;

  update public.line_group_bindings
  set status = 'disabled',
      updated_at = now()
  where id = v_binding.id;

  insert into public.line_binding_audit (
    binding_id,
    company_id,
    communication_group_id,
    line_group_id,
    action,
    actor_user_id,
    source
  )
  values (
    v_binding.id,
    v_binding.company_id,
    v_binding.communication_group_id,
    v_binding.line_group_id,
    'disabled',
    v_user_id,
    'sko_admin'
  );
end;
$function$
;
revoke all on function public.disable_line_group_binding(uuid) from public,anon,authenticated,service_role;
grant execute on function public.disable_line_group_binding(uuid) to authenticated;
grant execute on function public.disable_line_group_binding(uuid) to service_role;
CREATE OR REPLACE FUNCTION private.line_import_access(p_group_id uuid, p_target text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid; uid uuid:=auth.uid(); can_edit boolean; management boolean;
begin
 if uid is null or not private.account_access_allowed() or p_target is null or p_target not in ('attendance','invoice') or not private.can_access_communication_group(p_group_id) then raise exception 'LINE workspace unavailable' using errcode='42501';end if;
 select company_id into cid from public.communication_groups where id=p_group_id;
 if cid is null or not exists(select 1 from public.company_members where company_id=cid and user_id=uid) then raise exception 'company membership required' using errcode='42501';end if;
 management:=exists(select 1 from public.company_members where company_id=cid and user_id=uid and role::text in ('owner','admin','manager'));
 if p_target='invoice' and (not management or not private.has_company_feature(cid,'can_view_invoices')) then raise exception 'invoice management access required' using errcode='42501';end if;
 can_edit:=case when p_target='attendance' then public.can_manage_attendance_corrections(cid) else management and private.has_company_feature(cid,'can_manage_invoices') end;
 return jsonb_build_object('company_id',cid,'can_edit',can_edit,'management',management);
end $function$
;
revoke all on function private.line_import_access(uuid,text) from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.line_joined_group_workspace(p_target_group_id uuid DEFAULT NULL::uuid, p_new_company_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v_company uuid; v_master boolean; begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'authentication required' using errcode='42501'; end if;
 v_master:=public.is_current_user_master_admin();
 if p_new_company_id is not null then
  if p_target_group_id is not null or not exists(select 1 from public.company_members where company_id=p_new_company_id and user_id=auth.uid()) then raise exception 'current company membership required' using errcode='42501'; end if;
  v_company:=p_new_company_id;
 end if;
 if p_target_group_id is not null then
  if not private.can_access_communication_group(p_target_group_id) or not exists(select 1 from public.communication_groups where id=p_target_group_id and group_type='company' and participants_only and archived_at is null) then raise exception 'normal group access required' using errcode='42501'; end if;
  select company_id into v_company from public.communication_groups where id=p_target_group_id;
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'can_select',d.joined and ((b.company_id is not null and (v_company is null or b.company_id=v_company) and private.can_access_communication_group(b.communication_group_id) and b.status='active') or (b.company_id is null and v_master and exists(select 1 from public.company_members cm where cm.user_id=auth.uid() and (v_company is null or cm.company_id=v_company) and cm.role::text in ('owner','admin')))),'read_target_group_id',(select l.group_id from private.line_chat_source_links l where l.directory_id=d.id and l.company_id=b.company_id and (p_target_group_id is null or l.group_id=p_target_group_id) and private.can_access_communication_group(l.group_id) order by l.group_id limit 1),'primary_group_id',b.communication_group_id,'display_name',d.display_name,'joined',d.joined,'observed_at',d.observed_at,'linked',exists(select 1 from private.line_chat_source_links l where l.directory_id=d.id and l.group_id=p_target_group_id),'can_link',d.joined and p_target_group_id is not null and private.can_edit_custom_chat_photo(p_target_group_id) and ((b.company_id=v_company and b.status='active' and private.can_access_communication_group(b.communication_group_id)) or (b.company_id is null and v_master and private.has_company_role(v_company,array['owner'::public.app_role,'admin'::public.app_role])))) order by d.display_name nulls last,d.id)
 from private.line_joined_groups d left join public.line_group_bindings b on b.line_group_id=d.line_group_id
 where (v_master and b.company_id is null) or (b.company_id is not null and ((exists(select 1 from public.company_members cm where cm.company_id=b.company_id and cm.user_id=auth.uid()) and private.can_access_communication_group(b.communication_group_id)) or exists(select 1 from private.line_chat_source_links l join public.communication_groups linked_group on linked_group.id=l.group_id and linked_group.company_id=l.company_id and linked_group.group_type='company' and linked_group.participants_only and linked_group.archived_at is null where l.directory_id=d.id and (p_target_group_id is null or l.group_id=p_target_group_id) and l.company_id=b.company_id and private.can_access_communication_group(l.group_id))) and (v_company is null or b.company_id=v_company))), '[]'::jsonb);
 end $function$
;
revoke all on function private.line_joined_group_workspace(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function private.line_joined_group_workspace(uuid,uuid) to authenticated;
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
 end $function$
;
revoke all on function private.link_line_source_to_chat(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function private.link_line_source_to_chat(uuid,uuid) to authenticated;
CREATE OR REPLACE FUNCTION private.line_linked_talk(p_target_group_id uuid, p_directory_id uuid, p_after_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_after_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v_company uuid; v_primary uuid; begin
 if auth.uid() is null or not private.account_access_allowed() or not private.can_access_communication_group(p_target_group_id) then raise exception 'linked talk access required' using errcode='42501'; end if;
 select g.company_id,b.communication_group_id into v_company,v_primary from public.communication_groups g join private.line_chat_source_links l on l.group_id=g.id and l.company_id=g.company_id and l.directory_id=p_directory_id join private.line_joined_groups d on d.id=l.directory_id join public.line_group_bindings b on b.line_group_id=d.line_group_id and b.company_id=g.company_id and b.status in ('active','disabled') where g.id=p_target_group_id and g.group_type='company' and g.participants_only and g.archived_at is null;
 if not found then raise exception 'company source link required' using errcode='42501'; end if;
 if (p_after_at is null)<>(p_after_id is null) then raise exception 'complete source cursor required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(m) order by m.sent_at,m.id) from (select id,body,sender_display_name,sent_at from public.chat_messages where company_id=v_company and communication_group_id=v_primary and origin='line' and (p_after_at is null or (sent_at,id)>(p_after_at,p_after_id)) order by sent_at,id limit 200) m),'[]'::jsonb);
 end $function$
;
revoke all on function private.line_linked_talk(uuid,uuid,timestamp with time zone,uuid) from public,anon,authenticated,service_role;
grant execute on function private.line_linked_talk(uuid,uuid,timestamp with time zone,uuid) to authenticated;
CREATE OR REPLACE FUNCTION private.line_outbound_actor_allowed(p_actor uuid, p_group uuid, p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select p_actor is not null and exists(select 1 from auth.users where id=p_actor)
 and not exists(select 1 from private.account_deletion_access_restrictions where user_id=p_actor)
 and exists(select 1 from public.communication_groups g join public.communication_group_members m on m.group_id=g.id and m.user_id=p_actor
 where g.id=p_group and g.company_id=p_company and g.group_type='company' and g.participants_only and g.archived_at is null)
$function$
;
revoke all on function private.line_outbound_actor_allowed(uuid,uuid,uuid) from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.create_line_shared_chat_group(p_directory_id uuid, p_name text, p_origin text, p_company_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d private.line_joined_groups%rowtype; b public.line_group_bindings%rowtype; g public.communication_groups%rowtype; v_id uuid; v_created uuid; v_origin text;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'authentication required' using errcode='42501'; end if;
 if p_origin is null or p_origin not in ('line','sko') or nullif(btrim(p_name),'') is null or length(p_name)>200 then raise exception 'invalid group request'; end if;
 if not exists(select 1 from public.company_members where user_id=auth.uid() and company_id=p_company_id) then raise exception 'company membership required' using errcode='42501'; end if;
 -- Shared with the legacy link function. Do not take a canonical group row lock
 -- after this lock: legacy linking locks group before directory.
 select * into d from private.line_joined_groups where id=p_directory_id for update;
 if not found or d.joined is distinct from true then raise exception 'joined LINE group required'; end if;
 select * into b from public.line_group_bindings where line_group_id=d.line_group_id;
 if found and b.company_id is not null then
  if b.company_id<>p_company_id or b.status is distinct from 'active' then raise exception 'active company LINE source required' using errcode='42501'; end if;
  select * into g from public.communication_groups where id=b.communication_group_id;
  if not found or g.company_id<>p_company_id or g.archived_at is not null or g.group_type is distinct from 'company' or g.participants_only is distinct from true or not private.can_access_communication_group(g.id) or not private.can_edit_custom_chat_photo(g.id) then raise exception 'normal group management required' using errcode='42501'; end if;
  select origin into v_origin from private.line_chat_group_origins where group_id=g.id;
  if v_origin='line' and p_origin='sko' then update private.line_chat_group_origins set origin='sko' where group_id=g.id; end if;
  -- Existing legacy groups default to SKO origin; never downgrade or rename.
  return g.id;
 end if;
 if b.id is not null and b.status is distinct from 'pending' then raise exception 'LINE source unavailable'; end if;
 if not public.is_current_user_master_admin() or not private.has_company_role(p_company_id,array['owner'::public.app_role,'admin'::public.app_role]) then raise exception 'master and company administrator required' using errcode='42501'; end if;
 -- Existing creation chooses the actor's company; require an unambiguous match.
 if (select count(*) from public.company_members where user_id=auth.uid())<>1 then raise exception 'company selection unavailable'; end if;
 v_created:=private.create_custom_chat_group(btrim(p_name));
 if not exists(select 1 from public.communication_groups where id=v_created and company_id=p_company_id) then raise exception 'company changed'; end if;
 perform private.link_line_source_to_chat(v_created,p_directory_id);
 insert into private.line_chat_group_origins(group_id,company_id,origin) values(v_created,p_company_id,p_origin);
 return v_created;
end $function$
;
revoke all on function private.create_line_shared_chat_group(uuid,text,text,uuid) from public,anon,authenticated,service_role;
grant execute on function private.create_line_shared_chat_group(uuid,text,text,uuid) to authenticated;
CREATE OR REPLACE FUNCTION private.line_shared_chat_groups()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'authentication required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('group_id',g.id,'name',g.name,'origin',coalesce(o.origin,'sko')) order by g.name,g.id)
 from public.communication_groups g left join private.line_chat_group_origins o on o.group_id=g.id
 where g.group_type='company' and g.participants_only and g.archived_at is null and private.can_access_communication_group(g.id)
 and exists(select 1 from private.line_chat_source_links l where l.group_id=g.id and l.company_id=g.company_id)), '[]'::jsonb);
end $function$
;
revoke all on function private.line_shared_chat_groups() from public,anon,authenticated,service_role;
grant execute on function private.line_shared_chat_groups() to authenticated;
CREATE OR REPLACE FUNCTION private.chat_report_queue()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'sender_name',r.sender_name,'body',r.body_snapshot,'reason',r.reason,'created_at',r.created_at,'status',r.status) order by r.created_at),'[]') from private.chat_reports r where exists(select 1 from public.company_members m where m.company_id=r.company_id and m.user_id=auth.uid() and m.role::text in ('owner','admin'))
$function$
;
revoke all on function private.chat_report_queue() from public,anon,authenticated,service_role;
grant execute on function private.chat_report_queue() to authenticated;
CREATE OR REPLACE FUNCTION private.content_review_payload(p_kind text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare payload jsonb;
begin
 if not exists(select 1 from private.content_reviews r where kind=p_kind and content_id=p_id
  and review_required and private.content_reviewer(company_id) and private.chat_sender_visible(author_id)) then return null; end if;
 case p_kind
  when 'message' then select jsonb_build_object('text',body,'files','[]'::jsonb) into payload from public.chat_messages where id=p_id;
  when 'attachment' then select jsonb_build_object('text',original_filename,'files',jsonb_build_array(jsonb_build_object('bucket','chat-attachments','path',storage_path,'name',original_filename))) into payload from public.chat_attachments where id=p_id;
  when 'note' then select jsonb_build_object('text',title||E'\n'||coalesce(body,''),'files',(select coalesce(jsonb_agg(f||'{"bucket":"communication-notes"}'::jsonb),'[]'::jsonb) from jsonb_array_elements(attachments) f)) into payload from public.communication_notes where id=p_id;
  when 'album' then select jsonb_build_object('text',name||E'\n'||coalesce(description,''),'files','[]'::jsonb) into payload from public.communication_albums where id=p_id;
  when 'photo' then select jsonb_build_object('text',coalesce(caption,''),'files',jsonb_build_array(jsonb_build_object('bucket','communication-albums','path',storage_path,'name',original_filename))) into payload from public.communication_album_items where id=p_id;
  else return null;
 end case;
 return payload;
end $function$
;
revoke all on function private.content_review_payload(text,uuid) from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.report_chat_message(p_message uuid, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m public.chat_messages%rowtype; rid uuid; begin
 if auth.uid() is null then raise exception 'ログインしてください'; end if;
 if p_reason is null or p_reason not in ('harassment','inappropriate','personal_data','spam','other') then raise exception '通報理由を選んでください'; end if;
 select * into m from public.chat_messages where id=p_message;
 if not found or not private.can_access_communication_group(m.communication_group_id) or not private.chat_message_visible(m.id,m.sender_user_id) then raise exception 'この投稿を確認できません'; end if;
 if m.sender_user_id=auth.uid() then raise exception '自分の投稿は削除操作を利用してください'; end if;
 select id into rid from private.chat_reports where reporter_id=auth.uid() and message_id=p_message;
 if rid is not null then return rid; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,791));
 if (select count(*) from private.chat_reports where reporter_id=auth.uid() and created_at>now()-interval '1 day')>=20 then raise exception '本日の通報上限です。お問い合わせ窓口を利用してください'; end if;
 insert into private.chat_reports(reporter_id,message_id,company_id,sender_id,sender_name,body_snapshot,reason)
 values(auth.uid(),m.id,m.company_id,m.sender_user_id,m.sender_display_name,left(m.body,20000),p_reason)
 on conflict(reporter_id,message_id) do update set message_id=excluded.message_id returning id into rid;
 return rid;
end $function$
;
revoke all on function private.report_chat_message(uuid,text) from public,anon,authenticated,service_role;
grant execute on function private.report_chat_message(uuid,text) to authenticated;
CREATE OR REPLACE FUNCTION private.review_chat_report(p_report uuid, p_hide boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r private.chat_reports%rowtype; begin
 select * into r from private.chat_reports where id=p_report for update;
 if not found or not exists(select 1 from public.company_members m where m.company_id=r.company_id and m.user_id=auth.uid() and m.role::text in ('owner','admin')) then raise exception '管理者のみ対応できます'; end if;
 if p_hide then
   insert into private.chat_hidden_messages(message_id) select id from public.chat_messages where id=r.message_id on conflict do nothing;
 end if;
 update private.chat_reports set status=case when p_hide then 'hidden' else 'dismissed' end,reviewed_by=auth.uid(),reviewed_at=now() where id=r.id;
end $function$
;
revoke all on function private.review_chat_report(uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function private.review_chat_report(uuid,boolean) to authenticated;