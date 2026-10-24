-- READ ONLY. Transitive routine catalog only; no company/Auth/financial rows.
with wanted(name) as (values
 ('company_common_allowance_private.session_id'),
 ('public.save_company_rate_settings'),('public.save_company_allowance_units'),
 ('private.company_tax_refresh_invoice'),('private.capture_company_profile_revision'),
 ('private.company_refresh_generation_setting_issues_trigger'),('private.provision_standard_company_chat'),
 ('company_allowance_identity_private.prevent_settings_delete'),
 ('company_allowance_identity_private.prevent_reinsert'),('company_allowance_identity_private.track_settings'),
 ('company_common_allowance_private.protect_unit_aliases')),
 routines as (select p.*,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where p.prokind='f' and n.nspname||'.'||p.proname in (select name from wanted))
select jsonb_build_object('schema',1,'observation_kind','payroll_settings_entry_dependency_catalog',
 'application_rows_read',false,
 'missing_names',(select coalesce(jsonb_agg(w.name order by w.name),'[]'::jsonb) from wanted w
   where not exists(select 1 from routines p where p.nspname||'.'||p.proname=w.name)),
 'routines',(select coalesce(jsonb_object_agg(p.nspname||'.'||p.proname||'('||oidvectortypes(p.proargtypes)||')',
   jsonb_build_object('source_md5',md5(p.prosrc),'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),
     'attributes',to_jsonb(p)-'prosrc','anon_execute',has_function_privilege('anon',p.oid,'execute'),
     'authenticated_execute',has_function_privilege('authenticated',p.oid,'execute'),
     'service_role_execute',has_function_privilege('service_role',p.oid,'execute')) order by p.nspname,p.proname,oidvectortypes(p.proargtypes)),
   '{}'::jsonb) from routines p)) as observation;
