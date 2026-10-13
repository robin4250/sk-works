begin;
do $guard$ begin
 if (select md5(prosrc) from pg_proc where oid='private.link_line_source_to_chat(uuid,uuid)'::regprocedure) is distinct from '94700c6e0f0d18a7f6b25bd60bf19b9e' or
    (select md5(prosrc) from pg_proc where oid='private.create_custom_chat_group(text)'::regprocedure) is distinct from 'ab890a5257750f8850297016bb4ec712' then
  raise exception 'LINE factory prerequisite changed; review before applying';
 end if;
end $guard$;
create table private.line_chat_group_origins (
 group_id uuid primary key references public.communication_groups(id) on delete cascade,
 company_id uuid not null references public.companies(id) on delete cascade,
 origin text not null check(origin in ('line','sko')),
 created_at timestamptz not null default now()
);
alter table private.line_chat_group_origins enable row level security;
revoke all on private.line_chat_group_origins from public,anon,authenticated;
create function private.line_shared_chat_groups() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'authentication required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('group_id',g.id,'name',g.name,'origin',coalesce(o.origin,'sko')) order by g.name,g.id)
 from public.communication_groups g left join private.line_chat_group_origins o on o.group_id=g.id
 where g.group_type='company' and g.participants_only and g.archived_at is null and private.can_access_communication_group(g.id)
 and exists(select 1 from private.line_chat_source_links l where l.group_id=g.id and l.company_id=g.company_id)), '[]'::jsonb);
end $$;
create function private.create_line_shared_chat_group(p_directory_id uuid,p_name text,p_origin text,p_company_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
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
  if b.company_id<>p_company_id or b.status<>'active' then raise exception 'active company LINE source required' using errcode='42501'; end if;
  select * into g from public.communication_groups where id=b.communication_group_id;
  if not found or g.company_id<>p_company_id or g.archived_at is not null or g.group_type<>'company' or not g.participants_only or not private.can_access_communication_group(g.id) or not private.can_edit_custom_chat_photo(g.id) then raise exception 'normal group management required' using errcode='42501'; end if;
  select origin into v_origin from private.line_chat_group_origins where group_id=g.id;
  if v_origin='line' and p_origin='sko' then update private.line_chat_group_origins set origin='sko' where group_id=g.id; end if;
  -- Existing legacy groups default to SKO origin; never downgrade or rename.
  return g.id;
 end if;
 if b.id is not null and b.status<>'pending' then raise exception 'LINE source unavailable'; end if;
 if not public.is_current_user_master_admin() or not private.has_company_role(p_company_id,array['owner'::public.app_role,'admin'::public.app_role]) then raise exception 'master and company administrator required' using errcode='42501'; end if;
 -- Existing creation chooses the actor's company; require an unambiguous match.
 if (select count(*) from public.company_members where user_id=auth.uid())<>1 then raise exception 'company selection unavailable'; end if;
 v_created:=private.create_custom_chat_group(btrim(p_name));
 if not exists(select 1 from public.communication_groups where id=v_created and company_id=p_company_id) then raise exception 'company changed'; end if;
 perform private.link_line_source_to_chat(v_created,p_directory_id);
 insert into private.line_chat_group_origins(group_id,company_id,origin) values(v_created,p_company_id,p_origin);
 return v_created;
end $$;
revoke all on function private.line_shared_chat_groups() from public,anon;
revoke all on function private.create_line_shared_chat_group(uuid,text,text,uuid) from public,anon;
grant execute on function private.line_shared_chat_groups(), private.create_line_shared_chat_group(uuid,text,text,uuid) to authenticated;
create function public.line_shared_chat_groups() returns jsonb language sql stable security invoker set search_path='' as $$ select private.line_shared_chat_groups() $$;
create function public.create_line_shared_chat_group(p_directory_id uuid,p_name text,p_origin text,p_company_id uuid) returns uuid language sql security invoker set search_path='' as $$ select private.create_line_shared_chat_group(p_directory_id,p_name,p_origin,p_company_id) $$;
revoke all on function public.line_shared_chat_groups(),public.create_line_shared_chat_group(uuid,text,text,uuid) from public,anon;
grant execute on function public.line_shared_chat_groups(),public.create_line_shared_chat_group(uuid,text,text,uuid) to authenticated;
commit;
