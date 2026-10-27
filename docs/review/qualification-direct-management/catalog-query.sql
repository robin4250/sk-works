with relations as (
 select c.oid,n.nspname,c.relname,c.relkind,c.relowner,c.relacl,c.relrowsecurity,c.relforcerowsecurity,c.reloptions
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where (n.nspname='public' and c.relname in ('worker_qualifications','workers','qualification_master','company_members','member_feature_permissions'))
 or (n.nspname='private' and c.relname in ('worker_qualification_history','qualification_photo_history','qualification_submissions','qualification_management_operations','qualification_management_state'))
), functions as (
 select n.nspname,p.proname,p.oid::text identity,p.proowner,p.proacl,p.prosecdef,p.provolatile,p.proparallel,p.proleakproof,p.proconfig,p.prorettype,p.proargtypes::text args,md5(p.prosrc) body_md5
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='private' and p.proname in ('require_reauthentication_session','account_deletion_barrier_key','account_access_allowed','has_company_feature',
 'capture_official_qualification_history','validate_qualification_extra_photos','archive_qualification_photos',
 'personal_qualification_submission','personal_qualification_photo_submission',
 'qualification_management_audit_immutable','qualification_manager_can_write','qualification_management_result','qualification_direct_management'))
 or (n.nspname='public' and p.proname='qualification_direct_management')
)
select md5(jsonb_build_object(
 'relations',(select jsonb_agg(to_jsonb(r) order by nspname,relname) from relations r),
 'columns',(select jsonb_agg(jsonb_build_array(a.attrelid,a.attnum,a.attname,a.atttypid,a.atttypmod,a.attnotnull,a.attidentity,a.attgenerated,d.adbin::text) order by a.attrelid,a.attnum)
  from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid in(select oid from relations) and a.attnum>0 and not a.attisdropped),
 'constraints',(select jsonb_agg(to_jsonb(c) order by c.conrelid,c.conname) from pg_constraint c where c.conrelid in(select oid from relations)),
 'triggers',(select jsonb_agg(to_jsonb(t) order by t.tgrelid,t.tgname) from pg_trigger t where t.tgrelid in(select oid from relations) and not t.tgisinternal),
 'policies',(select jsonb_agg(to_jsonb(p) order by p.polname) from pg_policy p where p.polrelid='public.worker_qualifications'::regclass),
 'functions',(select jsonb_agg(to_jsonb(f) order by nspname,identity) from functions f)
)::text) catalog_md5;
