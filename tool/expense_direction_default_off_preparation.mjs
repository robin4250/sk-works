// Offline preparation only: does not connect, deploy, enable gates or convert rows.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {catalogSql,oldFunctions,newFunctions} from './expense_direction_code_checkpoint.mjs';

const reviewedSha256='36b64b32aff558aa99e264aea6439a747d7de9b3166dc55fe24adc241963f987';
const reviewedSourceMd5={
 'private.expense_cost_direction_v2_enabled(uuid)':'9f038cd8f856dc2fad5b866160f26637',
 'private.expense_cost_finalize()':'22ff4377666ec56ccc4b261cf380e9c0',
 'private.expense_payment_direction_capability(uuid)':'72c86b51bc0c6ae5c283e9868834fb54',
 'private.expense_payment_v2_envelope(uuid,uuid,uuid,date,integer,numeric,jsonb)':'52dcf11a021a6584621527aeacbf6e37',
 'private.expense_payment_v2_guard()':'4d08bd0b372a3048b9eb52dd99a3c321',
 'private.read_expense_document(text,uuid)':'85a16c6a5181c4f4ee85316f69a288cb',
 'private.refresh_automatic_payment_certificate(uuid,uuid,date)':'5828ec68ad83ace5f0c0fc8f21851cf8',
 'public.expense_payment_direction_capability(uuid)':'23d08c31cf55263869f09be3967f42a7',
};
const quote=(text,tag)=>{
  assert(!text.includes(`$${tag}$`),'SQL delimiter collision');
  return `$${tag}$${text}$${tag}$`;
};
// Hash values stay in the database; generated SQL never embeds business rows.
const businessHashSql=`select md5(jsonb_build_object(
 'payments',(select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') from public.payment_certificates x),
 'claims',(select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') from private.expense_claims x),
 'choices',(select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') from private.expense_settlement_choices x),
 'consumptions',(select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') from private.expense_amount_consumptions x),
 'snapshots',(select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') from private.expense_document_snapshots x)
)::text)`;

export function buildDefaultOffDeployment(before,candidate){
  assert.equal(createHash('sha256').update(candidate).digest('hex'),reviewedSha256,'candidate is not the independently reviewed OFF-compatible source');
  assert.deepEqual(before.functions.map(x=>x.signature).sort(),[...oldFunctions].sort(),'existing function scope differs');
  assert(Array.isArray(before.triggers)&&Array.isArray(before.event_triggers),'complete trigger checkpoint required');
  const expected=quote(JSON.stringify(before),'sko_expense_before');
  const existingSignatures=quote(JSON.stringify(oldFunctions),'sko_expense_old');
  const newSignatures=quote(JSON.stringify(newFunctions),'sko_expense_new');
  const expectedSources=quote(JSON.stringify(reviewedSourceMd5),'sko_expense_sources');
  return `-- REVIEW ONLY. Requires a dedicated connection: ROLLBACK on any error.
-- OFF preserves the generator path; it does not prohibit all direct DB writes.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';
LOCK TABLE public.payment_certificates,private.expense_claims,private.expense_settlement_choices,private.expense_amount_consumptions,private.expense_document_snapshots IN SHARE ROW EXCLUSIVE MODE NOWAIT;
CREATE TEMP TABLE sko_expense_off_before ON COMMIT DROP AS
 SELECT (SELECT value FROM (${catalogSql}) catalog) checkpoint,
 (${businessHashSql}) business_hash;
DO $sko_preflight$
BEGIN
 IF (SELECT checkpoint FROM sko_expense_off_before) IS DISTINCT FROM ${expected}::jsonb THEN RAISE EXCEPTION 'expense checkpoint drift'; END IF;
 IF EXISTS(SELECT 1 FROM public.payment_certificates WHERE snapshot?'expense_cost_direction_v2' OR snapshot?'expense_cost_basis') THEN RAISE EXCEPTION 'existing v2/basis rows need separate review'; END IF;
 IF to_regclass('private.expense_payment_direction_conversions') IS NOT NULL OR to_regprocedure('private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)') IS NOT NULL OR to_regprocedure('private.expense_direction_v2_client_rollout_verified(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'conversion or rollout installation outside code-only recovery scope'; END IF;
END $sko_preflight$;
${candidate}
DO $sko_postflight$
DECLARE actual jsonb; previous jsonb; f jsonb; signature text; row_before jsonb; expected_authenticated boolean; function_oid oid; expected_definer boolean; expected_volatility text;
BEGIN
 SELECT value INTO actual FROM (${catalogSql}) c;
 SELECT checkpoint INTO previous FROM sko_expense_off_before;
 IF jsonb_array_length(actual->'functions')<>8 THEN RAISE EXCEPTION 'unexpected deployed function scope'; END IF;
 FOR signature IN SELECT jsonb_array_elements_text(${existingSignatures}::jsonb) LOOP
  SELECT value INTO f FROM jsonb_array_elements(actual->'functions') WHERE value->>'signature'=signature;
  SELECT value INTO row_before FROM jsonb_array_elements(previous->'functions') WHERE value->>'signature'=signature;
  IF (f-'definition'-'source_md5') IS DISTINCT FROM (row_before-'definition'-'source_md5') THEN RAISE EXCEPTION 'existing function metadata changed'; END IF;
 END LOOP;
 IF actual->'event_triggers' IS DISTINCT FROM previous->'event_triggers' THEN RAISE EXCEPTION 'event trigger drift'; END IF;
 FOR row_before IN SELECT value FROM jsonb_array_elements(previous->'triggers') LOOP
  SELECT value INTO f FROM jsonb_array_elements(actual->'triggers') WHERE value->>'oid'=row_before->>'oid';
  IF row_before->>'function'='private.expense_cost_finalize()' THEN
   IF (f-'source_md5') IS DISTINCT FROM (row_before-'source_md5') THEN RAISE EXCEPTION 'existing finalizer trigger drift'; END IF;
  ELSIF f IS DISTINCT FROM row_before THEN RAISE EXCEPTION 'existing trigger drift'; END IF;
 END LOOP;
 IF jsonb_array_length(actual->'triggers')<>jsonb_array_length(previous->'triggers')+1 THEN RAISE EXCEPTION 'unexpected trigger scope'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.payment_certificates'::regclass
  AND t.tgname='expense_direction_v2_guard' AND t.tgfoid='private.expense_payment_v2_guard()'::regprocedure
  AND NOT t.tgisinternal AND t.tgenabled='O' AND t.tgtype=31 AND t.tgnargs=0 AND t.tgqual IS NULL
  AND t.tgattr=''::int2vector AND t.tgconstraint=0 AND NOT t.tgdeferrable AND NOT t.tginitdeferred
  AND t.tgoldtable IS NULL AND t.tgnewtable IS NULL) THEN RAISE EXCEPTION 'new guard trigger mismatch'; END IF;
 FOR signature IN SELECT jsonb_array_elements_text(${newSignatures}::jsonb) LOOP
  SELECT value INTO f FROM jsonb_array_elements(actual->'functions') WHERE value->>'signature'=signature;
  expected_authenticated:=signature IN ('private.expense_payment_direction_capability(uuid)','public.expense_payment_direction_capability(uuid)');
  function_oid:=to_regprocedure(signature);
  expected_definer:=signature IN ('private.expense_payment_v2_guard()','private.expense_payment_direction_capability(uuid)');
  expected_volatility:=CASE WHEN signature='private.expense_payment_v2_guard()' THEN 'v'
   WHEN signature='private.expense_payment_v2_envelope(uuid,uuid,uuid,date,integer,numeric,jsonb)' THEN 'i' ELSE 's' END;
  IF f IS NULL OR f->>'owner'<>current_user OR f->'config' IS DISTINCT FROM jsonb_build_array('search_path=""')
   OR (f->>'definer')::boolean IS DISTINCT FROM expected_definer OR f->>'volatility' IS DISTINCT FROM expected_volatility
   OR f->>'parallel' IS DISTINCT FROM 'u' OR (f->>'strict')::boolean IS DISTINCT FROM false OR (f->>'leakproof')::boolean IS DISTINCT FROM false
   OR has_function_privilege('anon',function_oid,'EXECUTE')
   OR has_function_privilege('authenticated',function_oid,'EXECUTE') IS DISTINCT FROM expected_authenticated
   OR EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    WHERE p.oid=function_oid AND (a.privilege_type<>'EXECUTE' OR (a.grantee<>p.proowner AND
      (NOT expected_authenticated OR a.grantee<>(SELECT oid FROM pg_roles WHERE rolname='authenticated') OR a.is_grantable))))
   THEN RAISE EXCEPTION 'new function privilege/config mismatch'; END IF;
 END LOOP;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='private.expense_cost_direction_v2_enabled(uuid)'::regprocedure)<>md5('select false') THEN RAISE EXCEPTION 'direction gate must remain constant OFF'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each_text(${expectedSources}::jsonb) expected
  WHERE (SELECT value->>'source_md5' FROM jsonb_array_elements(actual->'functions') WHERE value->>'signature'=expected.key) IS DISTINCT FROM expected.value)
  THEN RAISE EXCEPTION 'deployed function source differs from reviewed candidate'; END IF;
 IF (SELECT business_hash FROM sko_expense_off_before) IS DISTINCT FROM (${businessHashSql}) THEN RAISE EXCEPTION 'business data changed'; END IF;
END $sko_postflight$;
COMMIT;`;
}
