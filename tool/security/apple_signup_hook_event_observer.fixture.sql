-- Disposable-only observer. Never install or register this hook in production.
-- It always refuses creation after observing the actual GoTrue-generated event,
-- so neither email nor SMS can be sent after the observation.
create table private.fixture_apple_signup_hook_observations(
  provider text primary key,
  providers_type text,
  providers_contains_provider boolean not null,
  guard_allowed boolean not null
);
alter table private.fixture_apple_signup_hook_observations enable row level security;
grant insert on private.fixture_apple_signup_hook_observations to supabase_auth_admin;
create policy hook_insert on private.fixture_apple_signup_hook_observations
  for insert to supabase_auth_admin with check(true);

create function private.fixture_apple_signup_hook_observer(event jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  result jsonb;
  p text := event->'user'->'app_metadata'->>'provider';
begin
  result := private.apple_existing_account_signup_guard(event);
  insert into private.fixture_apple_signup_hook_observations values(
    coalesce(p,'MISSING'),jsonb_typeof(event->'user'->'app_metadata'->'providers'),
    coalesce(event->'user'->'app_metadata'->'providers' @> jsonb_build_array(p),false),
    result='{}'::jsonb);
  return jsonb_build_object('error',jsonb_build_object('http_code',403,
    'message','Disposable event observation complete; creation is disabled.'));
end $$;
revoke all on function private.fixture_apple_signup_hook_observer(jsonb) from public,anon,authenticated;
grant execute on function private.fixture_apple_signup_hook_observer(jsonb) to supabase_auth_admin;

-- Belt-and-braces local SMS replacement: never call a commercial endpoint,
-- even if an unexpected request reaches the SMS dispatch phase.
create function private.fixture_apple_signup_no_sms(event jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
begin
  return jsonb_build_object('error',jsonb_build_object('http_code',403,
    'message','External SMS is disabled in this disposable fixture.'));
end $$;
revoke all on function private.fixture_apple_signup_no_sms(jsonb) from public,anon,authenticated;
grant execute on function private.fixture_apple_signup_no_sms(jsonb) to supabase_auth_admin;
