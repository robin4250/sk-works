import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';
const {PGlite} = await import(process.argv[2]);
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
try {
  await setupExpenseCostFixture(db);
  await db.exec(fs.readFileSync('supabase/migrations/20261012142138_expense_document_original_costs.sql','utf8'));
  const company=id(1), worker=id(2), actor=id(3);
  await db.exec(`insert into companies(id) values('${company}');
    insert into company_members values('${company}','${actor}','owner');
    insert into workers(id,company_id,name,user_id) values('${worker}','${company}','申請者','${actor}');
    insert into private.expense_approval_settings(company_id,approver_ids,revision) values('${company}',array['${actor}']::uuid[],1);
    set test.uid='${actor}';`);
  async function claim(n,submitted,incurred='2026-09-01') {
    await db.exec(`insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen)
      values('${id(n)}','${company}','${worker}','申請者','${actor}','${incurred}','${submitted}','月境界検証',1000)`);
  }
  const approve=async(n,c,method,month,revision=1)=>(await db.query(`select public.expense_approve_with_settlement('${id(n)}','${id(c)}',${revision},'${method}','${month}') value`)).rows[0].value;
  await claim(10,'2026-09-30T15:00:00Z');
  const legacy=await approve(20,10,'cash','2026-11-01');
  const oldChoice=(await db.query('select * from private.expense_settlement_choices')).rows;
  const oldEvents=(await db.query('select * from private.expense_settlement_events')).rows;
  const oldClaims=(await db.query('select * from private.expense_claims')).rows;
  const before=(await db.query(`select proacl::text acl,prosecdef,proconfig from pg_proc where oid='private.expense_approve_with_settlement(uuid,uuid,integer,text,date)'::regprocedure`)).rows;
  await db.exec(fs.readFileSync('supabase/migrations/20261012163343_expense_settlement_application_month.sql','utf8'));
  assert.deepEqual((await db.query('select * from private.expense_settlement_choices')).rows,oldChoice);
  assert.deepEqual((await db.query('select * from private.expense_settlement_events')).rows,oldEvents);
  assert.deepEqual((await db.query('select * from private.expense_claims')).rows,oldClaims);
  assert.deepEqual((await db.query(`select proacl::text acl,prosecdef,proconfig from pg_proc where oid='private.expense_approve_with_settlement(uuid,uuid,integer,text,date)'::regprocedure`)).rows,before);
  assert.deepEqual(await approve(20,10,'cash','2026-11-01'),legacy,'old fixed receipt replays unchanged');
  await claim(11,'2026-09-30T14:59:59Z');
  await assert.rejects(approve(21,11,'cash','2026-10-01'),/申請月/);
  assert.equal((await approve(21,11,'cash','2026-09-01')).settlement_month,'2026-09-01');
  await claim(12,'2026-09-30T15:00:00Z');
  await assert.rejects(approve(22,12,'payroll','2026-09-01'),/申請月/);
  const paid=await approve(22,12,'payroll','2026-10-01');
  assert.equal(paid.settlement_month,'2026-10-01');
  assert.equal(paid.incurred_on,'2026-09-01','invoice incurred month remains independent');
  assert.deepEqual(await approve(22,12,'payroll','2026-10-01'),paid);
  await assert.rejects(approve(22,12,'cash','2026-10-01'),/fixed expense settlement command differs/);
  await claim(13,'2026-12-31T15:00:00Z');
  assert.equal((await approve(23,13,'cash','2027-01-01')).settlement_month,'2027-01-01');
  await claim(14,'2026-09-30T15:00:00Z');
  const originalSubmitted=(await db.query(`select submitted_at from private.expense_claims where id='${id(14)}'`)).rows[0].submitted_at;
  await db.exec(`select public.expense_personal_change('${id(24)}','${id(14)}',1,'edit','2026-08-01','日付変更',2000)`);
  assert.deepEqual((await db.query(`select submitted_at from private.expense_claims where id='${id(14)}'`)).rows[0].submitted_at,originalSubmitted);
  assert.equal((await approve(25,14,'cash','2026-10-01',2)).settlement_month,'2026-10-01');
  console.log('PASS Japan application month cash/payroll, UTC month/year boundaries, original application time after edits, legacy receipts/rows/ACL preserved; incurred-month contract unchanged');
} finally { await db.close(); }
