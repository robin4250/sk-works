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
select set_config('test.jwt','{"role":"authenticated","session_id":"00000000-0000-0000-0000-000000000002","is_anonymous":false}',false);
insert into private.account_deletion_access_restrictions values (auth.uid());
do $$ begin
 begin perform public.prepare_master_device_enrollment_candidate(repeat('d',64),'iphone','synthetic-correct');
  raise exception 'restricted account accepted'; exception when insufficient_privilege then null; end;
end $$;
delete from private.account_deletion_access_restrictions where user_id=auth.uid();
select set_config('test.actor','00000000-0000-0000-0000-000000000009',false);
do $$ begin
 begin perform public.prepare_master_device_enrollment_candidate(repeat('d',64),'iphone','synthetic-correct');
  raise exception 'nonmaster accepted'; exception when insufficient_privilege then null; end;
end $$;
select set_config('test.actor','00000000-0000-0000-0000-000000000001',false);
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
do $$ declare v_key text:=repeat('k',32); v_token text:=repeat('t',32); v_id uuid; v_result jsonb; begin
 if has_function_privilege('authenticated','public.approve_master_device_intent_candidate(uuid,text,text)','EXECUTE') then
  raise exception 'authenticated can approve own intent'; end if;
 v_result:=public.prepare_master_device_enrollment_candidate(encode(extensions.digest(v_key,'sha256'),'hex'),'mac','synthetic-correct');
 v_id:=(v_result->>'intent_id')::uuid;
 if not public.approve_master_device_intent_candidate(v_id,encode(extensions.digest(v_token,'sha256'),'hex'),'trusted_device') then
  raise exception 'synthetic service approval failed'; end if;
 v_result:=public.complete_master_device_intent_candidate(v_id,v_key,'Synthetic Mac',v_token);
 if (v_result->>'trusted')::boolean is not true then raise exception 'completion failed'; end if;
 begin perform public.complete_master_device_intent_candidate(v_id,v_key,'Synthetic Mac',v_token);
  raise exception 'replay accepted'; exception when insufficient_privilege then null; end;
end $$;
do $$ declare v_key text:=repeat('x',32); v_token text:=repeat('y',32); v_id uuid; v_result jsonb; begin
 insert into private.master_devices(master_user_id,device_key,device_name,device_type) values
  (auth.uid(),repeat('1',32),'Synthetic 1','iphone'),(auth.uid(),repeat('2',32),'Synthetic 2','ipad');
 v_result:=public.prepare_master_device_enrollment_candidate(encode(extensions.digest(v_key,'sha256'),'hex'),'iphone','synthetic-correct');
 v_id:=(v_result->>'intent_id')::uuid;
 perform public.approve_master_device_intent_candidate(v_id,encode(extensions.digest(v_token,'sha256'),'hex'),'trusted_device');
 begin perform public.complete_master_device_intent_candidate(v_id,v_key,'Synthetic 4',v_token);
  raise exception 'fourth device accepted'; exception when insufficient_privilege then null; end;
 if (select consumed_at from master_device_enrollment_candidate.intents where id=v_id) is not null then
  raise exception 'failed completion consumed intent'; end if;
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
