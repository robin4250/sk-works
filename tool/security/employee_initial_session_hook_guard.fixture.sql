-- DISPOSABLE INTEGRATION PROTOTYPE ONLY. Not a complete QR-v2 implementation.
-- The real trusted issuer/redemption and Storage/caller graph remain unconnected.
create role fixture_initial_onboarding nologin noinherit;
grant fixture_initial_onboarding to authenticator;
grant usage on schema public to fixture_initial_onboarding;
create table private.fixture_employee_initial_targets (
  user_id uuid primary key, invite_id uuid not null unique,
  company_id uuid not null, worker_id uuid not null,
  state text not null check(state in ('pending','approved','cancelled')),
  generation integer not null default 1,
  expires_at timestamptz not null,
  password_at_issue text not null,
  consumed_session_id uuid
);
create table private.fixture_employee_initial_leases (
  session_id uuid primary key,user_id uuid not null,
  invite_id uuid not null,generation integer not null
);
revoke all on private.fixture_employee_initial_targets,private.fixture_employee_initial_leases from public,anon,authenticated,fixture_initial_onboarding;
create or replace function public.fixture_employee_initial_access_token_hook(event jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor uuid := (event->>'user_id')::uuid;
  sid uuid := (event->'claims'->>'session_id')::uuid;
  claims jsonb := event->'claims';
  target private.fixture_employee_initial_targets%rowtype;
  lease private.fixture_employee_initial_leases%rowtype;
  v_session_user_id uuid;
  session_until timestamptz;
  current_password text;
begin
  select * into target from private.fixture_employee_initial_targets where user_id=actor for update;
  if not found then return jsonb_build_object('claims',claims); end if;
  select s.user_id,s.not_after into v_session_user_id,session_until from auth.sessions s where s.id=sid;
  if not found or v_session_user_id<>actor or (session_until is not null and session_until<=clock_timestamp()) then
    raise exception 'employee_initial_lease_denied';
  end if;
  select * into lease from private.fixture_employee_initial_leases where session_id=sid;
  if found then
    if lease.user_id<>actor or lease.invite_id<>target.invite_id or lease.generation<>target.generation
       or target.state<>'pending' or target.expires_at<=clock_timestamp() then
      raise exception 'employee_initial_lease_denied';
    end if;
    claims=jsonb_set(claims,'{role}','"fixture_initial_onboarding"');
    return jsonb_build_object('claims',claims);
  end if;
  select encrypted_password into current_password from auth.users where id=actor;
  if target.state='approved' and current_password is distinct from target.password_at_issue
      and current_password is not null and event->>'authentication_method'='password' then
    return jsonb_build_object('claims',claims);
  end if;
  if target.state<>'pending' or target.expires_at<=clock_timestamp()
      or target.consumed_session_id is not null or event->>'authentication_method'<>'password'
      or current_password is distinct from target.password_at_issue then
    raise exception 'employee_initial_lease_denied';
  end if;
  insert into private.fixture_employee_initial_leases values(sid,actor,target.invite_id,target.generation);
  update private.fixture_employee_initial_targets set consumed_session_id=sid where user_id=actor;
  claims=jsonb_set(claims,'{role}','"fixture_initial_onboarding"');
  return jsonb_build_object('claims',claims);
end $$;
-- CREATE OR REPLACE preserves the existing Auth-admin-only EXECUTE ACL.
create function public.fixture_employee_initial_state()
returns boolean language plpgsql security definer set search_path='' as $$
declare allowed boolean;
begin
 select true into allowed from private.fixture_employee_initial_targets t
 join private.fixture_employee_initial_leases l on l.user_id=t.user_id and l.invite_id=t.invite_id and l.generation=t.generation
 join auth.sessions s on s.id=l.session_id and s.user_id=t.user_id
 where t.user_id=auth.uid() and l.session_id=(auth.jwt()->>'session_id')::uuid
 and t.state='pending' and t.expires_at>clock_timestamp()
 and (s.not_after is null or s.not_after>clock_timestamp());
 if not coalesce(allowed,false) then raise exception 'employee_initial_lease_denied'; end if;
 return true;
end $$;
revoke all on function public.fixture_employee_initial_state() from public,anon,authenticated;
grant execute on function public.fixture_employee_initial_state() to fixture_initial_onboarding;
create table public.fixture_employee_business_rows(user_id uuid primary key,value text not null);
alter table public.fixture_employee_business_rows enable row level security;
create policy fixture_employee_business_own on public.fixture_employee_business_rows for select to authenticated using(user_id=auth.uid());
revoke all on public.fixture_employee_business_rows from public,anon,fixture_initial_onboarding;
grant select on public.fixture_employee_business_rows to authenticated;
create function public.fixture_employee_business_rpc() returns boolean language sql as $$select true$$;
revoke all on function public.fixture_employee_business_rpc() from public,anon,fixture_initial_onboarding;
grant execute on function public.fixture_employee_business_rpc() to authenticated;
