-- READ ONLY. No user/account/session rows, JWTs, keys or credentials returned.
-- Execute inside BEGIN READ ONLY; SET LOCAL search_path=''; SELECT...; ROLLBACK.
with context as materialized(select set_config('search_path','',true)), targets(identity) as(values ('private.account_access_allowed()'),('public.is_current_user_master_admin()'),('private.account_deletion_barrier_key(uuid)'),('auth.uid()'),('auth.jwt()'),('auth.role()'),('extensions.digest(text,text)'),('private.reauthentication_scope(text)'),('private.reauthentication_required(text)'),('public.reauthentication_capabilities()'),('public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text)'),('private.consume_reauthentication_proof(text,jsonb,text)'),('private.ingest_security_collector_event(jsonb)'),('private.read_security_collector_events(text)'),('public.master_security_collector_events(text)'),('public.set_secondary_password(text)'),('public.set_master_feature_enabled(text,boolean)'),('public.set_master_device_locked(uuid,boolean)')),
routines as(select t.identity,jsonb_build_object('present',p.oid is not null,'source_md5',md5(p.prosrc),
 'attributes',to_jsonb(p)-'prosrc','definition',case when p.oid is not null then pg_get_functiondef(p.oid) end) item
 from targets t cross join context left join pg_proc p on p.oid=to_regprocedure(t.identity)),
target_tables(identity) as(values ('public.companies'),('public.company_members'),('public.workers'),('public.worker_payroll_settings'),('public.payroll_statements'),('public.payroll_adjustments'),('public.invoices'),('private.master_admins'),('private.master_devices'),('private.account_deletion_access_restrictions'),('private.reauthentication_rollout'),('private.reauthentication_proofs'),('private.security_collector_control'),('private.security_collector_events'),('private.security_collector_read_audit'),('auth.sessions')),
relations as(select t.identity,jsonb_build_object('present',c.oid is not null,'attributes',to_jsonb(c),
 'columns',(select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('type',format_type(a.atttypid,a.atttypmod),'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum),'[]') from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
 'constraints',(select coalesce(jsonb_agg(to_jsonb(k)||jsonb_build_object('definition',pg_get_constraintdef(k.oid)) order by k.oid),'[]') from pg_constraint k where k.conrelid=c.oid),
 'policies',(select coalesce(jsonb_agg(to_jsonb(p) order by p.oid),'[]') from pg_policy p where p.polrelid=c.oid),
 'triggers',(select coalesce(jsonb_agg(to_jsonb(g)||jsonb_build_object('definition',pg_get_triggerdef(g.oid)) order by g.oid),'[]') from pg_trigger g where g.tgrelid=c.oid)) item
 from target_tables t cross join context left join pg_class c on c.oid=to_regclass(t.identity)),
data_hashes as(
select 'public.companies' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') sha256 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.companies t) q
union all
select 'public.company_members' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') sha256 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.company_members t) q
union all
select 'public.workers' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') sha256 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.workers t) q
union all
select 'public.worker_payroll_settings' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') sha256 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.worker_payroll_settings t) q
union all
select 'public.payroll_statements' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') sha256 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.payroll_statements t) q
union all
select 'public.payroll_adjustments' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') sha256 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.payroll_adjustments t) q
union all
select 'public.invoices' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') sha256 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from public.invoices t) q
union all
select 'private.master_admins' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') sha256 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from private.master_admins t) q
union all
select 'private.master_devices' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') sha256 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from private.master_devices t) q
union all
select 'private.account_deletion_access_restrictions' identity,count(*) row_count,encode(sha256(convert_to(coalesce(string_agg(h,'' order by h),''),'UTF8')),'hex') sha256 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') h from private.account_deletion_access_restrictions t) q
), bridge as(select to_jsonb(r)-'rolpassword' item from pg_roles r where rolname='sko_security_collector_ingest')
select jsonb_build_object('schema',1,'catalog_search_path',current_setting('search_path'),
 'routines',(select jsonb_object_agg(identity,item) from routines),
 'relations',(select jsonb_object_agg(identity,item) from relations),
 'business',(select jsonb_object_agg(identity,jsonb_build_object('count',row_count,'sha256',sha256)) from data_hashes),
 'bridge_role',(select item from bridge),
 'bridge_credential_absent',not exists(select 1 from pg_authid where rolname='sko_security_collector_ingest' and rolpassword is not null),
 'bridge_dependencies',(select count(*) from pg_shdepend where refclassid='pg_authid'::regclass and refobjid=(select oid from pg_roles where rolname='sko_security_collector_ingest')),
 'bridge_memberships',(select coalesce(jsonb_agg(to_jsonb(m) order by m.roleid,m.member),'[]') from pg_auth_members m where m.roleid=(select oid from pg_roles where rolname='sko_security_collector_ingest') or m.member=(select oid from pg_roles where rolname='sko_security_collector_ingest')),
 'private_schema',(select to_jsonb(n) from pg_namespace n where nspname='private'),
 'authenticated_private_usage',has_schema_privilege('authenticated','private','USAGE'),
 'roles',(select jsonb_object_agg(rolname,to_jsonb(r)-'rolpassword') from pg_roles r where rolname in ('postgres','anon','authenticated','service_role'))
) inventory from context;

