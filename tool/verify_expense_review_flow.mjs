import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
try {
 await setupExpenseCostFixture(db);
 for(const file of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])
  await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 const company=id(1),worker=id(2),actor=id(3),customer=id(4);
 await db.exec(`insert into companies(id,tax_rate) values('${company}',10);
  insert into company_members values('${company}','${actor}','owner');
  insert into workers(id,company_id,name,user_id) values('${worker}','${company}','本人','${actor}');
  insert into customers values('${customer}','${company}','取引先','');
  insert into private.expense_approval_settings(company_id,approver_ids,revision) values('${company}',array['${actor}']::uuid[],1);
  set test.uid='${actor}';`);
 async function claim(n){await db.exec(`insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen)
  values('${id(n)}','${company}','${worker}','本人','${actor}','2026-09-30','2026-09-30T15:00:00Z','原子確定検証',1234)`);}
 const confirm=async(cmd,c,action='approve',category='ownCompany',method='cash',party=null,memo='',revision=1)=>(await db.query(
  `select public.expense_confirm_review('${id(cmd)}','${id(c)}',${revision},'${action}',${category===null?'null':"'"+category+"'"},${party===null?'null':"'"+party+"'"},${method===null?'null':"'"+method+"'"},'${memo}') value`)).rows[0].value;
 for(const [index,method] of ['cash','payroll','paid','advance'].entries()) {
  await claim(10+index);
  const result=await confirm(20+index,10+index,'approve','other',method,null,'メモ');
  assert.equal(result.allocation,'other');assert.equal(result.settlement_method,method);
  assert.equal(result.settlement_month,'2026-10-01');assert.equal(result.revision,2);
  assert.equal(result.cost_allocation_current,false);
  assert.deepEqual(await confirm(20+index,10+index,'approve','other',method,null,'メモ'),result);
  await assert.rejects(confirm(20+index,10+index,'approve','other',method,null,'別メモ'),/fixed expense confirmation differs/);
 }
 assert.equal((await db.query('select count(*)::int n from payroll_statements')).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from invoices')).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from private.expense_claim_events')).rows[0].n,0,'no preliminary approval events');
 await claim(30);
 await assert.rejects(confirm(31,30,'approve','customer','cash',id(999)),/company customer required/);
 assert.equal((await db.query(`select approval,revision from private.expense_claims where id='${id(30)}'`)).rows[0].approval,'pending');
 const rejected=await confirm(31,30,'reject',null,null,null,'用途を確認してください');
 assert.equal(rejected.approval,'rejected');assert.equal(rejected.settlement_method,null);
 assert.equal((await db.query(`select count(*)::int n from private.expense_settlement_choices where claim_id='${id(30)}'`)).rows[0].n,0);
 await claim(40);
 const billed=await confirm(41,40,'approve','customer','paid',customer,'立替済み');
 assert.equal(billed.settlement_method,'paid');assert.equal(billed.cost_allocation_current,true);
 const invoice=(await db.query(`select * from invoices where customer_id='${customer}'`)).rows[0];
 assert.equal(invoice.grand_total,1234);assert.equal(invoice.tax,0);assert.equal(invoice.welfare_amount,0);
 assert.equal(new Date(invoice.billing_period_start).toISOString().slice(0,10),'2026-09-01','cost recovery still uses incurred month');
 await db.exec(`update invoices set status='finalized' where id='${invoice.id}'`);
 await assert.rejects(confirm(42,40,'reject',null,null,null,'変更',2),/帳票確定済み/);
 assert.deepEqual(await confirm(41,40,'approve','customer','paid',customer,'立替済み'),billed,'frozen original receipt replays unchanged');
 assert.equal((await db.query(`select count(*)::int n from private.expense_review_confirmations where command_id='${id(42)}'`)).rows[0].n,0);
 const workspace=(await db.query(`select public.expense_review_flow_workspace('${company}','2026-09-01') value`)).rows[0].value;
 assert.equal(workspace.review_flow_enabled,true);
 assert.equal(workspace.claims.find(x=>x.id===id(40)).review_memo,'立替済み');
 const history=(await db.query(`select public.expense_review_flow_history('${id(40)}') value`)).rows[0].value;
 assert.equal(history.events.length,1);assert.equal(history.events[0].result.review_action,'approve');
 await db.exec(`set role authenticated;`);
 await assert.rejects(db.query('select * from private.expense_review_confirmations'),/permission denied/);
 await db.exec('reset role');
 const beforeEdit=(await db.query(`select submitted_at from private.expense_claims where id='${id(10)}'`)).rows[0].submitted_at;
 const edit=async()=>(await db.query(`select public.expense_review_edit('${id(50)}','${id(10)}',2,'2026-08-01','内容修正',1500) value`)).rows[0].value;
 const changed=await edit();assert.equal(changed.approval,'pending');assert.equal(changed.allocation,'unallocated');
 assert.equal(changed.amount_yen,1500);assert.deepEqual(await edit(),changed);
 assert.deepEqual((await db.query(`select submitted_at from private.expense_claims where id='${id(10)}'`)).rows[0].submitted_at,beforeEdit);
 await assert.rejects(db.exec(`select public.expense_review_edit('${id(51)}','${id(40)}',2,'2026-09-30','確定後変更',999)`),/帳票確定済み/);
 console.log('PASS atomic final confirmation, four distinct methods, other category, Japan application month, rollback/no partial approval, immutable receipt, cost month and frozen consumption protection');
}finally{await db.close();}
