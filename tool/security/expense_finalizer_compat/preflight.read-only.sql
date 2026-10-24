-- Read-only catalog checkpoint. No financial/Auth rows or secrets are selected.
with target as (
 select p.*, n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where p.oid=to_regprocedure('private.expense_cost_finalize()')
), protected as (
 select c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where (n.nspname,c.relname) in (
 ('public','invoices'),('public','payment_certificates'),
 ('private','expense_claims'),('private','expense_settlement_choices'),
 ('private','expense_amount_consumptions'),('private','expense_document_snapshots'),
 ('private','invoice_number_counters'),('public','app_notifications'))
)
select jsonb_build_object(
 'schema',1,
 'function',(select jsonb_build_object(
   'signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),
   'source_md5',md5(p.prosrc),'attributes',to_jsonb(p)-'prosrc'-'nspname',
   'owner',pg_get_userbyid(p.proowner),
   'effective_acl',(select coalesce(jsonb_agg(to_jsonb(a) order by a.grantee,a.privilege_type,a.grantor),'[]'::jsonb)
       from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a)) from target p),
 'relations',(select coalesce(jsonb_agg(jsonb_build_object(
   'name',c.oid::regclass::text,'oid',c.oid,'owner',pg_get_userbyid(c.relowner),
   'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'acl',c.relacl,
   'columns',(select coalesce(jsonb_agg(to_jsonb(a) order by attnum),'[]'::jsonb) from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
   'constraints',(select coalesce(jsonb_agg(jsonb_build_object('oid',x.oid,'definition',pg_get_constraintdef(x.oid),'catalog',to_jsonb(x)) order by x.oid),'[]'::jsonb) from pg_constraint x where x.conrelid=c.oid),
   'policies',(select coalesce(jsonb_agg(to_jsonb(x) order by x.oid),'[]'::jsonb) from pg_policy x where x.polrelid=c.oid)
 ) order by c.oid),'[]'::jsonb) from pg_class c where c.oid in(select oid from protected)),
 'triggers',(select coalesce(jsonb_agg(jsonb_build_object(
   'catalog',to_jsonb(t),'definition',pg_get_triggerdef(t.oid),
   'function_definition',pg_get_functiondef(t.tgfoid),'function_catalog',to_jsonb(p)
 ) order by t.oid),'[]'::jsonb) from pg_trigger t join pg_proc p on p.oid=t.tgfoid
 where not t.tgisinternal and (t.tgrelid in(select oid from protected) or t.tgfoid=to_regprocedure('private.expense_cost_finalize()'))),
 'event_triggers',(select coalesce(jsonb_agg(jsonb_build_object('catalog',to_jsonb(e),'definition',pg_get_functiondef(e.evtfoid)) order by e.oid),'[]'::jsonb) from pg_event_trigger e)
) as checkpoint;
