begin;
-- An analysis destination is not a LINE binding and never enables LINE replies.
create table private.line_history_analysis_groups (
 group_id uuid primary key references public.communication_groups(id) on delete cascade,
 company_id uuid not null references public.companies(id) on delete cascade,
 command_id uuid not null,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 unique(created_by,command_id)
);
alter table private.line_history_analysis_groups enable row level security;
revoke all on private.line_history_analysis_groups from public,anon,authenticated;

create function private.line_history_destinations() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.line_client_access_allowed() or not public.is_current_user_master_admin() then raise exception 'master LINE access required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,
 'destination_kind',case when a.group_id is not null then 'analysis' when exists(select 1 from private.line_chat_source_links l where l.group_id=g.id and l.company_id=g.company_id) then 'linked' else 'saved' end,
 'months',coalesce((select jsonb_agg(jsonb_build_object('month',d.work_month,'row_count',jsonb_array_length(d.candidate_rows)) order by d.work_month desc)
 from private.line_import_drafts d where d.group_id=g.id and d.company_id=g.company_id and d.target='invoice'),'[]'::jsonb))
 order by g.name,g.id)
 from public.communication_groups g left join private.line_history_analysis_groups a on a.group_id=g.id
 where g.archived_at is null and private.can_access_communication_group(g.id)
 and exists(select 1 from public.company_members m where m.company_id=g.company_id and m.user_id=auth.uid() and m.role::text in ('owner','admin','manager'))
 and (a.group_id is not null or exists(select 1 from private.line_chat_source_links l where l.group_id=g.id and l.company_id=g.company_id)
 or exists(select 1 from private.line_import_drafts d where d.group_id=g.id and d.company_id=g.company_id))), '[]'::jsonb);
end $$;

create function private.create_line_history_analysis(p_name text,p_command_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare cid uuid; gid uuid;
begin
 if auth.uid() is null or not private.line_client_access_allowed() or not public.is_current_user_master_admin() then raise exception 'master LINE access required' using errcode='42501'; end if;
 if p_command_id is null or nullif(btrim(p_name),'') is null or length(p_name)>200 then raise exception 'invalid analysis request' using errcode='22023'; end if;
 if (select count(*) from public.company_members where user_id=auth.uid())<>1 then raise exception 'company selection unavailable' using errcode='42501'; end if;
 select company_id into cid from public.company_members where user_id=auth.uid() and role::text in ('owner','admin','manager');
 if cid is null or not private.has_company_feature(cid,'can_manage_invoices') then raise exception 'invoice management required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('line-analysis:'||auth.uid()::text||p_command_id::text,0));
 select group_id into gid from private.line_history_analysis_groups where created_by=auth.uid() and command_id=p_command_id;
 if gid is not null then return gid; end if;
 gid:=private.create_custom_chat_group('過去履歴分析：'||left(btrim(p_name),190));
 insert into private.line_history_analysis_groups(group_id,company_id,command_id,created_by) values(gid,cid,p_command_id,auth.uid());
 return gid;
end $$;
create function public.line_history_destinations() returns jsonb language sql stable security invoker set search_path='' as $$select private.line_history_destinations()$$;
create function public.create_line_history_analysis(p_name text,p_command_id uuid) returns uuid language sql security invoker set search_path='' as $$select private.create_line_history_analysis(p_name,p_command_id)$$;
revoke all on function private.line_history_destinations(),private.create_line_history_analysis(text,uuid),public.line_history_destinations(),public.create_line_history_analysis(text,uuid) from public,anon;
grant execute on function private.line_history_destinations(),private.create_line_history_analysis(text,uuid),public.line_history_destinations(),public.create_line_history_analysis(text,uuid) to authenticated;
-- Classification is independent of LINE feature availability; history remains private.
create function private.line_history_analysis_ids() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(a.group_id),'[]'::jsonb)
 from private.line_history_analysis_groups a
 where auth.uid() is not null and private.account_access_allowed()
 and private.can_access_communication_group(a.group_id)
$$;
create function public.line_history_analysis_ids() returns jsonb
language sql stable security invoker set search_path='' as $$select private.line_history_analysis_ids()$$;
revoke all on function private.line_history_analysis_ids(),public.line_history_analysis_ids() from public,anon;
grant execute on function private.line_history_analysis_ids(),public.line_history_analysis_ids() to authenticated;

-- Preserve existing signatures, function attributes and ACLs. Refuse definition drift.
do $guard$
declare definition text;
begin
 if (select md5(prosrc) from pg_proc where oid='private.link_line_source_to_chat(uuid,uuid)'::regprocedure)
   is distinct from '24724b45e6ac4a104da71855c5cf18dc' then
  raise exception 'LINE source link definition changed; review analysis guard';
 end if;
 definition := pg_get_functiondef('private.link_line_source_to_chat(uuid,uuid)'::regprocedure);
 definition := replace(definition,'begin' || chr(10), 'begin' || chr(10) ||
  ' if exists(select 1 from private.line_history_analysis_groups where group_id=p_group_id) then raise exception ''analysis destination cannot link LINE'' using errcode=''42501''; end if;' || chr(10));
 execute definition;
 if (select md5(prosrc) from pg_proc where oid='private.line_outbound_actor_allowed(uuid,uuid,uuid)'::regprocedure)
   is distinct from 'b83336427ece79df3a4a0ad6152674ce' then
  raise exception 'LINE outbound definition changed; review analysis guard';
 end if;
 definition := pg_get_functiondef('private.line_outbound_actor_allowed(uuid,uuid,uuid)'::regprocedure);
 definition := replace(definition,'select private.line_actor_release_allowed(p_actor)',
  'select not exists(select 1 from private.line_history_analysis_groups where group_id=p_group) and private.line_actor_release_allowed(p_actor)');
 execute definition;
end $guard$;
commit;
