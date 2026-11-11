// Expense-only preparation. Never connects to or executes SQL on a database.
import assert from 'node:assert/strict';
import{buildDefaultOffDeployment,defaultOffBusinessHashSql}from'./source/expense_direction_default_off_preparation.mjs';
import{catalogSql,buildCodeRestore,oldFunctions,newFunctions}from'./source/expense_direction_code_checkpoint.mjs';
function quote(value){const tag='expense_specific_fresh';assert(!value.includes('$'+tag+'$'));return '$'+tag+'$'+value+'$'+tag+'$';}
export function buildExpensePlan(input,candidate){
 assert.equal(input.schema,1);assert.equal(input.read_only,'on');assert.equal(input.exact_target_count,1);assert.equal(input.global_v2_or_basis_count,0);
 for(const key of ['converter_installed','conversion_audit_installed','rollout_installed'])assert.equal(input[key],false);
 assert.deepEqual(input.before.functions.map(f=>f.signature).sort(),[...oldFunctions].sort());
 assert(input.before.functions.every(f=>f.owner==='postgres'),'expense owner differs from reviewed execution role');
 const original=buildDefaultOffDeployment(input.before,candidate,input.business);
 const marker="SET LOCAL statement_timeout='30s';";assert.equal(original.split(marker).length,2);
 const expected=quote(JSON.stringify(input.before));
 const guard=`\nSET LOCAL ROLE postgres;\nDO $expense_operator_preflight$ BEGIN
 IF current_user<>'postgres' OR NOT pg_has_role(session_user,'postgres','SET')
 THEN RAISE EXCEPTION 'expense execution role differs'; END IF;
 IF (SELECT value FROM (${catalogSql}) expense_current) IS DISTINCT FROM ${expected}::jsonb
 THEN RAISE EXCEPTION 'expense fresh code/owner/ACL/OID differs'; END IF;
END $expense_operator_preflight$;`;
 return {install:original.replace(marker,marker+guard),readActualAfter:`BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;SET LOCAL statement_timeout='30s';SET LOCAL ROLE postgres;
SELECT jsonb_build_object('read_only',current_setting('transaction_read_only'),'after',(${catalogSql}),'business',(${defaultOffBusinessHashSql}),'v2_or_basis_count',(SELECT count(*) FROM public.payment_certificates WHERE snapshot?'expense_cost_direction_v2' OR snapshot?'expense_cost_basis'),'converter_installed',to_regprocedure('private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)') IS NOT NULL,'audit_installed',to_regclass('private.expense_payment_direction_conversions') IS NOT NULL,'rollout_installed',to_regprocedure('private.expense_direction_v2_client_rollout_verified(uuid)') IS NOT NULL);COMMIT;`};
}
const reviewedAfterSources={
 'private.expense_cost_direction_v2_enabled(uuid)':'9f038cd8f856dc2fad5b866160f26637',
 'private.expense_cost_finalize()':'22ff4377666ec56ccc4b261cf380e9c0',
 'private.expense_payment_direction_capability(uuid)':'72c86b51bc0c6ae5c283e9868834fb54',
 'private.expense_payment_v2_envelope(uuid,uuid,uuid,date,integer,numeric,jsonb)':'52dcf11a021a6584621527aeacbf6e37',
 'private.expense_payment_v2_guard()':'4d08bd0b372a3048b9eb52dd99a3c321',
 'private.read_expense_document(text,uuid)':'85a16c6a5181c4f4ee85316f69a288cb',
 'private.refresh_automatic_payment_certificate(uuid,uuid,date)':'5828ec68ad83ace5f0c0fc8f21851cf8',
 'public.expense_payment_direction_capability(uuid)':'23d08c31cf55263869f09be3967f42a7',
};
export function prepareUnusedUndo(beforeRecord,actual){
 assert.equal(actual.read_only,'on');assert.equal(actual.business,beforeRecord.business);
 assert.equal(actual.v2_or_basis_count,0);
 for(const key of ['converter_installed','audit_installed','rollout_installed'])assert.equal(actual[key],false);
 assert.deepEqual(Object.fromEntries(actual.after.functions.map(f=>[f.signature,f.source_md5])),reviewedAfterSources,'actual after source differs from reviewed installation');
 for(const signature of newFunctions){
  const f=actual.after.functions.find(f=>f.signature===signature);
  const authenticated=signature.includes('expense_payment_direction_capability');
  assert.equal(f.owner,'postgres');assert.deepEqual(f.config,['search_path=""']);
  assert.equal(f.definer,['private.expense_payment_v2_guard()','private.expense_payment_direction_capability(uuid)'].includes(signature));
  assert.equal(f.volatility,signature==='private.expense_payment_v2_guard()'?'v':signature.includes('expense_payment_v2_envelope')?'i':'s');
  assert.equal(f.parallel,'u');assert.equal(f.strict,false);assert.equal(f.leakproof,false);
  assert.deepEqual([...f.acl].sort(),['postgres=X/postgres',...(authenticated?['authenticated=X/postgres']:[])].sort());
 }
 const restore=buildCodeRestore(beforeRecord.before,actual.after);
 return `BEGIN;SET LOCAL statement_timeout='30s';SET LOCAL lock_timeout='3s';SET LOCAL ROLE postgres;
 DO $expense_unused_scope$ BEGIN
 IF to_regprocedure('private.expense_direction_v2_client_rollout_verified(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'rollout installation requires separate recovery review';END IF;
 END $expense_unused_scope$;
 ${restore}
 COMMIT;`;

}
