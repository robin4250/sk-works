-- Read-only: schema/source metadata and opaque whole-table fingerprints only.
-- No salary rows, personal identifiers, tokens or credentials are returned.
with targets(identity,is_new) as (values
 ('company_common_allowance_private.registered_labels(uuid)',true),
 ('public.read_company_registered_allowance_labels(uuid)',true),
 ('company_common_allowance_private.session_id()',false),
 ('private.account_access_allowed()',false),
 ('auth.uid()',false)
), routines as (
 select t.identity,jsonb_build_object('is_new',t.is_new,'present',p.oid is not null,
  'source_md5',md5(p.prosrc),'definition',case when not t.is_new then pg_get_functiondef(p.oid) end,
  'owner',pg_get_userbyid(p.proowner),'acl',p.proacl,'config',p.proconfig,
  'definer',p.prosecdef,'volatility',p.provolatile,'return_type',p.prorettype::regtype::text,
  'authenticated_execute',case when p.oid is not null then has_function_privilege('authenticated',p.oid,'EXECUTE') end,
  'anon_execute',case when p.oid is not null then has_function_privilege('anon',p.oid,'EXECUTE') end,
  'service_execute',case when p.oid is not null then has_function_privilege('service_role',p.oid,'EXECUTE') end) item
 from targets t left join pg_proc p on p.oid=to_regprocedure(t.identity)
), tables(identity) as (values
 ('public.companies'),
 ('public.company_members'),
 ('public.company_rate_settings'),
 ('company_allowance_identity_private.identities'),
 ('company_allowance_identity_private.state'),
 ('company_common_allowance_private.items'),
 ('company_common_allowance_private.state')
), schemas as (
 select t.identity,jsonb_build_object('oid',c.oid,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl,
  'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
  'columns',(select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
    'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
   from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
   where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)) item
 from tables t left join pg_class c on c.oid=to_regclass(t.identity)
), data_hashes as (
 select 'public.companies' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.companies t) q
 union all select 'public.company_members' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.company_members t) q
 union all select 'public.company_rate_settings' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.company_rate_settings t) q
 union all select 'company_allowance_identity_private.identities' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from company_allowance_identity_private.identities t) q
 union all select 'company_allowance_identity_private.state' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from company_allowance_identity_private.state t) q
 union all select 'company_common_allowance_private.items' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from company_common_allowance_private.items t) q
 union all select 'company_common_allowance_private.state' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from company_common_allowance_private.state t) q
)
select jsonb_build_object('schema',1,'catalog_search_path',current_setting('search_path'),
 'routines',(select jsonb_object_agg(identity,item) from routines),
 'tables',(select jsonb_object_agg(identity,item) from schemas),
 'data',(select jsonb_object_agg(identity,jsonb_build_object('count',row_count,'sha256',hash)) from data_hashes),
 'roles',jsonb_build_object('authenticated_private_usage',has_schema_privilege('authenticated','company_common_allowance_private','USAGE'),
  'authenticated_public_usage',has_schema_privilege('authenticated','public','USAGE'))) inventory;
