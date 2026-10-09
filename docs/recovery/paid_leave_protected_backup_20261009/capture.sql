-- TEMPLATE ONLY: never pass real scope or output to Git/CI/public messages.
-- Requires psql variable sko_paid_leave_scope_json: JSON array of
-- objects with company_id and worker_id, provided from a protected local file.
-- No defaults, no UUIDs, no production connection, no data mutation.
\set ON_ERROR_STOP on
\set QUIET on
\pset format unaligned
\pset tuples_only on
\if :{?sko_paid_leave_scope_json}
\else
\echo 'Missing protected scope; no query was run.'
\quit 3
\endif
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '45s';
WITH scope AS (
 SELECT DISTINCT company_id,worker_id
 FROM jsonb_to_recordset(:'sko_paid_leave_scope_json'::jsonb)
 AS s(company_id uuid,worker_id uuid)
), bounds AS (
 SELECT (current_timestamp AT TIME ZONE 'Asia/Tokyo')::date today,
 date_trunc('month',current_timestamp AT TIME ZONE 'Asia/Tokyo')::date start_day,
 (date_trunc('month',current_timestamp AT TIME ZONE 'Asia/Tokyo')+interval '1 month - 1 day')::date end_day
), statements AS (
 -- All periods for the selected pairs: protected history is a comparison baseline.
 SELECT p.* FROM public.payroll_statements p JOIN scope s USING(company_id,worker_id)
), periods AS (
 SELECT s.company_id,s.worker_id,b.start_day,b.end_day FROM scope s CROSS JOIN bounds b
 UNION SELECT company_id,worker_id,period_start,period_end FROM statements
), eligible AS (
 -- Mirror the current-month new scheduler's candidate selection without calling it.
 SELECT p.company_id,p.worker_id FROM public.worker_payroll_settings p
 JOIN public.workers w ON w.id=p.worker_id AND w.company_id=p.company_id
 JOIN public.companies c ON c.id=w.company_id CROSS JOIN bounds b
 WHERE ((p.pay_type='monthly' AND coalesce(p.monthly_salary_yen,0)>0)
 OR EXISTS(SELECT 1 FROM public.paid_leave_requests l
 WHERE l.company_id=p.company_id AND l.worker_id=p.worker_id AND l.status='approved'
 AND l.leave_date BETWEEN b.start_day AND b.today))
 AND w.status::text='active' AND w.affiliation::text='employee'
 AND (w.hire_date IS NULL OR w.hire_date<=b.end_day)
), function_signatures(signature) AS (VALUES
 ('private.refresh_automatic_payroll_internal(uuid,uuid,date)'),
 ('private.sync_payroll_attendance_detail(uuid,uuid,date)'),
 ('private.paid_leave_sync_payroll_detail()'),
 ('private.payroll_condition_warnings(uuid,uuid,date,date)'),
 ('private.ensure_monthly_payroll_drafts(date)'),
 ('private.apply_monthly_salary_detail()'),
 ('private.apply_monthly_salary_to_statement()'),
 ('private.apply_payroll_custom_money()'),
 ('private.attendance_refresh_payroll()'),
 ('private.attendance_sync_payroll_detail()'),
 ('private.settings_refresh_payroll()'),
 ('private.payroll_approver_ids(uuid)'),
 ('private.refresh_automatic_payroll(uuid,uuid,date)'),
 ('private.document_company_seal_snapshot(jsonb,uuid,boolean)'),
 ('private.preserve_document_company_seal_snapshot()'),
 ('private.payroll_document_metadata(uuid)'),
 ('public.company_seal_style_settings(uuid)'),
 ('public.save_company_seal_style(uuid,text,text)'),
 ('private.aoyagi_reisho_name_supported(text)'),
 ('public.paid_leave_wage_contract_version()'),
 ('private.paid_leave_daily_amount(jsonb)')
), trigger_signatures AS (
 SELECT DISTINCT p.oid::regprocedure::text signature
 FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
 JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE NOT t.tgisinternal AND n.nspname='public' AND c.relname IN
 ('companies','worker_payroll_settings','payroll_statements','attendance_entries',
 'paid_leave_requests','invoices','payment_certificates','payroll_adjustments')
), all_function_signatures AS (
 SELECT signature FROM function_signatures UNION SELECT signature FROM trigger_signatures
), functions AS (
 SELECT f.signature,p.oid,pg_get_functiondef(p.oid) definition,
 md5(pg_get_functiondef(p.oid)) definition_md5,pg_get_userbyid(p.proowner) owner,
 p.proacl,p.proconfig,p.prosecdef,p.provolatile
 FROM all_function_signatures f LEFT JOIN pg_proc p ON p.oid=to_regprocedure(f.signature)
), target_tables AS (
 SELECT c.oid,n.nspname,c.relname,pg_get_userbyid(c.relowner) owner,
 c.relacl,c.relrowsecurity,c.relforcerowsecurity
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relname IN
 ('companies','workers','worker_payroll_settings','payroll_statements',
 'attendance_entries','paid_leave_requests','invoices','payment_certificates',
 'site_calculation_source_preferences','trade_company_contracts','trade_companies',
 'payroll_confirmers','payroll_statement_reviews','payroll_audit','payroll_adjustments')
), company_inputs AS (
 SELECT c.id,c.payroll_payment_day,c.payroll_payment_month_offset,c.payroll_closing_day,
 c.name,c.company_seal_enabled,c.company_seal_style
 FROM public.companies c WHERE c.id IN(SELECT company_id FROM scope)
), worker_inputs AS (
 SELECT w.id,w.company_id,w.status,w.affiliation,w.hire_date
 FROM public.workers w JOIN scope s ON s.company_id=w.company_id AND s.worker_id=w.id
), settings AS (
 -- Fingerprint uses every settings key except updated_at/payment_day: save full rows.
 SELECT p.* FROM public.worker_payroll_settings p JOIN scope s USING(company_id,worker_id)
), attendance AS (
 -- Fingerprint includes whole rows except timestamps; retaining timestamps aids comparison.
 SELECT a.* FROM public.attendance_entries a WHERE EXISTS(SELECT 1 FROM periods p
 WHERE p.company_id=a.company_id AND p.worker_id=a.worker_id
 AND a.work_date BETWEEN p.start_day AND p.end_day)
), leaves AS (
 SELECT l.id,l.company_id,l.worker_id,l.leave_date,l.status
 FROM public.paid_leave_requests l WHERE EXISTS(SELECT 1 FROM periods p
 WHERE p.company_id=l.company_id AND p.worker_id=l.worker_id
 AND l.leave_date BETWEEN p.start_day AND p.end_day)
), preferences AS (
 -- Fingerprint uses all company payroll preferences, not only attended sites.
 SELECT p.* FROM public.site_calculation_source_preferences p
 WHERE p.output_type='payroll' AND p.company_id IN(SELECT company_id FROM scope)
), contracts AS (
 SELECT c.* FROM public.trade_company_contracts c WHERE EXISTS(SELECT 1 FROM preferences p
 WHERE p.company_id=c.company_id AND p.trade_company_id=c.trade_company_id)
), trade_inputs AS (
 SELECT t.* FROM public.trade_companies t WHERE EXISTS(SELECT 1 FROM preferences p
 WHERE p.company_id=t.company_id AND p.trade_company_id=t.id)
)
SELECT jsonb_build_object(
 'format','sko-paid-leave-protected-backup-v1','captured_at',current_timestamp,
 'server_version',current_setting('server_version'),'transaction_read_only',current_setting('transaction_read_only'),
 'scope',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY company_id,worker_id),'[]') FROM scope s),
 'bounds',(SELECT to_jsonb(b) FROM bounds b),
 'scope_checks',jsonb_build_object(
 'scope_count',(SELECT count(*) FROM scope),
 'null_scope_pairs',(SELECT count(*) FROM scope WHERE company_id IS NULL OR worker_id IS NULL),
 'missing_worker_pairs',(SELECT count(*) FROM scope s WHERE NOT EXISTS(SELECT 1 FROM worker_inputs w WHERE w.company_id=s.company_id AND w.id=s.worker_id)),
 'scheduler_candidates',(SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY company_id,worker_id),'[]') FROM eligible e),
 'scheduler_candidates_outside_scope',(SELECT count(*) FROM eligible e WHERE NOT EXISTS(SELECT 1 FROM scope s WHERE s.company_id=e.company_id AND s.worker_id=e.worker_id)),
 'required_functions_missing',(SELECT count(*) FROM functions WHERE oid IS NULL AND signature NOT IN('public.paid_leave_wage_contract_version()','private.paid_leave_daily_amount(jsonb)'))),
 'functions',(SELECT jsonb_agg(to_jsonb(f) ORDER BY signature) FROM functions f),
 'tables',(SELECT jsonb_agg(to_jsonb(t) ORDER BY nspname,relname) FROM target_tables t),
 'columns',(SELECT jsonb_agg(jsonb_build_object('table_oid',a.attrelid,'name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,'acl',a.attacl,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attrelid,a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid IN(SELECT oid FROM target_tables) AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT jsonb_agg(jsonb_build_object('table_oid',c.conrelid,'name',c.conname,'definition',pg_get_constraintdef(c.oid),'validated',c.convalidated,'deferrable',c.condeferrable,'deferred',c.condeferred) ORDER BY c.conrelid,c.conname) FROM pg_constraint c WHERE c.conrelid IN(SELECT oid FROM target_tables)),
 'policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.schemaname,p.tablename,p.policyname) FROM pg_policies p WHERE p.schemaname='public' AND p.tablename IN(SELECT relname FROM target_tables)),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('oid',t.oid,'table_oid',t.tgrelid,'name',t.tgname,'enabled',t.tgenabled,'function_oid',t.tgfoid,'definition',pg_get_triggerdef(t.oid)) ORDER BY t.tgrelid,t.tgname) FROM pg_trigger t WHERE t.tgrelid IN(SELECT oid FROM target_tables) AND NOT t.tgisinternal),
 'cron',(SELECT coalesce(jsonb_agg(to_jsonb(j) ORDER BY jobid),'[]') FROM cron.job j WHERE j.jobname='payroll-confirmation-daily-jst'),
 'migration_ledger',(SELECT coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) ORDER BY version),'[]') FROM supabase_migrations.schema_migrations),
 'companies',(SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY id),'[]') FROM company_inputs c),
 'workers',(SELECT coalesce(jsonb_agg(to_jsonb(w) ORDER BY id),'[]') FROM worker_inputs w),
 'settings',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY company_id,worker_id),'[]') FROM settings s),
 'statements',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]') FROM statements p),
 'attendance',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY work_date,id),'[]') FROM attendance a),
 'leaves',(SELECT coalesce(jsonb_agg(to_jsonb(l) ORDER BY leave_date,id),'[]') FROM leaves l),
 'preferences',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY company_id,site_id),'[]') FROM preferences p),
 'contracts',(SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY company_id,trade_company_id),'[]') FROM contracts c),
 'trade_companies',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY company_id,id),'[]') FROM trade_inputs t),
 'confirmers',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY company_id,position),'[]') FROM public.payroll_confirmers p WHERE p.company_id IN(SELECT company_id FROM scope)),
 'reviews',(SELECT coalesce(jsonb_agg(to_jsonb(r)),'[]') FROM public.payroll_statement_reviews r WHERE r.statement_id IN(SELECT id FROM statements)),
 'adjustments',(SELECT coalesce(jsonb_agg(to_jsonb(a)),'[]') FROM public.payroll_adjustments a JOIN scope s USING(company_id,worker_id)),
 'audit',(SELECT coalesce(jsonb_agg(to_jsonb(a)),'[]') FROM public.payroll_audit a WHERE a.statement_id IN(SELECT id FROM statements))
);
COMMIT;
