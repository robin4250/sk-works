// Synthetic disposable database only. No production checkpoint or URL input.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';
import {captureCodeCheckpoint,buildCodeRestore,newFunctions} from './expense_direction_code_checkpoint.mjs';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();
const read=p=>fs.readFileSync(p,'utf8'),id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const candidate='docs/candidates/expense_payment_direction_v2_20261019.sql.review-only';
try{
 await setupExpenseCostFixture(db);
 for(const file of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])await db.exec(read('supabase/migrations/'+file));
 await db.exec(`insert into companies(id,tax_rate) values('${id(1)}',10);insert into company_members values('${id(1)}','${id(3)}','owner');insert into workers(id,company_id,name,user_id,partner_company_id) values('${id(2)}','${id(1)}','Synthetic','${id(3)}','${id(5)}');insert into partner_companies values('${id(5)}','${id(1)}','Synthetic');insert into private.expense_approval_settings(company_id,approver_ids,revision) values('${id(1)}',array['${id(3)}']::uuid[],1);set test.uid='${id(3)}';`);
 // A real v1 finalized document and existing consumption must survive code restoration.
 await db.exec(`insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen) values('${id(20)}','${id(1)}','${id(2)}','Synthetic','${id(3)}','2026-09-01','2026-09-01','Legacy',1000);select public.expense_confirm_review('${id(120)}','${id(20)}',1,'approve','subcontractor','${id(5)}','cash','');update public.payment_certificates set status='finalized' where period_start='2026-09-01';`);
 const before=await captureCodeCheckpoint(db);await db.exec(read(candidate));const after=await captureCodeCheckpoint(db),restore=buildCodeRestore(before,after);
 const business=async()=>(await db.query(`select jsonb_build_object('claims',(select jsonb_agg(to_jsonb(x) order by id) from private.expense_claims x),'payments',(select jsonb_agg(to_jsonb(x) order by id) from public.payment_certificates x),'ledger',(select jsonb_agg(to_jsonb(x) order by claim_id,purpose) from private.expense_amount_consumptions x)) value`)).rows[0].value;
 const originalData=await business();assert.equal(originalData.payments.length,1);assert.equal(originalData.payments[0].net_amount,1000);assert.equal(originalData.ledger.length,1);
 for(const mutation of [
  'grant execute on function public.expense_payment_direction_capability(uuid) to anon',
  'alter function private.read_expense_document(text,uuid) volatile',
  'alter table public.payment_certificates disable trigger expense_direction_v2_guard',
  `create or replace function private.expense_cost_direction_v2_enabled(cid uuid) returns boolean language sql stable security invoker set search_path='' as $$select true$$`,
 ]){
  await db.exec('begin');await db.exec(mutation);await assert.rejects(db.exec(restore),/deployed checkpoint differs/);await db.exec('rollback');assert.deepEqual(await captureCodeCheckpoint(db),after);assert.deepEqual(await business(),originalData);
 }
 // An unknown dependency must reject without CASCADE and roll back earlier replacements.
 await db.exec(`create view public.synthetic_direction_dependency as select public.expense_payment_direction_capability('${id(1)}') value`);
 await assert.rejects(db.exec(restore),/depend/);assert.deepEqual(await captureCodeCheckpoint(db),after);assert.deepEqual(await business(),originalData);
 await db.exec('drop view public.synthetic_direction_dependency');
 for(const finalized of [false,true]){
  await db.exec('begin');
  await db.exec(`create or replace function private.expense_cost_direction_v2_enabled(cid uuid) returns boolean language sql stable security invoker set search_path='' as $$select true$$;insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen) values('${id(10)}','${id(1)}','${id(2)}','Synthetic','${id(3)}','2026-10-01','2026-10-01','Synthetic',1000);select public.expense_confirm_review('${id(110)}','${id(10)}',1,'approve','subcontractor','${id(5)}','cash','');`);
  const gate=after.functions.find(f=>f.signature===newFunctions[0]);await db.exec(gate.definition);
  if(finalized)await db.exec("update public.payment_certificates set status='finalized' where period_start='2026-10-01'");
  assert.deepEqual(await captureCodeCheckpoint(db),after);
  await assert.rejects(db.exec(restore),/v2 documents require v2 code/);await db.exec('rollback');assert.deepEqual(await business(),originalData);
 }
 await db.exec('begin;create table private.expense_payment_direction_conversions(id integer)');await assert.rejects(db.exec(restore),/separate recovery review/);await db.exec('rollback');
 await db.exec(restore);assert.deepEqual(await captureCodeCheckpoint(db),before);assert.deepEqual(await business(),originalData);
 console.log('PASS exact code restore with OID/ACL/owner/settings/trigger preservation; unknown grant/function/trigger/gate/dependency and v2 draft/final/conversion refusal; atomic rollback and no business data changes');
}finally{await db.close();}
