\set ON_ERROR_STOP on
\i docs/review/personal-vault24/storage-test.sql
\i docs/review/personal-vault24/read-api.sql.review-only
set fixture.live='true';set fixture.actor='00000000-0000-0000-0000-000000000001';
set role authenticated;
do $$begin assert (select count(*) from public.personal_vault24_list_mine())=1;end $$;
set fixture.actor='00000000-0000-0000-0000-000000000002';
do $$begin
 assert (select count(*) from public.personal_vault24_list_mine())=0;
 begin perform public.personal_vault24_item_mine('10000000-0000-0000-0000-000000000001',repeat('a',64));raise exception 'foreign RPC allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$begin
 assert not has_function_privilege('anon','public.personal_vault24_list_mine()','EXECUTE');
 assert not has_function_privilege('service_role','public.personal_vault24_list_mine()','EXECUTE');
end $$;
