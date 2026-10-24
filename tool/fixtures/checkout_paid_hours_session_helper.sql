-- Isolated fixture copy of the registration live-session helper.
-- Runtime API reuses the existing installed function; no new identity model.
create schema checkout_report_registration_private;
create function checkout_report_registration_private.current_actor()
returns uuid language plpgsql stable security invoker set search_path='' as $$
declare actor uuid:=auth.uid(); claims jsonb:=auth.jwt(); sid uuid;
begin
 if current_setting('role',true) is distinct from 'authenticated'
 or actor is null or claims->>'role' is distinct from 'authenticated'
 or claims->>'sub' is distinct from actor::text
 or (claims ? 'is_anonymous' and claims->'is_anonymous' not in ('false'::jsonb,'null'::jsonb)) then
  raise sqlstate '42501' using message='checkout_report_actor_access_unavailable';
 end if;
 begin sid:=nullif(claims->>'session_id','')::uuid;
 exception when invalid_text_representation then
  raise sqlstate '42501' using message='checkout_report_actor_access_unavailable';
 end;
 if sid is null or private.account_access_allowed() is distinct from true then
  raise sqlstate '42501' using message='checkout_report_actor_access_unavailable';
 end if;
 if not exists(select 1 from auth.sessions s where s.id=sid and s.user_id=actor
  and (s.not_after is null or s.not_after>clock_timestamp()))
 or not exists(select 1 from auth.users u where u.id=actor and not coalesce(u.is_anonymous,false)
  and (u.banned_until is null or u.banned_until<=clock_timestamp())) then
  raise sqlstate '42501' using message='checkout_report_actor_access_unavailable';
 end if;
 return actor;
end $$;
revoke all on function checkout_report_registration_private.current_actor() from public,anon,authenticated,service_role;
