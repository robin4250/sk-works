import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const company=id(1),worker=id(2),actor=id(3),customer=id(4),partner=id(5);
const candidate='docs/candidates/expense_payment_direction_v2_20261019.sql.review-only';
try {
 await setupExpenseCostFixture(db);
 for(const file of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])
  await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 await db.exec(`insert into companies(id,tax_rate) values('${company}',10);
 insert into company_members values('${company}','${actor}','owner');
 insert into workers(id,company_id,name,user_id,partner_company_id) values('${worker}','${company}','検証社員','${actor}','${partner}');
 insert into customers values('${customer}','${company}','検証取引先','');
 insert into partner_companies values('${partner}','${company}','検証下請け');
 insert into private.expense_approval_settings(company_id,approver_ids,revision) values('${company}',array['${actor}']::uuid[],1);
 set test.uid='${actor}';`);
 const row=async(month)=>(await db.query(`select * from payment_certificates where company_id='${company}' and partner_company_id='${partner}' and period_start='2026-${month}-01'`)).rows[0];
 async function approve(n,month,method='cash',category='subcontractor',party=partner){
 await db.exec(`insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen)
 values('${id(n)}','${company}','${worker}','検証社員','${actor}','2026-${month}-01','2026-${month}-01T01:00:00Z','検証経費',1000)`);
 return (await db.query(`select public.expense_confirm_review('${id(n+100)}','${id(n)}',1,'approve','${category}','${party}','${method}','') value`)).rows[0].value;
 }
 await approve(10,'07');const legacy=await row('07');
 assert.equal(legacy.gross_amount,1000);assert.equal(legacy.net_amount,1000);
 await db.exec(`update payment_certificates set status='finalized' where id='${legacy.id}'`);
 const frozenLegacy=await row('07');
 const legacyLedger=(await db.query(`select * from private.expense_amount_consumptions where claim_id='${id(10)}'`)).rows;
 const invoiceSource=(await db.query("select md5(prosrc) hash from pg_proc where oid='private.refresh_automatic_invoice(uuid,uuid,date)'::regprocedure")).rows[0].hash;
 await db.exec(fs.readFileSync(candidate,'utf8'));
 assert.equal((await db.query("select private.expense_cost_direction_v2_enabled('"+company+"') value")).rows[0].value,false);
 const capOff=(await db.query(`select public.expense_payment_direction_capability('${company}') value`)).rows[0].value;assert.equal(capOff.read_enabled,false);assert.equal(capOff.actor_id,actor);
 await approve(11,'08');assert.equal((await row('08')).net_amount,1000,'OFF retains v1');
 await db.exec(`create or replace function private.expense_cost_direction_v2_enabled(cid uuid) returns boolean language sql stable security invoker set search_path='' as $$select cid='${company}'::uuid$$`);
 const draftsBefore=(await db.query('select count(*)::int n from payment_certificates')).rows[0].n;
 await db.exec(`select private.refresh_automatic_payment_certificate('${company}','${id(999)}','2026-10-01')`);
 assert.equal((await db.query('select count(*)::int n from payment_certificates')).rows[0].n,draftsBefore,'no empty unrelated document');
 const capOn=(await db.query(`select public.expense_payment_direction_capability('${company}') value`)).rows[0].value;assert.equal(capOn.read_enabled,true);assert.equal(capOn.company_id,company);
 const payrollReceipt=await approve(12,'10','payroll');let value=await row('10');
 assert.equal(value.gross_amount,0);assert.equal(value.deductions,1000);assert.equal(value.net_amount,-1000);
 assert.equal(value.snapshot.expense_extra_source_version,undefined);
 assert.equal(value.snapshot.expense_cost_direction_v2.direction,'deduction');
 assert.equal(value.snapshot.expense_cost_direction_v2.document_id,value.id);
 assert.equal(value.snapshot.expense_cost_direction_v2.document_revision,value.revision);
 assert.deepEqual(value.snapshot.expense_cost_direction_v2.claims,[{id:id(12),revision:2,amount_yen:1000}]);
 const beforeRefresh=structuredClone(value);
 await db.exec(`select private.refresh_automatic_payment_certificate('${company}','${partner}','2026-10-01')`);
 assert.deepEqual(await row('10'),beforeRefresh,'same snapshot keeps revision and totals');
 const details=async()=> (await db.query(`select public.read_expense_document('paymentCertificate','${value.id}') value`)).rows[0].value;
 const live=await details();assert.equal(live.frozen,false);assert.equal(live.claims.length,1);
 assert.deepEqual(live.expense_cost_direction_v2,value.snapshot.expense_cost_direction_v2);
 assert.deepEqual(live.expense_cost_basis,value.snapshot.expense_cost_basis);
 await db.exec(`update payment_certificates set status='finalized' where id='${value.id}'`);
 value=await row('10');const frozen=await details();assert.equal(frozen.frozen,true);
 assert.deepEqual(frozen.expense_cost_direction_v2,value.snapshot.expense_cost_direction_v2);
 const ledger=(await db.query(`select * from private.expense_amount_consumptions where claim_id='${id(12)}'`)).rows;
 assert.equal(ledger.length,1);assert.equal(ledger[0].purpose,'cost_recovery');assert.equal(ledger[0].amount_yen,1000);
 await db.exec(`select private.refresh_automatic_payment_certificate('${company}','${partner}','2026-10-01')`);
 assert.deepEqual(await row('10'),value,'finalized v2 is not regenerated');
 assert.deepEqual((await db.query(`select * from private.expense_amount_consumptions where claim_id='${id(12)}'`)).rows,ledger);
 await assert.rejects(db.exec(`update private.expense_claims set amount_yen=2000 where id='${id(12)}'`),/確定済み/);
 await assert.rejects(db.exec(`update private.expense_settlement_choices set method='cash' where claim_id='${id(12)}'`),/確定済み/);
 assert.deepEqual((await db.query(`select public.expense_confirm_review('${id(112)}','${id(12)}',1,'approve','subcontractor','${partner}','payroll','') value`)).rows[0].value,payrollReceipt,'fixed confirmation retry returns one original receipt');
 await assert.rejects(db.exec(`delete from payment_certificates where id='${value.id}'`),/immutable/);
 await assert.rejects(db.exec(`update payment_certificates set net_amount=1000 where id='${value.id}'`),/immutable/);
 await assert.rejects(db.exec(`update payment_certificates set snapshot=snapshot-'expense_cost_direction_v2' where id='${value.id}'`),/downgrade/);
 await db.exec(`select private.refresh_automatic_payment_certificate('${company}','${partner}','2026-07-01')`);
 assert.deepEqual(await row('07'),frozenLegacy,'existing finalized v1 exact row preserved');
 assert.deepEqual((await db.query(`select * from private.expense_amount_consumptions where claim_id='${id(10)}'`)).rows,legacyLedger,'old consumption byte values preserved');
 await db.exec(`select private.refresh_automatic_payment_certificate('${company}','${partner}','2026-08-01')`);
 assert.equal((await row('08')).snapshot.expense_extra_source_version,1,'old draft is not silently upgraded');
 for(const [n,month,method] of [[13,'09','paid'],[14,'11','cash']]){
 const receipt=await approve(n,month,method);assert.equal(receipt.settlement_method,method);
 assert.equal((await row(month)).net_amount,-1000,`${method} does not change burden direction`);
 }
 await approve(15,'12','paid','customer',customer);
 assert.equal((await db.query(`select grand_total from invoices where customer_id='${customer}' and billing_period_start='2026-12-01'`)).rows[0].grand_total,1000,'invoice addition unchanged');
 assert.equal((await db.query("select md5(prosrc) hash from pg_proc where oid='private.refresh_automatic_invoice(uuid,uuid,date)'::regprocedure")).rows[0].hash,invoiceSource);
 const clearedBefore=await row('11');
 await db.exec(`update private.expense_settlement_choices set cost_allocation_current=false where claim_id='${id(14)}'`);
 const cleared=await row('11');assert.equal(cleared.id,clearedBefore.id);assert.equal(cleared.net_amount,0);assert.equal(cleared.revision,clearedBefore.revision+1);
 assert.deepEqual(cleared.snapshot.expense_cost_direction_v2.claims,[]);
 assert.equal(cleared.snapshot.expense_cost_direction_v2.document_revision,cleared.revision);
 assert.equal(cleared.snapshot.expense_cost_basis.document_revision,cleared.revision);
 await db.exec(`select private.refresh_automatic_payment_certificate('${company}','${partner}','2026-11-01')`);assert.deepEqual(await row('11'),cleared);
 const draft=await row('09');
 await assert.rejects(db.exec(`update payment_certificates set net_amount=0 where id='${draft.id}'`),/amount/);
 await assert.rejects(db.exec(`update payment_certificates set snapshot=jsonb_set(snapshot,'{expense_cost_direction_v2,subject_id}','"${customer}"') where id='${draft.id}'`),/scope/);
 await assert.rejects(db.exec(`update payment_certificates set revision=revision+1 where id='${draft.id}'`),/scope/);
 await db.exec(`begin;update payment_certificates set snapshot=jsonb_set(snapshot,'{expense_cost_direction_v2,claims,0,id}','\"${id(777)}\"') where id='${draft.id}'`);
 try {await assert.rejects(db.exec(`update payment_certificates set status='finalized' where id='${draft.id}'`),/allocated expenses changed/);} finally {await db.exec('rollback');}
 assert.deepEqual(await row('09'),draft,'failed finalization cannot persist an unknown claim');
 await db.exec(`begin;insert into private.expense_amount_consumptions(claim_id,purpose,company_id,document_kind,document_id,document_revision,claim_revision,amount_yen,snapshot)
 values('${id(13)}','cost_recovery','${company}','paymentCertificate','${draft.id}',999,2,1000,'{}')`);
 try {await assert.rejects(db.exec(`update payment_certificates set status='finalized' where id='${draft.id}'`),/別の帳票/);} finally {await db.exec('rollback');}
 assert.equal((await db.query(`select count(*)::int n from private.expense_amount_consumptions where claim_id='${id(13)}'`)).rows[0].n,0);
 await db.exec(`set test.uid='${id(99)}'`);
 await assert.rejects(details(),/access denied/);
 await assert.rejects(db.exec(`select public.expense_payment_direction_capability('${company}')`),/access denied/);
 console.log('PASS v2 real generator expense-only -1000, OFF/v1 immutable, idempotent revision, scoped live/frozen read, one consumption/freeze, cash/payroll/paid independence, unchanged invoice addition and rejected amount/scope/revision/unauthorized read');
} finally {await db.close();}
