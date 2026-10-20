-- Native isolated restored DB only. Simulated claims, not an issued JWT.
DO $isolated_negotiation$
DECLARE doc uuid; cid uuid; actor uuid; rejected boolean; matches integer;
BEGIN
 SELECT count(*) INTO matches FROM private.expense_payment_direction_conversions;
 IF matches<>1 THEN RAISE EXCEPTION 'one isolated converted draft required'; END IF;
 SELECT document_id,company_id,actor_id INTO doc,cid,actor FROM private.expense_payment_direction_conversions;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM set_config('request.headers','{}',true);
 IF EXISTS(SELECT 1 FROM public.payment_certificates WHERE id=doc)
 THEN RAISE EXCEPTION 'legacy request can see directional row'; END IF;
 rejected:=false;
 BEGIN PERFORM * FROM public.payment_certificate_detail_rows(doc);
 EXCEPTION WHEN SQLSTATE '42501' THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'legacy detail RPC was not rejected'; END IF;
 rejected:=false;
 BEGIN PERFORM public.read_expense_document('paymentCertificate',doc);
 EXCEPTION WHEN SQLSTATE '42501' THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'legacy expense RPC was not rejected'; END IF;
 PERFORM set_config('request.headers','{"x-sko-payment-source-version":"2"}',true);
 IF NOT EXISTS(SELECT 1 FROM public.payment_certificates WHERE id=doc AND company_id=cid AND gross_amount=0 AND deductions=1000 AND net_amount=-1000)
 THEN RAISE EXCEPTION 'supported owner cannot read exact directional row'; END IF;
 PERFORM * FROM public.payment_certificate_detail_rows(doc);
 IF public.read_expense_document('paymentCertificate',doc)->'expense_cost_direction_v2'->>'amount_yen' IS DISTINCT FROM '1000'
 THEN RAISE EXCEPTION 'supported expense RPC amount differs'; END IF;
 PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000099',true);
 PERFORM set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated"}',true);
 IF EXISTS(SELECT 1 FROM public.payment_certificates WHERE id=doc)
 THEN RAISE EXCEPTION 'header granted another user document access'; END IF;
 EXECUTE 'RESET ROLE';
END $isolated_negotiation$;
