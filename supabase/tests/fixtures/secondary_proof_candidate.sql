-- Isolated design candidate, not a production migration or active RPC.
create table private.secondary_change_tickets(
 token_hash text primary key,
 actor_id uuid not null,
 session_id uuid not null,
 scope text not null check(scope='secondary-password-change'),
 credential_version text not null,
 expires_at timestamptz not null,
 consumed_at timestamptz
);
alter table private.secondary_change_tickets enable row level security;
revoke all on private.secondary_change_tickets from public,anon,authenticated,service_role;

create function private.secondary_candidate_context(p_actor uuid,p_session uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if p_actor is null or p_session is null then raise exception 'verified session required' using errcode='42501';end if;
 perform 1 from auth.sessions where id=p_session and user_id=p_actor
  and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise exception 'session unavailable' using errcode='42501';end if;
 if exists(select 1 from private.fixture_account_restrictions where user_id=p_actor) then
  raise exception 'account restricted' using errcode='42501';
 end if;
end $$;
revoke all on function private.secondary_candidate_context(uuid,uuid) from public,anon,authenticated,service_role;

create function private.secondary_candidate_mint(p_actor uuid,p_session uuid)
returns text language plpgsql security definer set search_path='' as $$
declare version text;ticket text;
begin
 perform private.secondary_candidate_context(p_actor,p_session);
 select md5(password_hash) into version from public.user_secondary_credentials where user_id=p_actor for update;
 if version is null then raise exception 'existing credential required';end if;
 ticket:=encode(public.gen_random_bytes(32),'hex');
 insert into private.secondary_change_tickets(token_hash,actor_id,session_id,scope,credential_version,expires_at)
 values(encode(public.digest(ticket,'sha256'),'hex'),p_actor,p_session,'secondary-password-change',version,clock_timestamp()+interval '5 minutes');
 return ticket;
end $$;
revoke all on function private.secondary_candidate_mint(uuid,uuid) from public,anon,authenticated,service_role;

create function public.secondary_candidate_issue_with_secondary(p_password text)
returns text language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();sid uuid:=nullif(auth.jwt()->>'session_id','')::uuid;
begin
 perform private.secondary_candidate_context(actor,sid);
 -- Wrong password returns null, committing existing failure-count/lock updates.
 if public.verify_secondary_password(p_password) is distinct from true then return null;end if;
 return private.secondary_candidate_mint(actor,sid);
end $$;
revoke all on function public.secondary_candidate_issue_with_secondary(text) from public,anon,service_role;
grant execute on function public.secondary_candidate_issue_with_secondary(text) to authenticated;

-- The Edge server must verify primary credentials against Auth first, match the
-- same actor, and validate the originating caller session. No client boolean.
create function public.secondary_candidate_issue_after_server_primary(p_actor uuid,p_session uuid)
returns text language plpgsql security definer set search_path='' as $$
begin
 if auth.jwt()->>'role' is distinct from 'service_role' then raise exception 'trusted issuer required' using errcode='42501';end if;
 return private.secondary_candidate_mint(p_actor,p_session);
end $$;
revoke all on function public.secondary_candidate_issue_after_server_primary(uuid,uuid) from public,anon,authenticated;
grant execute on function public.secondary_candidate_issue_after_server_primary(uuid,uuid) to service_role;

create function public.secondary_candidate_initial_set(p_password text)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();sid uuid:=nullif(auth.jwt()->>'session_id','')::uuid;n int;
begin
 perform private.secondary_candidate_context(actor,sid);
 if p_password is null or length(p_password)<8 then raise exception 'password length required';end if;
 insert into public.user_secondary_credentials(user_id,password_hash,failed_attempts,locked_until,updated_at)
 values(actor,public.crypt(p_password,public.gen_salt('bf',12)),0,null,clock_timestamp()) on conflict(user_id) do nothing;
 get diagnostics n=row_count;
 if n<>1 then raise exception 'change proof required' using errcode='42501';end if;
end $$;
revoke all on function public.secondary_candidate_initial_set(text) from public,anon,service_role;
grant execute on function public.secondary_candidate_initial_set(text) to authenticated;

create function public.secondary_candidate_change(p_ticket text,p_password text)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();sid uuid:=nullif(auth.jwt()->>'session_id','')::uuid;version text;n int;
begin
 perform private.secondary_candidate_context(actor,sid);
 if p_password is null or length(p_password)<8 then raise exception 'password length required';end if;
 if p_ticket is null or p_ticket!~'^[0-9a-f]{64}$' then raise exception 'change proof invalid' using errcode='42501';end if;
 select md5(password_hash) into version from public.user_secondary_credentials where user_id=actor for update;
 update private.secondary_change_tickets set consumed_at=clock_timestamp()
 where token_hash=encode(public.digest(p_ticket,'sha256'),'hex') and actor_id=actor and session_id=sid
  and scope='secondary-password-change' and credential_version=version
  and consumed_at is null and expires_at>clock_timestamp();
 get diagnostics n=row_count;
 if n<>1 then raise exception 'change proof invalid' using errcode='42501';end if;
 update public.user_secondary_credentials set password_hash=public.crypt(p_password,public.gen_salt('bf',12)),
  failed_attempts=0,locked_until=null,updated_at=clock_timestamp() where user_id=actor;
end $$;
revoke all on function public.secondary_candidate_change(text,text) from public,anon,service_role;
grant execute on function public.secondary_candidate_change(text,text) to authenticated;
