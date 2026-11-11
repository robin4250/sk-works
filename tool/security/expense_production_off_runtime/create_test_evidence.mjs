// Isolated fixture only; output contains generated synthetic records, never production input.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {setupExpenseCostFixture} from '../../fixtures/expense_cost_fixture.mjs';
import {buildExpensePlan,prepareUnusedUndo} from './expense_default_off_plan.mjs';
import {captureCodeCheckpoint} from './source/expense_direction_code_checkpoint.mjs';
import {defaultOffBusinessHashSql} from './source/expense_direction_default_off_preparation.mjs';
const runtime=process.argv[2],output=process.argv[3];
// The unchanged existing native adapter expects argv[3] to contain the pinned pg driver.
if(process.argv[4])process.argv[3]=process.argv[4];
const {PGlite}=await import(runtime);const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const sha=b=>createHash('sha256').update(b).digest('hex');
const write=(name,value)=>fs.writeFileSync(path.join(output,name),typeof value==='string'?value:JSON.stringify(value),{mode:0o600,flag:'wx'});
try{
 await setupExpenseCostFixture(db);
 for(const name of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])
  await db.exec(fs.readFileSync('supabase/migrations/'+name,'utf8'));
 await db.exec(`insert into companies(id,tax_rate) values('${id(1)}',10);
 insert into company_members values('${id(1)}','${id(3)}','owner');
 insert into workers(id,company_id,name,user_id,partner_company_id) values('${id(2)}','${id(1)}','Synthetic','${id(3)}','${id(5)}');
 insert into partner_companies values('${id(5)}','${id(1)}','Synthetic');
 insert into private.expense_approval_settings(company_id,approver_ids,revision) values('${id(1)}',array['${id(3)}']::uuid[],1);
 set test.uid='${id(3)}';
 insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen)
 values('${id(10)}','${id(1)}','${id(2)}','Synthetic','${id(3)}','2026-07-01','2026-07-01','Synthetic',1000);
 select public.expense_confirm_review('${id(110)}','${id(10)}',1,'approve','subcontractor','${id(5)}','cash','');`);
 const before={schema:1,read_only:'on',exact_target_count:1,global_v2_or_basis_count:0,
  converter_installed:false,conversion_audit_installed:false,rollout_installed:false,
  before:await captureCodeCheckpoint(db),business:(await db.query(defaultOffBusinessHashSql)).rows[0].value};
 const originalRows=(await db.query('select * from payment_certificates order by id')).rows;
 const candidate=fs.readFileSync(new URL('./source/expense_payment_direction_v2_20261019.sql.review-only',import.meta.url),'utf8');
 const plan=buildExpensePlan(before,candidate);
 write('private-fresh-before.json',before);
 write('private-prepared-install.sql.review-only',plan.install);
 write('private-read-actual-after.sql.read-only',plan.readActualAfter);
 const artifacts={};
 for(const name of ['private-prepared-install.sql.review-only','private-read-actual-after.sql.read-only']){
  const raw=fs.readFileSync(path.join(output,name));artifacts[name]={sha256:sha(raw),bytes:raw.length};
 }
 write('prepare-status.json',{verified:true,prepare_only:true,production_connected:false,
  source_checkpoint_sha256:sha(fs.readFileSync(path.join(output,'private-fresh-before.json'))),artifacts});
 write('synthetic-before-observation.json',{read_only:'on',after:before.before,business:before.business,
  v2_or_basis_count:0,converter_installed:false,audit_installed:false,rollout_installed:false});
 await db.exec(plan.install);
 const results=await db.exec(plan.readActualAfter);
 const actual=results.flatMap(r=>r.rows??[]).find(r=>r.jsonb_build_object)?.jsonb_build_object;
 assert(actual);assert.equal(actual.read_only,'on');
 write('synthetic-after-observation.json',actual);
 assert.deepEqual((await db.query('select * from payment_certificates order by id')).rows,originalRows);
 const undo=prepareUnusedUndo(before,actual);await db.exec(undo);
 assert.deepEqual(await captureCodeCheckpoint(db),before.before);
 assert.deepEqual((await db.query('select * from payment_certificates order by id')).rows,originalRows);
 console.log('PASS PGlite original plan install/read-only actual/actual-OID undo; financial rows unchanged');
}finally{await db.close();}
