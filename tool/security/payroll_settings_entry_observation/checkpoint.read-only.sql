-- READ ONLY checkpoint. Two writer tables are read inside PostgreSQL solely for
-- count/SHA256. No application values or Auth rows are returned. Catalog includes
-- constraints and definitions; save the result privately, never paste it publicly.
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '15s';
SET LOCAL lock_timeout = '3s';
SET LOCAL search_path = '';
SET LOCAL TimeZone = 'UTC';
SET LOCAL DateStyle = 'ISO, YMD';
with relation_names(name) as (values ('public.companies'),('public.company_rate_settings')),
 routine_names(name) as (values
 ('company_common_allowance_private.authorize'),('company_common_allowance_private.session_id'),
 ('company_common_allowance_private.read_rate_defaults'),('company_common_allowance_private.save_rate_defaults'),
 ('public.read_company_rate_defaults'),('public.save_company_rate_defaults'),
 ('private.account_access_allowed'),('public.company_rate_settings_state'),
 ('public.save_company_rate_settings'),('public.save_company_rate_settings_with_units'),('public.save_company_allowance_units'),
 ('private.company_tax_refresh_invoice'),('private.capture_company_profile_revision'),
 ('private.company_refresh_generation_setting_issues_trigger'),('private.provision_standard_company_chat'),
 ('company_allowance_identity_private.prevent_settings_delete'),('company_allowance_identity_private.prevent_reinsert'),
 ('company_allowance_identity_private.track_settings'),('company_common_allowance_private.protect_unit_aliases')),
 namespaces(name) as (values ('public'),('company_common_allowance_private'),('company_allowance_identity_private'),('private')),
 objects as (select w.name,c.* from relation_names w left join pg_class c on c.oid=to_regclass(w.name)),
 routines as (select p.*,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where p.prokind='f' and (n.nspname||'.'||p.proname in (select name from routine_names)
  ))
select jsonb_build_object('schema',1,'observation_kind','company_rate_defaults_checkpoint',
 'application_rows_read',true,'application_values_returned',false,
 'data',jsonb_build_object(
   'public.companies',(select jsonb_build_object('count',count(*),'sha256',encode(sha256(convert_to(coalesce(jsonb_agg(v order by v::text)::text,'[]'),'UTF8')),'hex')) from (select to_jsonb(t) v from public.companies t) x),
   'public.company_rate_settings',(select jsonb_build_object('count',count(*),'sha256',encode(sha256(convert_to(coalesce(jsonb_agg(v order by v::text)::text,'[]'),'UTF8')),'hex')) from (select to_jsonb(t) v from public.company_rate_settings t) x)),
 'namespaces',(select jsonb_object_agg(w.name,case when n.oid is null then jsonb_build_object('exists',false)
   else jsonb_build_object('exists',true,'owner',pg_get_userbyid(n.nspowner),'acl',to_jsonb(n.nspacl)) end order by w.name)
   from namespaces w left join pg_namespace n on n.nspname=w.name),
 'relations',(select jsonb_object_agg(o.name,case when o.oid is null then jsonb_build_object('exists',false)
   else jsonb_build_object('exists',true,'owner',pg_get_userbyid(o.relowner),'acl',to_jsonb(o.relacl),
     'rls',o.relrowsecurity,'force_rls',o.relforcerowsecurity,'kind',o.relkind,'options',to_jsonb(o.reloptions),
     'columns',(select coalesce(jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
       'not_null',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid))
       order by a.attnum),'[]'::jsonb) from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
       where a.attrelid=o.oid and a.attnum>0 and not a.attisdropped),
     'constraints',(select coalesce(jsonb_agg(jsonb_build_object('name',x.conname,'definition',pg_get_constraintdef(x.oid)) order by x.conname),'[]'::jsonb) from pg_constraint x where x.conrelid=o.oid),
     'indexes',(select coalesce(jsonb_agg(jsonb_build_object('name',i.relname,'definition',pg_get_indexdef(i.oid)) order by i.relname),'[]'::jsonb) from pg_index x join pg_class i on i.oid=x.indexrelid where x.indrelid=o.oid),
     'triggers',(select coalesce(jsonb_agg(jsonb_build_object('name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid),'function',t.tgfoid::regprocedure::text) order by t.tgname),'[]'::jsonb) from pg_trigger t where t.tgrelid=o.oid and not t.tgisinternal),
     'policies',(select coalesce(jsonb_agg(jsonb_build_object('name',p.polname,'roles',p.polroles,'command',p.polcmd,
       'permissive',p.polpermissive,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) order by p.polname),'[]'::jsonb)
       from pg_policy p where p.polrelid=o.oid)) end order by o.name) from objects o),
 'missing_routine_names',(select coalesce(jsonb_agg(w.name order by w.name),'[]'::jsonb) from routine_names w
   where not exists(select 1 from routines r where r.nspname||'.'||r.proname=w.name)),
 'routines',(select coalesce(jsonb_object_agg(p.nspname||'.'||p.proname||'('||oidvectortypes(p.proargtypes)||')',
   jsonb_build_object('source_md5',md5(p.prosrc),'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),
     'attributes',to_jsonb(p)-'prosrc','anon_execute',has_function_privilege('anon',p.oid,'execute'),
     'authenticated_execute',has_function_privilege('authenticated',p.oid,'execute'),
     'service_role_execute',has_function_privilege('service_role',p.oid,'execute')) order by p.nspname,p.proname,oidvectortypes(p.proargtypes)),
   '{}'::jsonb) from routines p)) as observation;

ROLLBACK;
