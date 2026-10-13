-- New text posts only. No historical backfill and no changes to existing chat RLS.
create table private.line_chat_outbox (
 id uuid primary key default gen_random_uuid(),
 message_id uuid not null references public.chat_messages(id) on delete cascade,
 binding_id uuid not null references public.line_group_bindings(id),
 company_id uuid not null references public.companies(id),
 group_id uuid not null references public.communication_groups(id),
 actor_id uuid not null references auth.users(id),
 line_group_id text not null, body text not null, sender_name text not null,
 retry_key uuid not null default gen_random_uuid(),
 state text not null default 'pending' check(state in ('pending','sending','accepted','unknown','rejected','expired')),
 created_at timestamptz not null default now(), first_attempt_at timestamptz,
 lease_id uuid, lease_until timestamptz, ticket uuid, ticket_until timestamptz,
 next_attempt_at timestamptz, attempts integer not null default 0,
 unique(message_id,binding_id), unique(retry_key)
);
alter table private.line_chat_outbox enable row level security;
revoke all on private.line_chat_outbox from public,anon,authenticated,service_role;
create function private.line_outbound_actor_allowed(p_actor uuid,p_group uuid,p_company uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select p_actor is not null and exists(select 1 from auth.users where id=p_actor)
 and not exists(select 1 from private.account_deletion_access_restrictions where user_id=p_actor)
 and exists(select 1 from public.communication_groups g join public.communication_group_members m on m.group_id=g.id and m.user_id=p_actor
 where g.id=p_group and g.company_id=p_company and g.group_type='company' and g.participants_only and g.archived_at is null)
$$;
-- utf16 units used by LINE, including surrogate-pair characters.
create function private.line_utf16_length(p_text text) returns integer language sql immutable set search_path='' as $$
 select coalesce(sum(case when ascii(c)>65535 then 2 else 1 end),0)::integer from regexp_split_to_table(p_text,'') c
$$;
create table private.line_chat_sender_preferences (
 user_id uuid not null references auth.users(id) on delete cascade,
 group_id uuid not null references public.communication_groups(id) on delete cascade,
 mode text not null check(mode in ('name','nickname','company')),
 nickname text, primary key(user_id,group_id)
);
alter table private.line_chat_sender_preferences enable row level security;
revoke all on private.line_chat_sender_preferences from public,anon,authenticated,service_role;
create function private.line_chat_sender_preferences(p_group_id uuid,p_mode text default null,p_nickname text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_company uuid; v_mode text; v_nickname text;
begin
 select company_id into v_company from public.communication_groups where id=p_group_id;
 if not private.line_outbound_actor_allowed(auth.uid(),p_group_id,v_company) then raise exception 'Chat send access required' using errcode='42501'; end if;
 if p_mode is not null then
  if p_mode not in ('name','nickname','company') or (p_mode='nickname' and (nullif(btrim(p_nickname),'') is null or private.line_utf16_length(p_nickname)>40 or p_nickname ~ '[[:cntrl:]]')) then raise exception 'Invalid sender preference'; end if;
  insert into private.line_chat_sender_preferences(user_id,group_id,mode,nickname) values(auth.uid(),p_group_id,p_mode,case when p_mode='nickname' then btrim(p_nickname) end)
  on conflict(user_id,group_id) do update set mode=excluded.mode,nickname=excluded.nickname;
 end if;
 select mode,nickname into v_mode,v_nickname from private.line_chat_sender_preferences where user_id=auth.uid() and group_id=p_group_id;
 return jsonb_build_object('mode',coalesce(v_mode,'name'),'nickname',v_nickname);
end $$;
create function public.line_chat_sender_preferences(p_group_id uuid,p_mode text default null,p_nickname text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.line_chat_sender_preferences(p_group_id,p_mode,p_nickname) $$;
revoke all on function private.line_chat_sender_preferences(uuid,text,text),public.line_chat_sender_preferences(uuid,text,text) from public,anon,service_role;
grant execute on function private.line_chat_sender_preferences(uuid,text,text),public.line_chat_sender_preferences(uuid,text,text) to authenticated;
create function private.line_chat_targets(p_group_id uuid,p_company_id uuid) returns setof public.line_group_bindings language sql stable security definer set search_path='' as $$
 select b.* from public.line_group_bindings b join private.line_joined_groups d on d.line_group_id=b.line_group_id and d.joined
 where b.company_id=p_company_id and b.status='active' and
 (b.communication_group_id=p_group_id or (not exists(select 1 from public.line_group_bindings primary_binding where primary_binding.communication_group_id=p_group_id and primary_binding.company_id=p_company_id and primary_binding.status='active') and exists(select 1 from private.line_chat_source_links l where l.group_id=p_group_id and l.company_id=p_company_id and l.directory_id=d.id)))
$$;
revoke all on function private.line_chat_targets(uuid,uuid) from public,anon,authenticated,service_role;
create function private.enqueue_line_chat_text() returns trigger language plpgsql security definer set search_path='' as $$
declare b public.line_group_bindings%rowtype; v_name text; v_pref private.line_chat_sender_preferences%rowtype;
begin
 if new.origin<>'sk_works' or new.sender_user_id is distinct from auth.uid() or not private.line_outbound_actor_allowed(new.sender_user_id,new.communication_group_id,new.company_id) then return new; end if;
 if nullif(btrim(new.body),'') is null or private.line_utf16_length(new.body)>5000 then return new; end if;
 if (select count(*) from private.line_chat_targets(new.communication_group_id,new.company_id))<>1 then return new; end if;
 select * into b from private.line_chat_targets(new.communication_group_id,new.company_id);
 select * into v_pref from private.line_chat_sender_preferences where user_id=new.sender_user_id and group_id=new.communication_group_id;
 v_name:=case v_pref.mode when 'nickname' then v_pref.nickname when 'company' then (select name from public.companies where id=new.company_id) else new.sender_display_name end;
 v_name:=coalesce(nullif(btrim(regexp_replace(v_name,'[[:cntrl:]]','','g')),''),'SKO');
 while private.line_utf16_length(v_name)>11 loop v_name:=left(v_name,length(v_name)-1); end loop;
 v_name:=v_name||' from SKO';
 insert into private.line_chat_outbox(message_id,binding_id,company_id,group_id,actor_id,line_group_id,body,sender_name)
 values(new.id,b.id,new.company_id,new.communication_group_id,new.sender_user_id,b.line_group_id,new.body,v_name) on conflict do nothing;
 return new;
end $$;
create trigger enqueue_line_chat_text after insert on public.chat_messages for each row execute function private.enqueue_line_chat_text();
create function private.prepare_line_chat_dispatch(p_message_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare o private.line_chat_outbox%rowtype; t uuid:=gen_random_uuid(); m public.chat_messages%rowtype;
begin
 select * into o from private.line_chat_outbox where message_id=p_message_id and actor_id=auth.uid() for update;
 if not found then
  select * into m from public.chat_messages where id=p_message_id and sender_user_id=auth.uid() and origin='sk_works';
  if not found or not private.line_outbound_actor_allowed(auth.uid(),m.communication_group_id,m.company_id) then raise exception 'Own accessible SKO post required' using errcode='42501'; end if;
  if (select count(*) from private.line_chat_targets(m.communication_group_id,m.company_id))>1 then return jsonb_build_object('state','ambiguous'); end if;
  return jsonb_build_object('state','not_linked');
 end if;
 if not private.line_outbound_actor_allowed(auth.uid(),o.group_id,o.company_id) then raise exception 'Chat send access required' using errcode='42501'; end if;
 if o.state='accepted' then return jsonb_build_object('state','accepted'); end if;
 if o.state in ('rejected','expired') then return jsonb_build_object('state',o.state); end if;
 update private.line_chat_outbox set ticket=t,ticket_until=now()+interval '30 seconds' where id=o.id;
 return jsonb_build_object('state','ready','ticket',t);
end $$;
create function public.prepare_line_chat_dispatch(p_message_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.prepare_line_chat_dispatch(p_message_id) $$;
create function private.claim_line_chat_dispatch(p_ticket uuid,p_actor_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare o private.line_chat_outbox%rowtype; v_lease uuid:=gen_random_uuid();
begin
 select * into o from private.line_chat_outbox where ticket=p_ticket and actor_id=p_actor_id and ticket_until>now() for update;
 if not found then raise exception 'Dispatch authorization expired' using errcode='42501'; end if;
 if not private.line_outbound_actor_allowed(p_actor_id,o.group_id,o.company_id) or not exists(select 1 from public.chat_messages m where m.id=o.message_id and m.origin='sk_works' and m.sender_user_id=p_actor_id and m.communication_group_id=o.group_id and m.company_id=o.company_id)
 or not exists(select 1 from public.line_group_bindings b join private.line_joined_groups d on d.line_group_id=b.line_group_id and d.joined where b.id=o.binding_id and b.status='active' and b.company_id=o.company_id and b.line_group_id=o.line_group_id and exists(select 1 from private.line_chat_targets(o.group_id,o.company_id) target where target.id=b.id) and (select count(*) from private.line_chat_targets(o.group_id,o.company_id))=1) then raise exception 'Active source and send access required' using errcode='42501'; end if;
 if o.state='accepted' then return jsonb_build_object('state','accepted'); end if;
 if o.state in ('rejected','expired') then return jsonb_build_object('state',o.state); end if;
 if o.first_attempt_at is not null and o.first_attempt_at<=now()-interval '23 hours 55 minutes' then update private.line_chat_outbox set state='expired',ticket=null where id=o.id; return jsonb_build_object('state','expired'); end if;
 if o.lease_until>now() or o.next_attempt_at>now() then return jsonb_build_object('state','busy'); end if;
 update private.line_chat_outbox set state='sending',lease_id=v_lease,lease_until=now()+interval '30 seconds',ticket=null,first_attempt_at=coalesce(first_attempt_at,now()),attempts=attempts+1 where id=o.id;
 return jsonb_build_object('state','claimed','outbox_id',o.id,'lease_id',v_lease,'retry_key',o.retry_key,'to',o.line_group_id,'body',o.body,'sender_name',o.sender_name);
end $$;
create function public.claim_line_chat_dispatch(p_ticket uuid,p_actor_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.claim_line_chat_dispatch(p_ticket,p_actor_id) $$;
create function private.finish_line_chat_dispatch(p_outbox_id uuid,p_lease_id uuid,p_state text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_state not in ('accepted','unknown','rejected') then raise exception 'Invalid dispatch outcome'; end if;
 update private.line_chat_outbox set state=p_state,lease_until=null,next_attempt_at=case when p_state='unknown' then now()+interval '30 seconds' else null end
 where id=p_outbox_id and lease_id=p_lease_id and state='sending';
 return found;
end $$;
create function public.finish_line_chat_dispatch(p_outbox_id uuid,p_lease_id uuid,p_state text) returns boolean language sql security invoker set search_path='' as $$ select private.finish_line_chat_dispatch(p_outbox_id,p_lease_id,p_state) $$;
revoke all on function private.line_outbound_actor_allowed(uuid,uuid,uuid),private.line_utf16_length(text),private.enqueue_line_chat_text() from public,anon,authenticated,service_role;
revoke all on function private.prepare_line_chat_dispatch(uuid),public.prepare_line_chat_dispatch(uuid) from public,anon,service_role;
grant execute on function private.prepare_line_chat_dispatch(uuid),public.prepare_line_chat_dispatch(uuid) to authenticated;
revoke all on function private.claim_line_chat_dispatch(uuid,uuid),public.claim_line_chat_dispatch(uuid,uuid),private.finish_line_chat_dispatch(uuid,uuid,text),public.finish_line_chat_dispatch(uuid,uuid,text) from public,anon,authenticated;
grant usage on schema private to authenticated,service_role;
grant execute on function private.claim_line_chat_dispatch(uuid,uuid),public.claim_line_chat_dispatch(uuid,uuid),private.finish_line_chat_dispatch(uuid,uuid,text),public.finish_line_chat_dispatch(uuid,uuid,text) to service_role;
