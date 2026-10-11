// Uses exact reviewed payroll calculator + normalization triggers in isolated SQL.
// Synthetic schema/access prerequisites; never connects to a linked database.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const read=p=>fs.readFileSync(p,'utf8');
const cid='10000000-0000-0000-0000-000000000001';
const wid='40000000-0000-0000-0000-000000000001';
const owner='00000000-0000-0000-0000-000000000001';
const editor='00000000-0000-0000-0000-000000000002';
const viewer='00000000-0000-0000-0000-000000000003';
const otherOwner='00000000-0000-0000-0000-000000000004';
async function actor(id,role='authenticated',denied=false) {
 await db.exec('reset role');
 await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('test.account_access_denied',$2,false)",[id,denied?'1':'']);
 await db.exec(`set role ${role}`);
}
async function save(version,mode,cutover,entries,confirmed=true) {
 return (await db.query('select public.save_worker_resident_tax_schedule($1,$2,$3,$4,$5,$6::jsonb,$7) as result',[cid,wid,version,mode,cutover,JSON.stringify(entries),confirmed])).rows[0].result;
}
async function state(month) {
 return (await db.query('select public.read_worker_resident_tax_schedule($1,$2,$3) as result',[cid,wid,month])).rows[0].result;
}
async function statement(month) {
 await db.exec('reset role');
 return (await db.query('select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start=$3',[cid,wid,month])).rows[0];
}
try {
 await setupPayrollScopeFixture(db);
 await db.exec(read('supabase/migrations/20261009171504_payroll_refresh_scope_order.sql'));
 await db.exec(read('supabase/migrations/20261009151946_company_payroll_rate_registry.sql'));
 const originalCalculator=(await db.query("select pg_get_functiondef('private.apply_payroll_custom_money()'::regprocedure) source")).rows[0].source;
 await db.exec("create or replace function private.apply_payroll_custom_money() returns trigger language plpgsql security definer set search_path='' as $$begin return new;end$$");
 await assert.rejects(db.exec(read('supabase/migrations/20261010030208_connect_payroll_tax_calculation.sql')),/prerequisite differs/);
 assert.equal((await db.query("select to_regnamespace('payroll_tax_private') n")).rows[0].n,null);
 await db.exec(originalCalculator);
 await db.exec(read('supabase/migrations/20261010030208_connect_payroll_tax_calculation.sql'));
 // All 231 official rows: lower endpoint, upper endpoint minus one, 8 koh columns and otsu.
 const official=JSON.parse(read('test/fixtures/nta_monthly_2026.json'));
 const tax=async(a,col='koh',n=0,date='2026-11-25')=>(await db.query('select payroll_tax_private.monthly_income_tax($1,$2,$3,$4) tax',[date,a,col,n])).rows[0].tax;
 for(const row of official.rows) for(const amount of [row[0],row[1]-1]) {
  for(let n=0;n<8;n++) assert.equal(await tax(amount,'koh',n),row[n+2]);
  assert.equal(await tax(amount,'otsu'),row[10]);
 }
 assert.equal(await tax(175000,'koh',2),250);
 assert.equal(await tax(446000,'koh',8),1010);
 assert.equal(await tax(775200,'koh',3),59477);
 assert.equal(await tax(104999,'otsu'),3216);
 assert.equal(await tax(0,'otsu'),0);
 assert.equal(await tax(740000),71680);
 assert.equal(await tax(790000),81890);
 assert.equal(await tax(960000),121820);
 assert.equal(await tax(1710000,'otsu'),655400);
 assert.equal(await tax(3500000),1125270);
 assert.equal(await tax(3500001),1125270);
 await assert.rejects(tax(300000,'koh',0,'2027-01-25'),/検証済み/);
 for(const [base,rate,expected] of [[100,500000,0],[101,500000,1],[300000,500000,1500],[0,500000,0]]) {
  assert.equal((await db.query('select payroll_tax_private.employee_premium($1,$2) n',[base,rate])).rows[0].n,expected);
 }
 const month='2026-09-01';
 await db.exec(`delete from public.attendance_entries;delete from public.payroll_statements;delete from public.payroll_adjustments;
 update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=300000,custom_earnings='[]',custom_deductions='[]',social_insurance_monthly=30000,income_tax_monthly=5000,resident_tax_monthly=12000 where worker_id='${wid}';`);
 await db.query('delete from public.payroll_statements where company_id=$1 and worker_id=$2',[cid,wid]);
 await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,month]);
 await db.query('select private.sync_payroll_attendance_detail($1,$2,$3)',[cid,wid,month]);
 const legacy=await statement(month);
 assert.equal(legacy.deductions,47000);
 const profile={insurance_mode:'fixed',health:false,pension:false,employment:false,child_support:false,nursing:false,birth_date:null,health_base_yen:0,pension_base_yen:0,income_mode:'koh',dependents:0,non_taxable_yen:0,employment_excluded_yen:0,additional_social_deduction_yen:0};
 const saveTax=async(version,value=profile,start=month)=>(await db.query('select public.save_worker_payroll_tax_conditions($1,$2,$3,$4,$5::jsonb,true) result',[cid,wid,start,version,JSON.stringify(value)])).rows[0].result;
 await actor(editor);
 const result=await saveTax(0);
 assert.equal(result.items[0].version,1);
 const calculated=await statement(month);
 assert.equal(calculated.deductions,42000+6860);
 assert.equal(calculated.detail['所得税'],6860);
 assert.equal(calculated.detail.tax_calculation.income_tax_base_yen,270000);
 assert.equal(calculated.net_pay,300000-calculated.deductions);
 const revision=calculated.revision;
 await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,month]);
 await db.query('select private.sync_payroll_attendance_detail($1,$2,$3)',[cid,wid,month]);
 assert.equal((await statement(month)).revision,revision,'unchanged display cannot invalidate reviews');
 await actor(editor);assert.equal((await saveTax(0)).items[0].version,1,'same saved request retry is idempotent');
 await assert.rejects(saveTax(0,{...profile,dependents:1}),/更新されています/);
 for(const id of [viewer,otherOwner,'']) {await actor(id);await assert.rejects(saveTax(1),/access denied/);}
 await actor(editor,'authenticated',true);await assert.rejects(saveTax(1),/access denied/);
 await actor(editor,'anon');await assert.rejects(saveTax(1),/permission denied/);
 await actor(editor);await assert.rejects(db.query('select * from payroll_tax_private.worker_conditions'),/permission denied/);
 await assert.rejects(db.query('select payroll_tax_private.calculate($1,$2,$3,$4,300000,47000)',[cid,wid,month,'2026-09-30']),/permission denied/);
 await db.exec('reset role');

 const rateValues={health_insurance:5000000,nursing_insurance:810000,pension_insurance:9150000,employment_insurance:500000,child_support:115000};
 await actor(owner);
 for(const [kind,employee] of Object.entries(rateValues)) {
  const rateValue={kind,label:kind,total:employee*2,employee,employer:employee,insurance_month:month,payroll_month:month,payment_month:'2026-10-01',source:{url:'https://example.test/fixture',publisher:'Synthetic fixture',document_hash:'fixture-only',applicability:{business:'fixture'}}};
  await db.query('select public.save_manual_company_payroll_rate($1,$2,0,$3::jsonb,true)',[cid,kind,JSON.stringify(rateValue)]);
 }
 const automatic={...profile,insurance_mode:'rates',health:true,pension:true,employment:true,child_support:true,nursing:true,birth_date:'1986-10-01',health_base_yen:300000,pension_base_yen:300000};
 await actor(editor);await saveTax(1,automatic);
 const rated=await statement(month);
 assert.equal(rated.detail.tax_calculation.social_yen,46725);
 assert.equal(rated.detail['介護保険料'],2430,'40th birthday on first day starts in prior month');
 assert.equal(rated.detail['所得税'],6220);
 assert.equal(rated.deductions,64945);
 assert.equal(rated.net_pay,235055);
 assert.equal(rated.detail['社会保険'],undefined,'legacy aggregate cannot double count');
 fs.mkdirSync('test/fixtures/payroll_tax_connection',{recursive:true});
 fs.writeFileSync('test/fixtures/payroll_tax_connection/automatic.json',JSON.stringify({gross_pay:rated.gross_pay,deductions:rated.deductions,net_pay:rated.net_pay,detail:{...rated.detail,company_seal_enabled:false}},null,2)+'\n');
 // Exercise real attendance INSERT/UPDATE/DELETE triggers, not only refresh RPCs.
 // Roll back this independent scenario so the finalized snapshot fixture is stable.
 await db.exec('reset role;begin');
 await db.query("update public.worker_payroll_settings set pay_type='daily',day_daily=10000,day_overtime=1563 where company_id=$1 and worker_id=$2",[cid,wid]);
 await db.query(`insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
 select gen_random_uuid(),$1,$2,'20000000-0000-0000-0000-000000000001',date '2026-09-01'+n,'day',1,0,0 from generate_series(0,19) n`,[cid,wid]);
 const fromAttendance=await statement(month);
 assert.equal(fromAttendance.gross_pay,200000);
 assert.equal(fromAttendance.detail['雇用保険料'],1000);
 assert.equal(fromAttendance.detail.tax_calculation.social_yen,46225);
 assert.equal(fromAttendance.detail['所得税'],official.rows.find(r=>r[0]<=153775&&r[1]>153775)[2]);
 assert.equal(fromAttendance.net_pay,200000-fromAttendance.deductions);
 await db.query("update public.attendance_entries set overtime_hours=1 where company_id=$1 and worker_id=$2 and work_date='2026-09-20'",[cid,wid]);
 assert.equal((await statement(month)).gross_pay,201563);
 await db.query("delete from public.attendance_entries where company_id=$1 and worker_id=$2 and work_date='2026-09-01'",[cid,wid]);
 const afterDelete=await statement(month);
 assert.equal(afterDelete.gross_pay,191563);
 await actor(owner);
 const ownDaily=(await db.query('select * from public.my_payroll_statement_rows_with_adjustments()')).rows.find(x=>x.id===afterDelete.id);
 assert.equal(ownDaily.deductions,afterDelete.deductions);
 assert.equal(ownDaily.net_pay,afterDelete.net_pay);
 await db.exec('reset role;rollback');
 await actor(editor);await saveTax(2,{...automatic,birth_date:'1986-10-02'});
 assert.equal((await statement(month)).detail['介護保険料'],0,'40th birthday after first day starts next month');
 await actor(editor);await saveTax(3,{...automatic,birth_date:'1961-10-01'});
 assert.equal((await statement(month)).detail['介護保険料'],0,'65th birthday on first day stops in prior month');
 await actor(editor);await saveTax(4,automatic);
 await db.exec('reset role');
 await db.query("insert into public.payroll_adjustments(company_id,worker_id,effective_date,label_snapshot,direction,amount_yen) values($1,$2,$3,'Taxable adjustment','addition',10000)",[cid,wid,'2026-09-15']);
 await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,month]);
 const adjustedTax=await statement(month);
 assert.equal(adjustedTax.detail.tax_calculation.gross_with_adjustments,310000);
 assert.equal(adjustedTax.detail['雇用保険料'],1550);
 assert.equal(adjustedTax.detail.tax_calculation.income_tax_base_yen,263225);
 assert.equal(adjustedTax.detail['所得税'],6650);
 const adjustedRevision=adjustedTax.revision;
 await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,month]);
 assert.equal((await statement(month)).revision,adjustedRevision);
 // A missing future-year rule blocks only payroll, not the attendance transaction.
 await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,'2026-12-01']);
 const blocked=await statement('2026-12-01');
 assert.equal(blocked.calculation_blocked,true);
 assert.equal(blocked.detail.tax_calculation.blocked,true);
 await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,'2026-12-01']);
 assert.equal((await statement('2026-12-01')).revision,blocked.revision);
 // Remove the synthetic future draft before exercising a valid condition change.
 await db.query("delete from public.payroll_statements where period_start='2026-12-01'");
 const toFinalize=await statement(month);
 await db.query('insert into public.payroll_confirmers(company_id,user_id,position) values($1,$2,1)',[cid,owner]);
 await db.query('insert into public.payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[toFinalize.id,owner,toFinalize.revision]);
 await actor(owner);
 const finalized=(await db.query('select public.finalize_payroll_statement($1,$2,true) result',[toFinalize.id,toFinalize.revision])).rows[0].result;
 assert.equal(finalized.finalized,true);
 assert.equal(finalized.snapshot.conditions.company_rate_registry_adopted,true);
 assert.equal(finalized.snapshot.conditions.income_tax_official_catalog,'nta-monthly-2026-c583c9c3');
 const savedDocument=finalized.snapshot;

 const frozen=await statement(month);
 await actor(editor);await saveTax(5,{...automatic,dependents:1});
 assert.deepEqual(await statement(month),frozen,'confirmed payroll is byte-for-byte preserved');
 await actor(owner);
 const persisted=(await db.query('select public.finalize_payroll_statement($1,$2,true) result',[toFinalize.id,toFinalize.revision])).rows[0].result;
 assert.deepEqual(persisted.snapshot,savedDocument,'snapshot retains exact tax conditions after future configuration changes');
 const rendered=(await db.query('select * from public.my_payroll_statement_rows_with_adjustments()')).rows.find(x=>x.id===toFinalize.id);
 assert.equal(rendered.deductions,savedDocument.result.deductions);
 assert.deepEqual(rendered.detail.tax_calculation,savedDocument.detail.tax_calculation);

 console.log('PASS: official 2026 monthly table (4158 endpoints), rounding, fixed-to-automatic payroll, repeated refresh, CAS, ACL, finalized preservation');
} finally {await db.close();}
