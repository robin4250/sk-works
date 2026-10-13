import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();const read=p=>fs.readFileSync(p,'utf8');
const cid='10000000-0000-0000-0000-000000000001',owner='00000000-0000-0000-0000-000000000001',w1='40000000-0000-0000-0000-000000000001',w2='40000000-0000-0000-0000-000000000002';
async function actor(id,role='authenticated'){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec(`set role ${role}`);}
try{
 await setupPayrollScopeFixture(db);
 const original=(await db.query("select pg_get_functiondef('private.attendance_refresh_payroll()'::regprocedure) definition")).rows[0].definition;
 await db.exec("create or replace function private.attendance_refresh_payroll() returns trigger language plpgsql security definer set search_path='' as $$begin return null;end$$");
 await assert.rejects(db.exec(read('supabase/migrations/20261009171504_payroll_refresh_scope_order.sql')),/prerequisite differs/);
 assert.equal((await db.query("select to_regnamespace('payroll_scope_private') namespace")).rows[0].namespace,null);
 await db.exec(original);
 await db.exec(read('supabase/migrations/20261009171504_payroll_refresh_scope_order.sql'));

 await db.exec(`update public.companies set name='Original Company';delete from public.attendance_entries;delete from public.payroll_statements;update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=300000,resident_tax_monthly=12000,family_monthly=0,transport_monthly=0,income_tax_monthly=0,social_insurance_monthly=0,other_deduction_monthly=0,custom_earnings='[]',custom_deductions='[]';`);
 const today=(await db.query("select (now() at time zone 'Asia/Tokyo')::date::text work_day")).rows[0].work_day;
 const report='a0000000-0000-0000-0000-000000000001',site='70000000-0000-0000-0000-000000000001';
 await db.query("insert into public.sites(id,company_id,name) values($1,$2,'Site')",[site,cid]);
 await db.query('insert into public.daily_reports(id,company_id,site_id,report_date) values($1,$2,$3,$4)',[report,cid,site,today]);
 await db.query('insert into public.daily_report_workers(report_id,worker_id) values($1,$2),($1,$3)',[report,w2,w1]);
 await actor(owner);await db.query('select public.save_daily_report_vehicle_usage($1,$2,null,null,null)',[report,w1]);
 await actor(owner);await assert.rejects(db.query("select payroll_scope_private.lock_scopes('[]')"),/permission denied/);
 await db.query("select public.save_daily_report_signature($1,'representative','Representative',$2::jsonb)",[report,JSON.stringify({strokes:[[1,2]]})]);
 await db.exec('reset role');assert.equal((await db.query('select count(*)::integer n from public.attendance_entries where source_report_id=$1',[report])).rows[0].n,0);
 await actor(owner);await db.query("select public.save_daily_report_signature($1,'supervisor','Supervisor',$2::jsonb)",[report,JSON.stringify({strokes:[[3,4]]})]);
 await db.exec('reset role');assert.equal((await db.query('select count(*)::integer n from public.attendance_entries where source_report_id=$1',[report])).rows[0].n,2);
 const ps=(await db.query('select * from public.payroll_statements where company_id=$1 and worker_id=$2 order by period_start desc limit 1',[cid,w1])).rows[0];
 await db.query('insert into public.payroll_confirmers(company_id,user_id,position) values($1,$2,1)',[cid,owner]);
 await db.query('insert into public.payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[ps.id,owner,ps.revision]);
 await actor(owner);const final=(await db.query('select public.finalize_payroll_statement($1,$2,true) result',[ps.id,ps.revision])).rows[0].result;assert.equal(final.finalized,true);
 const before=(await db.query('select * from public.my_payroll_statement_rows_with_adjustments()')).rows.find(r=>r.id===ps.id);assert.equal(before.detail.workflow_state,'finalized');assert.equal(before.detail.review_confirmed,true);assert.equal(before.detail.revision,ps.revision);assert.ok(before.detail.reviewed_at);
 await db.query('select public.cancel_payroll_review_month($1)',[ps.period_start]);
 const after=(await db.query('select * from public.my_payroll_statement_rows_with_adjustments()')).rows.find(r=>r.id===ps.id);assert.deepEqual(after,before,'final self must keep saved confirmation after live review cancellation');
 const workspace=(await db.query('select public.payroll_review_workspace($1) result',[ps.period_start])).rows[0].result;const finalRow=workspace.statements.find(r=>r.id===ps.id);assert.equal(finalRow.review_confirmed,true);assert.equal(finalRow.reviewer_confirmed,true);assert.equal(finalRow.workflow_state,'finalized');
 await db.exec('reset role');await db.query("update public.payroll_statements set period_start='2000-01-01',period_end='2000-01-31',issued_at='2000-01-01' where id=$1",[ps.id]);
 await actor(owner);assert.deepEqual((await db.query('select * from public.my_payroll_statement_rows_with_adjustments()')).rows.find(r=>r.id===ps.id),before,'final headers must read saved period and issuance');
 const savedWorkspace=(await db.query('select public.payroll_review_workspace($1) result',[ps.period_start])).rows[0].result;assert.deepEqual(savedWorkspace.statements.find(r=>r.id===ps.id),finalRow);
 const draft=(await db.query('select * from public.my_payroll_statement_rows_with_adjustments()')).rows.find(r=>r.detail.workflow_state==='draft'); // Owner has no remaining draft; another worker is self-scoped separately.
 await actor('00000000-0000-0000-0000-000000000002');const myDraft=(await db.query('select * from public.my_payroll_statement_rows_with_adjustments()')).rows.find(r=>r.detail.workflow_state==='draft');assert.ok(myDraft);assert.equal(typeof myDraft.detail.revision,'number');
 await actor('', 'anon');await assert.rejects(db.query("select public.sign_daily_report($1,'Signer','{}')",[report]),/permission denied/);
 console.log('PASS known scope ordering: source guards, original signature flow, helper privacy, snapshot saved state/header/confirmation, draft live state');

}catch(e){console.error(e.message,e.where||'',e.position||'',e.query?.slice(Number(e.position)-60,Number(e.position)+60)||'');process.exitCode=1;}finally{await db.close();}
