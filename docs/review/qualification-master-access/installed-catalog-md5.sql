set search_path='';
select md5((jsonb_build_object(
  'policies',(select coalesce(jsonb_agg(to_jsonb(p) order by policyname),'[]'::jsonb) from pg_policies p where schemaname='public' and tablename='qualification_master'),
  'triggers',(select coalesce(jsonb_agg(jsonb_build_object('name',tgname,'definition',pg_get_triggerdef(oid)) order by tgname),'[]'::jsonb) from pg_trigger where tgrelid='public.qualification_master'::regclass and not tgisinternal),
  'functions',(select coalesce(jsonb_agg(to_jsonb(p) order by oid),'[]'::jsonb) from pg_proc p where oid in (to_regprocedure('private.guard_qualification_master_manager_company_move()'),to_regprocedure('private.guard_qualification_master_references()')))
))::text);
