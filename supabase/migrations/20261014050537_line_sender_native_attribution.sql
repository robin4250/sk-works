-- Keep previously queued payloads unchanged: retry keys must keep their original payload.
-- Only newly created SKO posts use LINE's native account attribution.
do $$ begin
 if (select md5(prosrc) from pg_proc where oid='private.enqueue_line_chat_text()'::regprocedure) <> 'cc87af454b9133ac265692957f43001c' then
  raise exception 'Unexpected enqueue_line_chat_text definition';
 end if;
end $$;
create or replace function private.enqueue_line_chat_text() returns trigger language plpgsql security definer set search_path='' as $$
declare b public.line_group_bindings%rowtype; v_name text; v_pref private.line_chat_sender_preferences%rowtype;
begin
 if new.origin<>'sk_works' or new.sender_user_id is distinct from auth.uid() or not private.line_outbound_actor_allowed(new.sender_user_id,new.communication_group_id,new.company_id) then return new; end if;
 if nullif(btrim(new.body),'') is null or private.line_utf16_length(new.body)>5000 then return new; end if;
 if (select count(*) from private.line_chat_targets(new.communication_group_id,new.company_id))<>1 then return new; end if;
 select * into b from private.line_chat_targets(new.communication_group_id,new.company_id);
 select * into v_pref from private.line_chat_sender_preferences where user_id=new.sender_user_id and group_id=new.communication_group_id;
 v_name:=case v_pref.mode when 'nickname' then v_pref.nickname when 'company' then (select name from public.companies where id=new.company_id) else new.sender_display_name end;
 v_name:=coalesce(nullif(btrim(regexp_replace(v_name,'[[:cntrl:]]','','g')),''),'SKO');
 while private.line_utf16_length(v_name)>20 loop v_name:=left(v_name,length(v_name)-1); end loop;
 -- LINE itself appends from 'official account name' to custom sender names.
 v_name:=btrim(v_name);
 insert into private.line_chat_outbox(message_id,binding_id,company_id,group_id,actor_id,line_group_id,body,sender_name)
 values(new.id,b.id,new.company_id,new.communication_group_id,new.sender_user_id,b.line_group_id,new.body,v_name) on conflict do nothing;
 return new;
end $$;
