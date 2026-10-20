-- DISPOSABLE FIXTURE ONLY. Never a hosted migration, Auth hook or rollout.
create schema if not exists private;
create table if not exists private.fixture_employee_hook_observations (
  ordinal bigint generated always as identity primary key,
  user_id uuid not null, session_id uuid not null, method text not null,
  session_visible boolean not null, session_matches_user boolean not null
);
revoke all on private.fixture_employee_hook_observations from public,anon,authenticated;
create or replace function public.fixture_employee_initial_access_token_hook(event jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor uuid := (event->>'user_id')::uuid;
  sid uuid := (event->'claims'->>'session_id')::uuid;
  session_user uuid;
begin
  select s.user_id into session_user from auth.sessions s where s.id=sid;
  insert into private.fixture_employee_hook_observations
    (user_id,session_id,method,session_visible,session_matches_user)
  values(actor,sid,event->>'authentication_method',found,coalesce(session_user=actor,false));
  return jsonb_build_object('claims',event->'claims');
end $$;
revoke all on function public.fixture_employee_initial_access_token_hook(jsonb) from public,anon,authenticated;
grant execute on function public.fixture_employee_initial_access_token_hook(jsonb) to supabase_auth_admin;
