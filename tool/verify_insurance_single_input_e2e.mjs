// Disposable PG17 proof only. No production endpoint/credentials are accepted.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
import {validateResidentTaxFixtureUrl} from './resident_tax_pg17_database_guard.mjs';
const {PGlite}=await import(process.argv[2]);
const [phase,out]=process.argv.slice(4);
assert.ok(['prepare','apply'].includes(phase)); assert.ok(out);
fs.mkdirSync(out,{recursive:true});
const c='10000000-0000-0000-0000-000000000001',w='40000000-0000-0000-0000-000000000001';
const owner='00000000-0000-0000-0000-000000000001',editor='00000000-0000-0000-0000-000000000002';
const month='2026-10-01';
const read=p=>fs.readFileSync(p,'utf8');
let db;
if(phase==='prepare') db=new PGlite();
else {
 const pg=await import(process.argv[3]); const Client=pg.Client??pg.default?.Client;
 const client=new Client({connectionString:validateResidentTaxFixtureUrl(process.env.SKO_RESIDENT_TAX_FIXTURE_URL)});
 await client.connect();
 assert.equal(Math.floor(Number((await client.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 db={exec:sql=>client.query(sql),query:(sql,args)=>client.query(sql,args),close:()=>client.end()};
}
const actor=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
const row=async()=>{await db.exec('reset role');return (await db.query('select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start=$3',[c,w,month])).rows[0];};
try {
 if(phase==='prepare') {
  await setupPayrollScopeFixture(db);
  for(const p of ['supabase/migrations/20261009171504_payroll_refresh_scope_order.sql','supabase/migrations/20261009151946_company_payroll_rate_registry.sql','supabase/migrations/20261010030208_connect_payroll_tax_calculation.sql','supabase/migrations/20261013175452_payroll_unit_conditions.sql','supabase/migrations/20261014033249_payroll_fixed_deduction_overrides.sql']) await db.exec(read(p));
  await db.exec(`delete from public.attendance_entries;delete from public.payroll_statements;delete from public.payroll_adjustments;
   update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=700000,custom_earnings='[]',custom_deductions='[]',social_insurance_monthly=30000,income_tax_monthly=5000,resident_tax_monthly=12000 where worker_id='${w}';`);
  await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[c,w,month]);
  await db.query('select private.sync_payroll_attendance_detail($1,$2,$3)',[c,w,month]);
  const before=await row(); assert.equal(before.gross_pay,700000); assert.equal(before.deductions,47000);
  await actor(owner);
  for(const [kind,employee] of Object.entries({health_insurance:5000000,pension_insurance:9150000})) {
   const value={kind,label:kind,total:employee*2,employee,employer:employee,insurance_month:month,payroll_month:month,payment_month:'2026-11-01',source:{url:'https://example.test/fixture',publisher:'Synthetic fixture',document_hash:'fixture-only',applicability:{business:'fixture'}}};
   await db.query('select public.save_manual_company_payroll_rate($1,$2,0,$3::jsonb,true)',[c,kind,JSON.stringify(value)]);
  }
  await actor(editor);
  const state=(await db.query('select public.read_worker_payroll_tax_conditions($1,$2) result',[c,w])).rows[0].result;
  assert.equal(state.items.length,0,'no enrolled profile is inferred from initial checkboxes');
  fs.writeFileSync(path.join(out,'read-state.json'),JSON.stringify(state,null,2));
  fs.writeFileSync(path.join(out,'before.json'),JSON.stringify(before,null,2));
  console.log('Prepared actual empty condition read and existing calculator on disposable PG17');
 } else {
  const request=JSON.parse(read(path.join(out,'ui-save-request.json')));
  assert.equal(request.p_company_id,c);assert.equal(request.p_worker_id,w);assert.equal(request.p_starts_on,month);assert.equal(request.p_expected_version,0);assert.equal(request.p_confirmed,true);
  assert.equal(request.p_value.health_base_yen,710000);assert.equal(request.p_value.pension_base_yen,650000);
  assert.equal(request.p_value.insurance_mode,'rates');assert.equal(request.p_value.income_mode,'fixed');
  await actor(editor);
  const result=(await db.query('select public.save_worker_payroll_tax_conditions($1,$2,$3,$4,$5::jsonb,$6) result',[c,w,month,request.p_expected_version,JSON.stringify(request.p_value),request.p_confirmed])).rows[0].result;
  assert.equal(result.items[0].version,1);assert.deepEqual(result.items[0].value,request.p_value);
  const saved=await row();
  assert.equal(saved.calculation_blocked,false);
  assert.equal(saved.gross_pay,700000);
  assert.equal(saved.detail['健康保険料'],35500);assert.equal(saved.detail['厚生年金保険'],59475);
  assert.equal(saved.detail['所得税'],5000);assert.equal(saved.detail['住民税'],12000);
  assert.equal(saved.detail.tax_calculation.social_yen,94975);
  assert.equal(saved.deductions,111975);assert.equal(saved.net_pay,588025);
  assert.equal(saved.detail['社会保険'],undefined,'old aggregate cannot be counted twice');
  const revision=saved.revision;
  await actor(editor);
  const again=(await db.query('select public.save_worker_payroll_tax_conditions($1,$2,$3,$4,$5::jsonb,$6) result',[c,w,month,0,JSON.stringify(request.p_value),true])).rows[0].result;
  assert.equal(again.items[0].version,1);
  assert.equal((await row()).revision,revision,'same request retry does not recalculate again');
  fs.writeFileSync(path.join(out,'statement.json'),JSON.stringify(saved,null,2));
  fs.writeFileSync(path.join(out,'proof.json'),JSON.stringify({schema:1,fixture_only:true,production_connected:false,synthetic_authorization:true,actual_ui_payload:true,actual_calculator:true,average_input_yen:700000,health_base_yen:710000,pension_base_yen:650000,health_premium_yen:35500,pension_premium_yen:59475,gross_pay:saved.gross_pay,deductions:saved.deductions,net_pay:saved.net_pay,pdf_verified:false},null,2));
  console.log('PASS actual single-input UI payload → save RPC → actual calculator → saved statement totals');
 }
} finally {await db.close();}
