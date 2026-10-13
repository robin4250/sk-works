-- Signed LINE observations never assign a company automatically.
create table private.line_joined_groups (
 id uuid primary key default gen_random_uuid(), line_group_id text unique not null,
 display_name text, joined boolean, observed_at timestamptz not null,
 observed_event_id text not null, updated_at timestamptz not null default now()
);
-- Existing bindings prove identity/ownership, not current bot membership.
insert into private.line_joined_groups(line_group_id,display_name,joined,observed_at,observed_event_id)
select line_group_id,display_name,null,coalesce(updated_at,created_at),'existing-binding:'||id::text from public.line_group_bindings where nullif(line_group_id,'') is not null;
create table private.line_chat_source_links (
 group_id uuid not null references public.communication_groups(id) on delete cascade,
 directory_id uuid not null references private.line_joined_groups(id),
 company_id uuid not null references public.companies(id),
 linked_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 primary key(group_id,directory_id)
);
alter table private.line_joined_groups enable row level security;
alter table private.line_chat_source_links enable row level security;
revoke all on private.line_joined_groups,private.line_chat_source_links from public,anon,authenticated;
create function private.observe_line_joined_group(p_line_group_id text,p_display_name text,p_joined boolean,p_observed_at timestamptz,p_event_id text) returns void language plpgsql security definer set search_path='' as $$ begin
 if nullif(trim(p_line_group_id),'') is null or p_observed_at is null or nullif(p_event_id,'') is null then raise exception 'signed group observation required'; end if;
 insert into private.line_joined_groups(line_group_id,display_name,joined,observed_at,observed_event_id) values(p_line_group_id,nullif(trim(p_display_name),''),p_joined,p_observed_at,p_event_id)
 on conflict(line_group_id) do update set display_name=coalesce(excluded.display_name,line_joined_groups.display_name),joined=case when excluded.observed_at=line_joined_groups.observed_at then case when line_joined_groups.joined=false or excluded.joined=false then false else excluded.joined end else excluded.joined end,observed_at=excluded.observed_at,observed_event_id=excluded.observed_event_id,updated_at=now() where excluded.observed_at>line_joined_groups.observed_at or excluded.observed_at=line_joined_groups.observed_at;
 end $$;
create function public.observe_line_joined_group(p_line_group_id text,p_display_name text,p_joined boolean,p_observed_at timestamptz,p_event_id text) returns void language sql security invoker set search_path='' as $$ select private.observe_line_joined_group(p_line_group_id,p_display_name,p_joined,p_observed_at,p_event_id) $$;
create function private.line_joined_group_workspace(p_target_group_id uuid default null,p_new_company_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$ declare v_company uuid; v_master boolean; begin
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
 end $$;
create function public.line_joined_group_workspace(p_target_group_id uuid default null,p_new_company_id uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$ select private.line_joined_group_workspace(p_target_group_id,p_new_company_id) $$;
create function private.link_line_source_to_chat(p_group_id uuid,p_directory_id uuid) returns void language plpgsql security definer set search_path='' as $$ declare v_group public.communication_groups%rowtype; v_directory private.line_joined_groups%rowtype; v_binding public.line_group_bindings%rowtype; begin
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
 end $$;
create function public.link_line_source_to_chat(p_group_id uuid,p_directory_id uuid) returns void language sql security invoker set search_path='' as $$ select private.link_line_source_to_chat(p_group_id,p_directory_id) $$;
revoke all on function private.observe_line_joined_group(text,text,boolean,timestamptz,text),public.observe_line_joined_group(text,text,boolean,timestamptz,text) from public,anon,authenticated;
grant usage on schema private to service_role;
grant execute on function private.observe_line_joined_group(text,text,boolean,timestamptz,text),public.observe_line_joined_group(text,text,boolean,timestamptz,text) to service_role;
revoke all on function private.line_joined_group_workspace(uuid,uuid),public.line_joined_group_workspace(uuid,uuid),private.link_line_source_to_chat(uuid,uuid),public.link_line_source_to_chat(uuid,uuid) from public,anon;
grant execute on function private.line_joined_group_workspace(uuid,uuid),public.line_joined_group_workspace(uuid,uuid),private.link_line_source_to_chat(uuid,uuid),public.link_line_source_to_chat(uuid,uuid) to authenticated;
-- Retained webhook identifiers are discovery candidates only, never proof of
-- current membership or company ownership. Bodies are never exposed.
insert into private.line_joined_groups(line_group_id,joined,observed_at,observed_event_id)
select group_id,null,max(received_at),'retained-webhook:'||group_id from public.line_webhook_events where nullif(group_id,'') is not null group by group_id on conflict(line_group_id) do nothing;
create function private.line_known_group_ids(p_after uuid default null) returns jsonb language sql stable security definer set search_path='' as $$ select coalesce(jsonb_agg(jsonb_build_object('id',id,'line_group_id',line_group_id) order by id),'[]'::jsonb) from (select id,line_group_id from private.line_joined_groups where p_after is null or id>p_after order by id limit 8) d $$;
create function public.line_known_group_ids(p_after uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$ select private.line_known_group_ids(p_after) $$;
revoke all on function private.line_known_group_ids(uuid),public.line_known_group_ids(uuid) from public,anon,authenticated;
grant execute on function private.line_known_group_ids(uuid),public.line_known_group_ids(uuid) to service_role;
-- A linked normal group's members may read the original source through this
-- exact link only. No primary membership/RLS or billing authority is changed.
create function private.line_linked_talk(p_target_group_id uuid,p_directory_id uuid,p_after_at timestamptz default null,p_after_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$ declare v_company uuid; v_primary uuid; begin
 if auth.uid() is null or not private.account_access_allowed() or not private.can_access_communication_group(p_target_group_id) then raise exception 'linked talk access required' using errcode='42501'; end if;
 select g.company_id,b.communication_group_id into v_company,v_primary from public.communication_groups g join private.line_chat_source_links l on l.group_id=g.id and l.company_id=g.company_id and l.directory_id=p_directory_id join private.line_joined_groups d on d.id=l.directory_id join public.line_group_bindings b on b.line_group_id=d.line_group_id and b.company_id=g.company_id and b.status in ('active','disabled') where g.id=p_target_group_id and g.group_type='company' and g.participants_only and g.archived_at is null;
 if not found then raise exception 'company source link required' using errcode='42501'; end if;
 if (p_after_at is null)<>(p_after_id is null) then raise exception 'complete source cursor required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(m) order by m.sent_at,m.id) from (select id,body,sender_display_name,sent_at from public.chat_messages where company_id=v_company and communication_group_id=v_primary and origin='line' and (p_after_at is null or (sent_at,id)>(p_after_at,p_after_id)) order by sent_at,id limit 200) m),'[]'::jsonb);
 end $$;
create function public.line_linked_talk(p_target_group_id uuid,p_directory_id uuid,p_after_at timestamptz default null,p_after_id uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$ select private.line_linked_talk(p_target_group_id,p_directory_id,p_after_at,p_after_id) $$;
revoke all on function private.line_linked_talk(uuid,uuid,timestamptz,uuid),public.line_linked_talk(uuid,uuid,timestamptz,uuid) from public,anon;
grant execute on function private.line_linked_talk(uuid,uuid,timestamptz,uuid),public.line_linked_talk(uuid,uuid,timestamptz,uuid) to authenticated;
