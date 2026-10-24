-- Catalog only. No application/Auth data rows or keys.
select jsonb_build_object(
 'session', (select jsonb_build_object('definition',pg_get_functiondef(p.oid),'source_md5',md5(p.prosrc),'attributes',to_jsonb(p)-'prosrc','owner',pg_get_userbyid(p.proowner)) from pg_proc p where p.oid=to_regprocedure('company_common_allowance_private.session_id()')),
 'relations',(select jsonb_agg(jsonb_build_object('name',c.oid::regclass::text,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'acl',c.relacl,'columns',(select jsonb_agg(jsonb_build_object('name',attname,'type',atttypid::regtype::text,'not_null',attnotnull) order by attnum) from pg_attribute where attrelid=c.oid and attnum>0 and not attisdropped)) order by c.oid) from pg_class c where c.oid in(to_regclass('public.company_rate_settings'),to_regclass('company_allowance_identity_private.identities'),to_regclass('company_allowance_identity_private.state'),to_regclass('company_common_allowance_private.items'),to_regclass('company_common_allowance_private.state'))),
 'schema_usage',has_schema_privilege('authenticated','company_common_allowance_private','USAGE'),
 'private_exists',to_regprocedure('company_common_allowance_private.registered_labels(uuid)') is not null,
 'public_exists',to_regprocedure('public.read_company_registered_allowance_labels(uuid)') is not null
) as registered_labels_catalog;
