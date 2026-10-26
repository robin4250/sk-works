\set ON_ERROR_STOP on
select set_config('test.actor','00000000-0000-0000-0000-000000000001',false);
select set_config('test.jwt','{"role":"authenticated","session_id":"00000000-0000-0000-0000-000000000002","is_anonymous":false}',false);
do $$ begin
 begin
  perform public.prepare_master_device_enrollment_candidate(repeat('a',64),'iphone','synthetic-correct');
  raise exception 'disabled gate accepted';
 exception when insufficient_privilege then null; end;
end $$;
update master_device_enrollment_candidate.rollout set enabled=true;
select public.prepare_master_device_enrollment_candidate(repeat('a',64),'iphone','synthetic-wrong');
do $$ begin
 if (select failed_attempts from public.user_secondary_credentials limit 1) <> 1 then raise exception 'failure count not committed'; end if;
 if (select count(*) from master_device_enrollment_candidate.intents) <> 0 then raise exception 'wrong password created intent'; end if;
end $$;
select public.prepare_master_device_enrollment_candidate(repeat('b',64),'ipad','synthetic-correct');
do $$ begin
 if (select count(*) from master_device_enrollment_candidate.intents) <> 1 then raise exception 'missing intent'; end if;
 if (select failed_attempts from public.user_secondary_credentials limit 1) <> 0 then raise exception 'successful verification did not reset failure count'; end if;
end $$;
update auth.users set banned_until=now()+interval '1 hour' where id=auth.uid();
do $$ begin
 begin perform public.prepare_master_device_enrollment_candidate(repeat('c',64),'mac','synthetic-correct');
  raise exception 'banned account accepted'; exception when insufficient_privilege then null; end;
end $$;
update auth.users set banned_until=null where id=auth.uid();
update auth.sessions set not_after=now()-interval '1 minute';
do $$ begin
 begin perform public.prepare_master_device_enrollment_candidate(repeat('c',64),'mac','synthetic-correct');
  raise exception 'expired session accepted'; exception when insufficient_privilege then null; end;
end $$;
update auth.sessions set not_after=null;
select set_config('test.jwt','{"role":"authenticated","session_id":"00000000-0000-0000-0000-000000000002","is_anonymous":true}',false);
do $$ begin
 begin perform public.prepare_master_device_enrollment_candidate(repeat('c',64),'mac','synthetic-correct');
  raise exception 'anonymous session accepted'; exception when insufficient_privilege then null; end;
end $$;
