-- Rate-limit Master recovery challenge issuance at the database boundary.

create or replace function private.enforce_master_recovery_challenge_rate_limit()
returns trigger
language plpgsql
security definer
set search_path='private','pg_temp'
as $$
declare
  v_recent_count integer;
begin
  select count(*)
  into v_recent_count
  from private.master_recovery_challenges
  where master_user_id=new.master_user_id
    and created_at >= now() - interval '10 minutes';

  if v_recent_count >= 3 then
    raise exception 'master recovery challenge rate limit exceeded';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_master_recovery_challenge_rate_limit()
  from public, anon, authenticated;

drop trigger if exists enforce_master_recovery_challenge_rate_limit
  on private.master_recovery_challenges;
create trigger enforce_master_recovery_challenge_rate_limit
before insert on private.master_recovery_challenges
for each row
execute function private.enforce_master_recovery_challenge_rate_limit();
