\set ON_ERROR_STOP on
-- Existing read-api-test.sql must have completed in this isolated database.
\i docs/review/personal-vault25-delivery/source-binding.sql.review-only
set fixture.live='true';set fixture.actor='00000000-0000-0000-0000-000000000001';
set role authenticated;
do $$declare r record;begin
 select * into r from public.personal_vault25_source_mine('10000000-0000-0000-0000-000000000001',repeat('a',64));
 assert r.source_company_id='20000000-0000-0000-0000-000000000001'::uuid;
 assert r.source_worker_id='30000000-0000-0000-0000-000000000001'::uuid;
 assert r.source_id='50000000-0000-0000-0000-000000000001'::uuid;
 assert r.source_revision='r1' and r.snapshot_hash=repeat('a',64) and r.manifest_hash=repeat('b',64) and r.kind='own_payroll';
 assert (select count(*) from public.personal_vault25_source_mine('10000000-0000-0000-0000-000000000001',repeat('d',64)))=0;
end $$;
set fixture.actor='00000000-0000-0000-0000-000000000002';
do $$begin
 begin perform public.personal_vault25_source_mine('10000000-0000-0000-0000-000000000001',repeat('a',64));raise exception 'foreign accepted';exception when insufficient_privilege then null;end;
end $$;
set fixture.actor='00000000-0000-0000-0000-000000000001';set fixture.live='false';
do $$begin
 begin perform public.personal_vault25_source_mine('10000000-0000-0000-0000-000000000001',repeat('a',64));raise exception 'expired accepted';exception when others then if sqlerrm<>'fixture_expired' then raise;end if;end;
end $$;
reset role;
do $$begin
 assert not has_function_privilege('anon','public.personal_vault25_source_mine(uuid,text)','EXECUTE');
 assert not has_function_privilege('service_role','public.personal_vault25_source_mine(uuid,text)','EXECUTE');
end $$;
