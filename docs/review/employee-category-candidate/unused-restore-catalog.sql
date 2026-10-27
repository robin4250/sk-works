select md5(jsonb_build_object(
 'namespace',(select to_jsonb(n) from pg_namespace n where oid=to_regnamespace('employee_category_private')),
 'relations',(select coalesce(jsonb_agg(to_jsonb(c) order by c.oid),'[]') from pg_class c where relnamespace=to_regnamespace('employee_category_private')),
 'columns',(select coalesce(jsonb_agg(to_jsonb(a) order by a.attrelid,a.attnum),'[]') from pg_attribute a join pg_class c on c.oid=a.attrelid where c.relnamespace=to_regnamespace('employee_category_private')),
 'constraints',(select coalesce(jsonb_agg(to_jsonb(c) order by c.oid),'[]') from pg_constraint c where connamespace=to_regnamespace('employee_category_private')),
 'indexes',(select coalesce(jsonb_agg(to_jsonb(i) order by i.indexrelid),'[]') from pg_index i join pg_class c on c.oid=i.indexrelid where c.relnamespace=to_regnamespace('employee_category_private')),
 'triggers',(select coalesce(jsonb_agg(to_jsonb(t) order by t.oid),'[]') from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relnamespace=to_regnamespace('employee_category_private')),
 'functions',(select coalesce(jsonb_agg(to_jsonb(p) order by p.oid),'[]') from pg_proc p where pronamespace=to_regnamespace('employee_category_private') or p.oid in (to_regprocedure('public.ensure_employee_categories(uuid)'),to_regprocedure('public.list_employee_categories(uuid)'),to_regprocedure('public.add_employee_category(uuid,text)')))
)::text);
