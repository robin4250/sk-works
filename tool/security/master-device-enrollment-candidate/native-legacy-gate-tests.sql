\set ON_ERROR_STOP on
select set_config('test.actor','00000000-0000-0000-0000-000000000001',false);
-- OFF preserves the old function's own not-found result.
do $$ begin
 begin perform public.revoke_master_device('00000000-0000-0000-0000-000000000099');
  raise exception 'missing device unexpectedly accepted';
 exception when raise_exception then
  if sqlerrm <> 'master device not found' then raise; end if;
 end;
end $$;
update master_device_enrollment_candidate.rollout set enabled=true;
do $$ begin
 begin perform public.bootstrap_first_master_device(repeat('x',32),'synthetic','iphone',null);
  raise exception 'old bootstrap accepted'; exception when insufficient_privilege then null; end;
 begin perform public.set_master_device_locked('00000000-0000-0000-0000-000000000099',true);
  raise exception 'old lock accepted'; exception when insufficient_privilege then null; end;
 begin perform public.revoke_master_device('00000000-0000-0000-0000-000000000099');
  raise exception 'old revoke accepted'; exception when insufficient_privilege then null; end;
end $$;
update master_device_enrollment_candidate.rollout set enabled=false;
