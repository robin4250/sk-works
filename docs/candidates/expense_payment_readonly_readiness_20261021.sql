-- READ ONLY: catalog metadata only; does not call application functions or read financial rows.
-- Run on a dedicated read-only connection. This is an inventory, NOT rollout authorization.
WITH wanted(signature,stage) AS (VALUES
 ('private.refresh_automatic_payment_certificate(uuid,uuid,date)','direction_backend'),
 ('private.expense_cost_finalize()','direction_backend'),
 ('private.read_expense_document(text,uuid)','direction_backend'),
 ('private.expense_cost_direction_v2_enabled(uuid)','direction_backend'),
 ('private.expense_payment_v2_envelope(uuid,uuid,uuid,date,integer,numeric,jsonb)','direction_backend'),
 ('private.expense_payment_v2_guard()','direction_backend'),
 ('private.expense_payment_direction_capability(uuid)','direction_backend'),
 ('public.expense_payment_direction_capability(uuid)','direction_backend'),
 ('private.payment_expense_v2_requested()','source_negotiation'),
 ('public.payment_certificate_detail_rows(uuid)','source_negotiation'),
 ('private.expense_direction_v2_client_rollout_verified(uuid)','explicit_conversion'),
 ('private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)','explicit_conversion')
), function_inventory AS (
 SELECT w.stage,w.signature,p.oid IS NOT NULL present,
  md5(p.prosrc) source_md5,r.rolname owner_name,p.prosecdef security_definer,p.proconfig settings,
  CASE WHEN w.signature IN ('private.expense_cost_direction_v2_enabled(uuid)',
   'private.expense_direction_v2_client_rollout_verified(uuid)') AND p.oid IS NOT NULL
   THEN btrim(p.prosrc)='select false' ELSE NULL END constant_off_source,
  CASE WHEN p.oid IS NULL THEN NULL ELSE has_function_privilege('anon',p.oid,'EXECUTE') END anon_execute,
  CASE WHEN p.oid IS NULL THEN NULL ELSE has_function_privilege('authenticated',p.oid,'EXECUTE') END authenticated_execute
 FROM wanted w LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(w.signature)
 LEFT JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
)
SELECT jsonb_build_object(
 'schema',1,'inventory_only',true,
 'functions',(SELECT jsonb_agg(to_jsonb(f) ORDER BY f.stage,f.signature) FROM function_inventory f),
 'payment_rls_enabled',(SELECT c.relrowsecurity FROM pg_catalog.pg_class c
  WHERE c.oid=pg_catalog.to_regclass('public.payment_certificates')),
 'source_negotiation_policy',(SELECT jsonb_build_object('present',true,'permissive',p.polpermissive,
  'command',p.polcmd,'qual_md5',md5(pg_catalog.pg_get_expr(p.polqual,p.polrelid)))
  FROM pg_catalog.pg_policy p WHERE p.polrelid=pg_catalog.to_regclass('public.payment_certificates')
  AND p.polname='payment_expense_source_compatibility'),
 'conversion_receipt_table_present',pg_catalog.to_regclass('private.expense_payment_direction_conversions') IS NOT NULL,
 'v2_guard_trigger',(SELECT jsonb_build_object('enabled',t.tgenabled,'type',t.tgtype,
  'function_matches',t.tgfoid=pg_catalog.to_regprocedure('private.expense_payment_v2_guard()'))
  FROM pg_catalog.pg_trigger t WHERE t.tgrelid=pg_catalog.to_regclass('public.payment_certificates')
  AND t.tgname='expense_direction_v2_guard' AND NOT t.tgisinternal)
) AS inventory;
