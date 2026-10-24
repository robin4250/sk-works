-- Read-only catalog + opaque whole-table fingerprints; no financial/Auth rows returned.
with context as materialized(select set_config('search_path','',true) setting), targets(identity) as(values ('private.apply_payroll_custom_money()'),('private.refresh_automatic_payroll_internal(uuid,uuid,date)'),('public.sign_daily_report(uuid,text,jsonb)'),('payroll_unit_private.resolve_company_common(uuid,uuid,date,date)'),('payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)'),('company_common_canonical_review_private.resolve_legacy(uuid,uuid,date,date,jsonb,bigint,date)'),('private.sync_payroll_attendance_detail(uuid,uuid,date)'),('private.attendance_sync_payroll_detail()'),('public.save_daily_report_draft(uuid,uuid,date,text,jsonb)'),('public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)'),('private.attendance_refresh_payroll()'),('private.refresh_automatic_payroll(uuid,uuid,date)'),('public.save_daily_report_signature(uuid,text,text,jsonb)'),('private.save_daily_report_signature(uuid,text,text,jsonb)'),('payroll_unit_private.resolve(uuid,uuid,date,date)'),('private.account_access_allowed()'),('company_common_allowance_private.session_id()'),('company_common_allowance_private.registered_labels(uuid)'),('public.read_company_registered_allowance_labels(uuid)'),('public.company_checkout_allowance_contract_version()'),('public.read_daily_report_company_allowance_eligibility(uuid)')), routines as(
 select t.identity,jsonb_build_object('present',p.oid is not null,'definition',case when p.oid is not null then pg_get_functiondef(p.oid) end,
 'source_md5',md5(p.prosrc),'attributes',to_jsonb(p)-'prosrc') item from targets t cross join context ctx left join pg_proc p on p.oid=to_regprocedure(t.identity)
), relations as(
 select n.nspname||'.'||c.relname identity,jsonb_build_object('oid',c.oid,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl,
 'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'columns',(select jsonb_agg(jsonb_build_object('name',a.attname,
 'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
 from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
 where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)) item
 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join context ctx where c.oid in(to_regclass('public.company_members'),to_regclass('public.workers'),to_regclass('public.worker_payroll_settings'),to_regclass('public.payroll_statements'),to_regclass('public.payroll_adjustments'),to_regclass('public.daily_reports'),to_regclass('public.daily_report_workers'),to_regclass('public.attendance_entries'),to_regclass('public.company_rate_settings'),to_regclass('company_allowance_identity_private.state'),to_regclass('company_allowance_identity_private.identities'),to_regclass('company_common_allowance_private.state'),to_regclass('company_common_allowance_private.items'),to_regclass('company_common_allowance_private.payroll_publications'),to_regclass('company_common_allowance_private.payroll_activation'),to_regclass('company_common_allowance_private.payroll_type_activation'),to_regclass('company_common_allowance_private.payroll_activation_modes'),to_regclass('payroll_unit_private.conditions'),to_regclass('payroll_unit_private.quantities'))
), data_hashes as(
 select 'public.company_members' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from public.company_members t) hashed
 union all
 select 'public.workers' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from public.workers t) hashed
 union all
 select 'public.worker_payroll_settings' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from public.worker_payroll_settings t) hashed
 union all
 select 'public.payroll_statements' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from public.payroll_statements t) hashed
 union all
 select 'public.payroll_adjustments' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from public.payroll_adjustments t) hashed
 union all
 select 'public.daily_reports' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from public.daily_reports t) hashed
 union all
 select 'public.daily_report_workers' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t)-'company_allowance_selections'-'company_allowance_legacy_labels')::text,'UTF8')),'hex') h from public.daily_report_workers t) hashed
 union all
 select 'public.attendance_entries' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t)-'company_allowance_receipt_id')::text,'UTF8')),'hex') h from public.attendance_entries t) hashed
 union all
 select 'public.company_rate_settings' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from public.company_rate_settings t) hashed
 union all
 select 'company_allowance_identity_private.state' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from company_allowance_identity_private.state t) hashed
 union all
 select 'company_allowance_identity_private.identities' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from company_allowance_identity_private.identities t) hashed
 union all
 select 'company_common_allowance_private.state' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from company_common_allowance_private.state t) hashed
 union all
 select 'company_common_allowance_private.items' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from company_common_allowance_private.items t) hashed
 union all
 select 'company_common_allowance_private.payroll_publications' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from company_common_allowance_private.payroll_publications t) hashed
 union all
 select 'company_common_allowance_private.payroll_activation' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from company_common_allowance_private.payroll_activation t) hashed
 union all
 select 'company_common_allowance_private.payroll_type_activation' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from company_common_allowance_private.payroll_type_activation t) hashed
 union all
 select 'company_common_allowance_private.payroll_activation_modes' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from company_common_allowance_private.payroll_activation_modes t) hashed
 union all
 select 'payroll_unit_private.conditions' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from payroll_unit_private.conditions t) hashed
 union all
 select 'payroll_unit_private.quantities' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') hash from (select encode(sha256(convert_to((to_jsonb(t))::text,'UTF8')),'hex') h from payroll_unit_private.quantities t) hashed
) select jsonb_build_object('schema',1,'routines',(select jsonb_object_agg(identity,item) from routines),
 'relations',(select jsonb_object_agg(identity,item) from relations),'data',(select jsonb_object_agg(identity,jsonb_build_object('row_count',row_count,'hash',hash)) from data_hashes),
 'private_schema_present',to_regnamespace('company_checkout_allowance_private') is not null,
 'trigger_catalog',(select coalesce(jsonb_agg(jsonb_build_object('relation',t.tgrelid::regclass::text,'name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid)) order by t.tgrelid,t.tgname),'[]') from pg_trigger t cross join context context_trigger where not t.tgisinternal and t.tgrelid in('public.daily_reports'::regclass,'public.daily_report_workers'::regclass,'public.attendance_entries'::regclass,'public.payroll_statements'::regclass)),
 'role_access',jsonb_build_object('authenticated_common_usage',has_schema_privilege('authenticated','company_common_allowance_private','USAGE'))
) inventory from context context_final;
