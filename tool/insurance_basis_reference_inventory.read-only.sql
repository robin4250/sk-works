-- Read-only: schema/source metadata and opaque whole-table fingerprints only.
-- No salary rows, personal identifiers, tokens or credentials are returned.
with targets(identity,is_new) as (values
 ('payroll_tax_private.validate_conditions(jsonb)',false),
 ('payroll_tax_private.read_conditions(uuid,uuid)',false),
 ('payroll_tax_private.save_conditions(uuid,uuid,date,bigint,jsonb,boolean)',false),
 ('public.read_worker_payroll_tax_conditions(uuid,uuid)',false),
 ('payroll_tax_private.validate_basis_reference(jsonb)',true),
 ('payroll_tax_private.insurance_income_history(uuid,uuid,date,date)',true),
 ('payroll_tax_private.verify_basis_reference(uuid,uuid,jsonb)',true),
 ('payroll_tax_private.conditions_save_reply(uuid,uuid,boolean)',true),
 ('public.read_worker_payroll_insurance_income_history(uuid,uuid,date,date)',true),
 ('public.read_worker_payroll_tax_conditions_with_insurance_reference(uuid,uuid)',true),
 ('private.account_access_allowed()',false),
 ('private.payroll_settings_allowed(uuid,uuid,text)',false),
 ('private.payroll_document_metadata(uuid)',false)
), routines as (
 select t.identity,jsonb_build_object('is_new',t.is_new,'present',p.oid is not null,
  'source_md5',md5(p.prosrc),'definition',case when not t.is_new then pg_get_functiondef(p.oid) end,
  'owner',pg_get_userbyid(p.proowner),'acl',p.proacl,'config',p.proconfig,
  'definer',p.prosecdef,'volatility',p.provolatile,'return_type',p.prorettype::regtype::text,
  'authenticated_execute',case when p.oid is not null then has_function_privilege('authenticated',p.oid,'EXECUTE') end,
  'anon_execute',case when p.oid is not null then has_function_privilege('anon',p.oid,'EXECUTE') end) item
 from targets t left join pg_proc p on p.oid=to_regprocedure(t.identity)
), tables(identity) as (values
 ('public.companies'),('public.workers'),('payroll_tax_private.worker_conditions'),
 ('payroll_tax_private.condition_history'),('public.payroll_statements'),
 ('public.payroll_adjustments'),('payroll_final_private.documents')
), schemas as (
 select t.identity,jsonb_build_object('oid',c.oid,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl,
  'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
  'columns',(select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
    'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
   from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
   where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)) item
 from tables t left join pg_class c on c.oid=to_regclass(t.identity)
), data_hashes as (
 select 'public.companies' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash
 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.companies t) q
 union all select 'public.workers',count(*),encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.workers t) q
 union all select 'payroll_tax_private.worker_conditions',count(*),encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from payroll_tax_private.worker_conditions t) q
 union all select 'payroll_tax_private.condition_history',count(*),encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from payroll_tax_private.condition_history t) q
 union all select 'public.payroll_statements',count(*),encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.payroll_statements t) q
 union all select 'public.payroll_adjustments',count(*),encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.payroll_adjustments t) q
 union all select 'payroll_final_private.documents',count(*),encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from payroll_final_private.documents t) q
)
select jsonb_build_object('schema',1,
 'routines',(select jsonb_object_agg(identity,item) from routines),
 'tables',(select jsonb_object_agg(identity,item) from schemas),
 'data',(select jsonb_object_agg(identity,jsonb_build_object('count',row_count,'sha256',hash)) from data_hashes),
 'roles',jsonb_build_object('authenticated_tax_usage',has_schema_privilege('authenticated','payroll_tax_private','USAGE'),
  'authenticated_public_usage',has_schema_privilege('authenticated','public','USAGE')),
 'metadata_rows',(select count(*) from payroll_tax_private.worker_conditions where value?'insurance_basis_reference'),
 'metadata_history_rows',(select count(*) from payroll_tax_private.condition_history where after_value?'insurance_basis_reference' or before_value?'insurance_basis_reference')) inventory;
