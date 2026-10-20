// Disposable synthetic catalog test; no Supabase, credentials or production rows.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const query=fs.readFileSync('docs/candidates/expense_payment_readonly_readiness_20261021.sql','utf8');
const inventory=async()=> (await db.query(query)).rows[0].inventory;
try {
 await setupExpenseCostFixture(db);
 for(const file of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])
  await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 const before=await inventory();
 assert.equal(before.inventory_only,true);
 assert.equal(before.functions.length,12);
 const named=(data,signature)=>data.functions.find(f=>f.signature===signature);
 const gate='private.expense_cost_direction_v2_enabled(uuid)';
 assert.equal(named(before,gate).present,false);
 await db.exec(fs.readFileSync('docs/candidates/expense_payment_direction_v2_20261019.sql.review-only','utf8'));
 const off=await inventory();
 assert.equal(off.functions.filter(f=>f.stage==='direction_backend'&&f.present).length,8);
 assert.equal(named(off,gate).constant_off_source,true);
 assert.equal(off.v2_guard_trigger.function_matches,true);
 assert.equal(off.v2_guard_trigger.enabled,'O');
 assert.equal(off.conversion_receipt_table_present,false);
 await db.exec(fs.readFileSync('docs/candidates/expense_payment_v1_draft_conversion_20261019.sql.review-only','utf8'));
 const conversion=await inventory();
 assert.equal(conversion.conversion_receipt_table_present,true);
 const rollout='private.expense_direction_v2_client_rollout_verified(uuid)';
 assert.equal(named(conversion,rollout).constant_off_source,true);
 assert.equal(named(conversion,rollout).authenticated_execute,false);
 assert.equal(named(conversion,'private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)').anon_execute,false);
 const source='private.payment_expense_v2_requested()';
 assert.equal(named(conversion,source).present,false,'conversion alone is not source negotiation');
 const codeBefore=(await db.query('select oid,md5(prosrc) hash from pg_proc order by oid')).rows;
 const rowsBefore=(await db.query('select count(*)::int n from payment_certificates')).rows;
 await inventory();
 assert.deepEqual((await db.query('select oid,md5(prosrc) hash from pg_proc order by oid')).rows,codeBefore);
 assert.deepEqual((await db.query('select count(*)::int n from payment_certificates')).rows,rowsBefore);
 console.log('PASS readonly expense inventory: missing/OFF/conversion stages, no false rollout, catalog and business unchanged');
} finally {await db.close();}
