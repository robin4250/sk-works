-- Isolated transaction ONLY. No IDs or personal rows are embedded here.
DO $isolated_actual_conversion$
DECLARE original jsonb; converted jsonb; retried jsonb; cid uuid; doc uuid;
 subject uuid; month_day date; actor uuid; actor_count integer; expected_revision integer;
 preserved_before jsonb; preserved_after jsonb; other_before jsonb; other_after jsonb;
 matched integer;
BEGIN
 -- Exact original snapshot hash from the previously protected private record.
 SELECT count(*) INTO matched FROM public.payment_certificates p
 WHERE md5(to_jsonb(p)::text)='558302f271e0033a2a76299c16ea8b78';
 IF matched<>1 THEN RAISE EXCEPTION 'protected original no longer matches isolated archive'; END IF;
 SELECT to_jsonb(p) INTO original FROM public.payment_certificates p
 WHERE md5(to_jsonb(p)::text)='558302f271e0033a2a76299c16ea8b78';
 cid:=(original->>'company_id')::uuid; doc:=(original->>'id')::uuid;
 subject:=(original->>'partner_company_id')::uuid; month_day:=(original->>'period_start')::date;
 expected_revision:=(original->>'revision')::integer;
 IF original->>'status'<>'draft' OR (original->>'gross_amount')::numeric<>1000
 OR (original->>'deductions')::numeric<>0 OR (original->>'net_amount')::numeric<>1000
 OR (original->'snapshot'->>'expense_extra_amount_yen')::numeric<>1000
 THEN RAISE EXCEPTION 'protected legacy amount is not the reported 1000 draft'; END IF;
 SELECT count(*) INTO actor_count FROM public.company_members WHERE company_id=cid AND role::text='owner';
 IF actor_count<>1 THEN RAISE EXCEPTION 'unique existing owner required for isolated claims context'; END IF;
 SELECT user_id INTO actor FROM public.company_members WHERE company_id=cid AND role::text='owner';
 -- Actual restored memberships/access helpers, simulated DB claims only.
 -- This does not prove an issued JWT or a real HTTP login.
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 IF auth.uid() IS DISTINCT FROM actor OR private.account_access_allowed() IS NOT TRUE
 THEN RAISE EXCEPTION 'existing owner access denied'; END IF;
 SELECT jsonb_build_object(
 'claims',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]') FROM private.expense_claims x),
 'choices',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]') FROM private.expense_settlement_choices x),
 'consumptions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]') FROM private.expense_amount_consumptions x),
 'snapshots',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]') FROM private.expense_document_snapshots x)) INTO preserved_before;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]') INTO other_before
 FROM public.payment_certificates x WHERE id<>doc;
 -- Test-only gates, restricted to the exact restored company, rolled back.
 EXECUTE format('CREATE OR REPLACE FUNCTION private.expense_cost_direction_v2_enabled(cid uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path='''' AS %L',
 'select cid='||quote_literal(cid::text)||'::uuid');
 EXECUTE format('CREATE OR REPLACE FUNCTION private.expense_direction_v2_client_rollout_verified(cid uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path='''' AS %L',
 'select cid='||quote_literal(cid::text)||'::uuid');
 converted:=private.convert_payment_expense_v1_draft(cid,doc,subject,month_day,expected_revision,
 original,md5(original::text),'isolated verified native archive and original private record',
 'isolated test only; production client exclusion NOT verified');
 IF converted->>'id' IS DISTINCT FROM original->>'id'
 OR (converted->>'revision')::integer IS DISTINCT FROM expected_revision+1
 OR (converted->>'gross_amount')::numeric IS DISTINCT FROM 0
 OR (converted->>'deductions')::numeric IS DISTINCT FROM 1000
 OR (converted->>'net_amount')::numeric IS DISTINCT FROM -1000
 THEN RAISE EXCEPTION 'actual expense conversion amounts or identity differ'; END IF;
 retried:=private.convert_payment_expense_v1_draft(cid,doc,subject,month_day,expected_revision,
 original,md5(original::text),'isolated verified native archive and original private record',
 'isolated test only; production client exclusion NOT verified');
 IF retried IS DISTINCT FROM converted THEN RAISE EXCEPTION 'identical retry changed result'; END IF;
 IF (SELECT count(*) FROM private.expense_payment_direction_conversions WHERE document_id=doc)<>1
 OR NOT EXISTS(SELECT 1 FROM private.expense_payment_direction_conversions
 WHERE document_id=doc AND before_row=original AND after_row=converted AND actor_id=actor)
 THEN RAISE EXCEPTION 'actual conversion audit differs'; END IF;
 SELECT jsonb_build_object(
 'claims',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]') FROM private.expense_claims x),
 'choices',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]') FROM private.expense_settlement_choices x),
 'consumptions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]') FROM private.expense_amount_consumptions x),
 'snapshots',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]') FROM private.expense_document_snapshots x)) INTO preserved_after;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]') INTO other_after
 FROM public.payment_certificates x WHERE id<>doc;
 IF preserved_after IS DISTINCT FROM preserved_before OR other_after IS DISTINCT FROM other_before
 THEN RAISE EXCEPTION 'conversion changed settlement history or another document'; END IF;
 IF has_function_privilege('anon','private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)','EXECUTE')
 OR has_function_privilege('authenticated','private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)','EXECUTE')
 OR has_function_privilege('service_role','private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'conversion function exposed to a client role'; END IF;
END $isolated_actual_conversion$;
