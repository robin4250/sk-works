import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';
const {PGlite} = await import(process.argv[2]);
const db = new PGlite();
try {
  await setupExpenseCostFixture(db);
  // This synthetic fixture originally exposes only invoice management.
  // Enable its existing read feature for detail/amount consistency checks.
  await db.exec(`create or replace function private.has_company_feature(p_company uuid,p_feature text)
    returns boolean language sql as $$select p_feature in ('can_manage_invoices','can_view_invoices')
    and exists(select 1 from public.company_members m where m.company_id=p_company
      and m.user_id=auth.uid() and m.role in ('owner','admin'))$$`);
  // The extension is staged separately from the deployed metadata contract.
  await db.exec(fs.readFileSync('supabase/tests/expense_settlement_choice_cost_extension.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/tests/expense_cost_amounts.sql', 'utf8'));
  const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
  const [company, worker, actor, customer, partner, site, claim] = [1,2,3,4,5,6,7].map(id);
  await db.exec(`insert into companies(id,tax_rate) values('${company}',10);
    insert into company_members values('${company}','${actor}','owner');
    insert into workers(id,company_id,name,user_id,partner_company_id) values('${worker}','${company}','本人','${actor}','${partner}');
    insert into customers values('${customer}','${company}','取引会社','');
    insert into partner_companies values('${partner}','${company}','下請け会社');
    insert into sites(id,company_id,customer_id,name) values('${site}','${company}','${customer}','登録現場');
    insert into site_financial_settings(company_id,site_id,billing_unit_price_yen,welfare_rate) values('${company}','${site}',20000,8);
    insert into partner_payment_settings(company_id,partner_company_id,daily_rate_yen,welfare_rate,tax_rate) values('${company}','${partner}',20000,8,10);
    insert into attendance_entries(company_id,worker_id,site_id,work_date,base_man_days) values('${company}','${worker}','${site}','2026-09-30',1);
    set test.uid='${actor}';
    insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,description,amount_yen,approval,allocation,counterparty_id,revision)
      values('${claim}','${company}','${worker}','本人','${actor}','2026-09-30','別途交通費',1234,'approved','customer','${customer}',2);
    insert into private.expense_settlement_choices(claim_id,company_id,method,settlement_month,revision,chosen_by,approval_current,cost_allocation_current)
      values('${claim}','${company}','cash','2026-10-01',2,'${actor}',true,true);`);
  const invoice = () => db.query(`select * from invoices where customer_id='${customer}'`);
  const first = (await invoice()).rows[0];
  assert.equal(first.subtotal,21600); assert.equal(first.welfare_amount,1600);
  assert.equal(first.tax,2160); assert.equal(first.grand_total,24994);
  assert.equal(first.snapshot.expense_extra_amount_yen,1234);
  assert.equal(first.snapshot.expense_extra_claims.length,1);
  await db.exec(`select private.refresh_automatic_invoice('${company}','${customer}','2026-09-30')`);
  assert.deepEqual((await invoice()).rows[0].snapshot,first.snapshot,'refresh never adds the expense twice');
  await db.exec(`insert into private.expense_approval_settings(company_id,approver_ids,revision) values('${company}',array['${actor}']::uuid[],1)`);
  const allocationCommand=id(30);
  const allocate=`select public.expense_allocate_with_cost('${allocationCommand}','${claim}',2,'subcontractor','${partner}') as result`;
  const receipt=(await db.query(allocate)).rows[0].result;
  assert.equal(receipt.cost_allocation_current,true);
  assert.deepEqual((await db.query(allocate)).rows[0].result,receipt,'fixed allocation command returns exact receipt');
  assert.equal((await invoice()).rows[0].grand_total,23760);
  const certificate = (await db.query(`select * from payment_certificates where partner_company_id='${partner}'`)).rows[0];
  assert.equal(certificate.gross_amount,24994); assert.equal(certificate.net_amount,24994);
  assert.equal(certificate.snapshot.expense_extra_amount_yen,1234);
  assert.equal(certificate.snapshot.calculation_rows.find(r=>r.work_content==='福利厚生費').amount_yen,1600);
  assert.equal(certificate.snapshot.calculation_rows.find(r=>r.work_content==='消費税').amount_yen,2160);
  await db.exec(`update payment_certificates set status='finalized' where id='${certificate.id}'`);
  const frozenDetail=(await db.query(`select public.read_expense_document('paymentCertificate','${certificate.id}') as value`)).rows[0].value;
  assert.deepEqual(frozenDetail.claims.map(row=>row.id),[claim],'finalized payment details retain the charged claim');
  assert.equal(frozenDetail.claims.reduce((sum,row)=>sum+row.amount_yen,0),1234);
  assert.equal((await db.query('select count(*)::int n from private.expense_amount_consumptions')).rows[0].n,1);
  await assert.rejects(db.exec(`update private.expense_claims set amount_yen=2234,revision=4 where id='${claim}'`),/確定済み/);
  await assert.rejects(db.exec(`update private.expense_claims set allocation='customer',counterparty_id='${customer}',revision=4 where id='${claim}'`),/確定済み/);
  await assert.rejects(db.exec(`update private.expense_settlement_choices set method='payroll' where claim_id='${claim}'`),/確定済み/);
  assert.equal((await db.query(`select amount_yen from private.expense_claims where id='${claim}'`)).rows[0].amount_yen,1234);
  const legacyCustomer=id(24),legacyClaim=id(27);
  await db.exec(`insert into customers values('${legacyCustomer}','${company}','旧振り分け','');
    insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,description,amount_yen,approval,allocation,counterparty_id,revision)
      values('${legacyClaim}','${company}','${worker}','本人','${actor}','2026-10-01','以前の経費',999,'approved','customer','${legacyCustomer}',2);
    insert into private.expense_settlement_choices(claim_id,company_id,method,settlement_month,revision,chosen_by)
      values('${legacyClaim}','${company}','cash','2026-10-01',2,'${actor}');`);
  assert.equal((await db.query(`select count(*)::int n from invoices where customer_id='${legacyCustomer}'`)).rows[0].n,0,'legacy method choices never backfill financial documents');
  await assert.rejects(db.exec(`select public.expense_allocate_with_cost('${id(31)}','${legacyClaim}',2,'customer','${legacyCustomer}')`),/精算方法/);
  await db.exec(`select public.expense_approve_with_settlement('${id(32)}','${legacyClaim}',2,'cash','2026-10-01')`);
  assert.equal((await db.query(`select count(*)::int n from invoices where customer_id='${legacyCustomer}'`)).rows[0].n,0,'saving a method alone does not authorize recovery');
  await db.exec(`select public.expense_allocate_with_cost('${id(33)}','${legacyClaim}',2,'customer','${legacyCustomer}')`);
  const opted=(await db.query(`select * from invoices where customer_id='${legacyCustomer}'`)).rows[0];
  assert.equal(opted.grand_total,999);
  const unselectedClaim=id(44);
  await db.exec(`insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,description,amount_yen,approval,allocation,counterparty_id,revision)
    values('${unselectedClaim}','${company}','${worker}','本人','${actor}','2026-10-01','未選択の過去経費',688,'approved','customer','${legacyCustomer}',2);
    insert into private.expense_settlement_choices(claim_id,company_id,method,settlement_month,revision,chosen_by)
      values('${unselectedClaim}','${company}','cash','2026-10-01',2,'${actor}');`);
  const detail=(await db.query(`select public.read_expense_document('invoice','${opted.id}') as value`)).rows[0].value;
  assert.deepEqual(detail.claims.map(row=>row.id),[legacyClaim],'detail lists only the expense actually charged');
  assert.equal(detail.claims.reduce((sum,row)=>sum+row.amount_yen,0),999,'detail total equals the extra amount');
  await db.exec(`select private.expense_review_command('${id(34)}','${legacyClaim}',3,'allocate','ownCompany',null)`);
  assert.equal((await db.query(`select grand_total from invoices where id='${opted.id}'`)).rows[0].grand_total,0);
  assert.equal((await db.query(`select cost_allocation_current from private.expense_settlement_choices where claim_id='${legacyClaim}'`)).rows[0].cost_allocation_current,false);
  const emptyCustomer=id(14), emptyClaim=id(17);
  await db.exec(`insert into customers values('${emptyCustomer}','${company}','経費のみ','');
    insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,description,amount_yen,approval,allocation,counterparty_id,revision)
      values('${emptyClaim}','${company}','${worker}','本人','${actor}','2026-10-01','経費のみ',777,'approved','customer','${emptyCustomer}',2);
    insert into private.expense_settlement_choices(claim_id,company_id,method,settlement_month,revision,chosen_by,approval_current,cost_allocation_current)
      values('${emptyClaim}','${company}','cash','2026-10-01',2,'${actor}',true,true);`);
  const expenseOnly=(await db.query(`select * from invoices where customer_id='${emptyCustomer}'`)).rows[0];
  assert.equal(expenseOnly.grand_total,777); assert.equal(expenseOnly.tax,0); assert.equal(expenseOnly.welfare_amount,0);
  assert.deepEqual(expenseOnly.snapshot.sites,[]);
  await db.exec(`update private.expense_claims set approval='rejected',revision=3 where id='${emptyClaim}'`);
  const cleared=(await db.query(`select * from invoices where id='${expenseOnly.id}'`)).rows[0];
  assert.ok(cleared,'existing draft is retained after rejection'); assert.equal(cleared.grand_total,0);
  assert.equal((await db.query(`select approval_current from private.expense_settlement_choices where claim_id='${emptyClaim}'`)).rows[0].approval_current,false);
  await db.exec(`update invoices set status='finalized' where id='${expenseOnly.id}'`);
  const protectedInvoice=(await db.query(`select * from invoices where id='${expenseOnly.id}'`)).rows[0];
  await assert.rejects(db.exec(`select public.expense_allocate_with_cost('${id(35)}','${legacyClaim}',4,'customer','${emptyCustomer}')`),/確定済み/);
  assert.deepEqual((await db.query(`select * from invoices where id='${expenseOnly.id}'`)).rows[0],protectedInvoice,'new recovery cannot mutate finalized historical document');
  await db.exec(`select private.expense_review_command('${id(36)}','${legacyClaim}',4,'allocate','customer','${emptyCustomer}')`);
  assert.deepEqual((await db.query(`select * from invoices where id='${expenseOnly.id}'`)).rows[0],protectedInvoice,'legacy allocation stays metadata and leaves finalized document byte-identical');
  await db.exec(`update invoices set snapshot=jsonb_set(snapshot,'{expense_extra_amount_yen}','1') where id='${opted.id}'`);
  await assert.rejects(db.exec(`select public.read_expense_document('invoice','${opted.id}')`),/内訳と帳票金額/,'mismatched monetary snapshots never render an inconsistent detail page');
  console.log('PASS charged detail IDs, revisions and original amounts agree for draft/finalized documents; unselected legacy claims stay excluded');
  console.log('PASS expense-only invoice has no fabricated attendance, no tax/welfare; rejection preserves draft; frozen method/allocation and original amount retained');
  console.log('PASS original expense once, unchanged tax/welfare, customer-to-subcontractor move, frozen recovery and original claim retained');
} finally {await db.close();}
