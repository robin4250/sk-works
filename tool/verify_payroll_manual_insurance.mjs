// Synthetic disposable payroll fixture. No hosted credentials or connections.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const {setupPayrollScopeFixture}=await import(process.env.SKO_PAYROLL_SCOPE_FIXTURE_MODULE || './payroll_scope_fixture_setup.mjs');
let db;
if(process.argv[3]==='postgres') {
 const pg=(await import(process.argv[2])).default;
 const url=new URL(process.env.SKO_PAYROLL_MANUAL_FIXTURE_URL??'');
 if(!['127.0.0.1','localhost'].includes(url.hostname)||url.pathname!=='/sko_manual_insurance_fixture') throw Error('disposable loopback manual-insurance fixture required');
 pg.types.setTypeParser(20,Number);pg.types.setTypeParser(1700,Number);
 const client=new pg.Client({connectionString:url.href});await client.connect();
 db={query:(...args)=>client.query(...args),exec:sql=>client.query(sql),close:()=>client.end()};
} else {const {PGlite}=await import(process.argv[2]);db=new PGlite();}
const read=p=>fs.readFileSync(p,'utf8');
const candidate=process.env.SKO_MANUAL_INSURANCE_SQL || 'docs/candidates/payroll_manual_insurance_20261020.sql.review-only';
const commonRoot=process.env.SKO_COMMON_PAYROLL_SOURCE_ROOT || '.';
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001';
const owner='00000000-0000-0000-0000-000000000001',viewer='00000000-0000-0000-0000-000000000003';
const month='2026-09-01',monthEnd='2026-09-30';
const session=id=>id.replace(/^0/,'7');
async function actor(id=owner,role='authenticated',denied=false){
 await db.exec('reset role');
 await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false),set_config('test.account_access_denied',$3,false)",[id,JSON.stringify({sub:id,role,session_id:session(id)}),denied?'1':'']);
 await db.exec(`set role ${role}`);
}
const statement=async(period=month)=>{await db.exec('reset role');return(await db.query('select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start=$3',[cid,wid,period])).rows[0];};
const save=async(version,value,period=month,confirmed=true)=>(await db.query('select public.save_worker_payroll_tax_conditions($1,$2,$3,$4,$5::jsonb,$6) value',[cid,wid,period,version,JSON.stringify(value),confirmed])).rows[0].value;
const profile={insurance_mode:'fixed',income_mode:'fixed',health:false,pension:false,employment:false,child_support:false,nursing:false,birth_date:null,health_base_yen:0,pension_base_yen:0,dependents:0,non_taxable_yen:0,employment_excluded_yen:0,additional_social_deduction_yen:0};
const premiums={health_insurance:5000,pension_insurance:9000,employment_insurance:1200,nursing_insurance:0,child_support:0};
const manual={insurance_mode:'manual',income_mode:'fixed',manual_insurance_premiums:premiums,dependents:0,non_taxable_yen:0,additional_social_deduction_yen:0};
try {
 await setupPayrollScopeFixture(db);
 for(const path of ['20261009171504_payroll_refresh_scope_order.sql','20261009151946_company_payroll_rate_registry.sql','20261010030208_connect_payroll_tax_calculation.sql','20261013175452_payroll_unit_conditions.sql','20261014033249_payroll_fixed_deduction_overrides.sql']) await db.exec(read('supabase/migrations/'+path));
 await db.exec(`reset role;delete from public.attendance_entries;delete from public.payroll_statements;delete from public.payroll_adjustments;
 update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=300000,custom_earnings='[]',custom_deductions='[]',social_insurance_monthly=30000,income_tax_monthly=5000,resident_tax_monthly=12000 where worker_id='${wid}';`);
 await db.query("select private.refresh_automatic_payroll($1,$2,'2026-08-01')",[cid,wid]);
 const frozenLegacy=await statement('2026-08-01');assert.equal(frozenLegacy.deductions,47000);
 await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,month]);
 await actor();
 for(const [kind,employee] of Object.entries({health_insurance:5000000,nursing_insurance:810000,pension_insurance:9150000,employment_insurance:500000,child_support:115000})) {
  const value={kind,label:kind,total:employee*2,employee,employer:employee,insurance_month:month,payroll_month:month,payment_month:'2026-10-01',source:{url:'https://example.test/manual-fixture',publisher:'Synthetic fixture',document_hash:'fixture-only',applicability:{business:'fixture'}}};
  await db.query('select public.save_manual_company_payroll_rate($1,$2,0,$3::jsonb,true)',[cid,kind,JSON.stringify(value)]);
 }
 const rates={...profile,insurance_mode:'rates',health:true,pension:true,employment:true,child_support:true,nursing:true,birth_date:'1986-10-01',health_base_yen:300000,pension_base_yen:300000,income_mode:'koh'};
 await save(0,rates);const automatic=await statement();assert.equal(automatic.detail.tax_calculation.social_yen,46725);
 const signatures=['payroll_tax_private.validate_conditions(jsonb)','payroll_tax_private.calculate(uuid,uuid,date,date,bigint,bigint)','payroll_tax_private.read_conditions(uuid,uuid)','private.apply_payroll_custom_money()'];
 const metadata=async()=>(await db.query(`select oid,proowner,proacl,proconfig,prosecdef,provolatile from pg_proc where oid=any($1::regprocedure[]) order by oid`,[signatures])).rows;
 const originalMetadata=await metadata();
 await db.exec(read(candidate));
 assert.deepEqual(await metadata(),originalMetadata,'existing OIDs, owners, grants and security modes retained');
 assert.deepEqual(await statement(),automatic,'install alone never edits existing rates conditions or statement');
 await actor();let state=(await db.query('select public.read_worker_payroll_tax_conditions($1,$2) value',[cid,wid])).rows[0].value;
 assert.equal(state.manual_insurance_contract_version,1);
 assert.deepEqual(state.items[0].value,rates);
 await save(1,manual);let saved=await statement();
 assert.equal(saved.detail.tax_calculation.social_yen,15200);
 assert.equal(saved.detail['健康保険料'],5000);assert.equal(saved.detail['厚生年金保険'],9000);assert.equal(saved.detail['雇用保険料'],1200);assert.equal(saved.detail['介護保険料'],0);
 assert.equal(saved.detail['社会保険'],undefined);assert.equal(saved.detail['所得税'],5000);assert.equal(saved.detail['住民税'],12000);
 assert.equal(saved.deductions,32200);assert.equal(saved.net_pay,267800);
 assert.equal(saved.detail.tax_calculation.automatic_premiums,null);
 assert.deepEqual(saved.detail.tax_calculation.conditions,manual);
 for(const key of ['health','pension','employment','nursing','health_base_yen','pension_base_yen']) assert.equal(key in saved.detail.tax_calculation.conditions,false,'no fabricated enrollment/base');
 assert.deepEqual(await statement('2026-08-01'),frozenLegacy,'prior legacy month preserved');
 await actor();await save(1,manual);assert.deepEqual(await statement(),saved,'identical retry does not recalculate');
 await db.exec('reset role;begin');await actor();
 await save(2,{...manual,manual_insurance_premiums:Object.fromEntries(Object.keys(premiums).map(key=>[key,0]))});
 const zeroStatement=await statement();assert.equal(zeroStatement.detail.tax_calculation.social_yen,0);assert.equal(zeroStatement.deductions,17000);
 await db.exec('rollback');assert.deepEqual(await statement(),saved);
 const invalid=[
  {...manual,manual_insurance_premiums:{...premiums,nursing_insurance:undefined}},
  {...manual,manual_insurance_premiums:{...premiums,nursing_insurance:null}},
  {...manual,manual_insurance_premiums:{...premiums,nursing_insurance:''}},
  {...manual,manual_insurance_premiums:{...premiums,nursing_insurance:-1}},
  {...manual,manual_insurance_premiums:{...premiums,nursing_insurance:0.5}},
  {...manual,manual_insurance_premiums:{...premiums,nursing_insurance:2147483648}},
  {...manual,manual_insurance_premiums:{...premiums,health_insurance:2147483647,pension_insurance:1}},
  {...manual,health:false},
  {...manual,deduction_overrides:{health_insurance:1}},
 ];
 for(const bad of invalid){await actor();await assert.rejects(save(2,bad));assert.deepEqual(await statement(),saved,'invalid input leaves payroll unchanged');}
 await actor();await assert.rejects(save(2,manual,month,false),/確認/);
 await actor(viewer);await assert.rejects(save(2,manual),/access denied/);
 await actor('00000000-0000-0000-0000-000000000004');await assert.rejects(save(2,manual),/access denied/);
 await actor(owner,'anon');await assert.rejects(save(2,manual),/permission denied/);
 await actor(owner,'authenticated',true);await assert.rejects(save(2,manual),/access denied/);
 await actor();await assert.rejects(save(1,{...manual,manual_insurance_premiums:{...premiums,health_insurance:5100}}),/更新されています/);
 const calculatedIncome={...manual,income_mode:'koh'};
 await save(2,calculatedIncome);saved=await statement();
 assert.equal(saved.detail.tax_calculation.income_tax_base_yen,284800);
 const tax=(await db.query("select payroll_tax_private.monthly_income_tax('2026-10-25',284800,'koh',0) n")).rows[0].n;
 assert.equal(saved.detail['所得税'],tax);assert.equal(saved.deductions,15200+12000+tax);
 await actor();await save(3,rates);saved=await statement();
 for(const key of ['健康保険料','介護保険料','厚生年金保険','雇用保険料','所得税'])assert.equal(saved.detail[key],automatic.detail[key],'original rates remain available');
 await actor();await save(4,manual);saved=await statement();
 await db.exec('reset role;begin');
 await db.query(`update public.worker_payroll_settings set custom_deductions='[{"name":"健康保険料","amount_yen":100}]' where company_id=$1 and worker_id=$2`,[cid,wid]);
 assert.equal((await statement()).calculation_blocked,true,'manual duplicate insurance is blocked');
 await db.exec('rollback');assert.deepEqual(await statement(),saved);
 // Reuse the existing common allowance saver and effective-publication layer.
 await db.exec(`create role service_role nologin;
 alter table public.companies add column if not exists default_welfare_rate numeric default 0,add column if not exists tax_rate numeric default 10,add column if not exists updated_at timestamptz;
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create function auth.jwt() returns jsonb language sql as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;`);
 for(const id of [owner,viewer])await db.query('insert into auth.sessions values($1,$2,null)',[session(id),id]);
 const foundation=read('supabase/tests/company_allowance_identity_access_fixture.sql');
 await db.exec(foundation.slice(foundation.indexOf('create table public.company_rate_settings('),foundation.indexOf('create table public.payroll_statements')));
 await db.query('insert into public.company_rate_settings(company_id) values($1)',[cid]);
 for(const path of ['20260922020000_add_company_rate_settings_management.sql','20261003002700_add_attendance_allowance_display_units.sql','20261008043823_atomic_company_rate_and_allowance_units_save.sql','20261009201229_company_allowance_identity_lifecycle.sql']) await db.exec(read('supabase/migrations/'+path));
 for(const path of ['tool/staged_company_common_allowances.sql.review-only','docs/candidates/company_common_payroll_bridge_20261020.sql.review-only','docs/candidates/company_common_payroll_effective_20261020.sql.review-only'])await db.exec(read(path.startsWith('tool/')?commonRoot+'/'+path:(process.env.SKO_COMMON_PAYROLL_CANDIDATE_ROOT || commonRoot)+'/'+path));
 const currentMonth=(await db.query("select date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')::date::text as current_month")).rows[0].current_month;
 await db.query('insert into company_common_allowance_private.payroll_activation values($1,$2)',[cid,currentMonth]);
 await actor();let common=(await db.query('select public.read_company_common_allowances_admin($1) value',[cid])).rows[0].value;
 const legacyRefs=common.legacy_refs.map(({slot,id,generation,name,source_unit,amount_yen})=>({slot,id,generation,name,source_unit,amount_yen}));
 const request='80000000-0000-0000-0000-000000000001';
 await db.query('select public.save_company_common_allowances($1,$2,$3,$4::jsonb,$5,$6::jsonb,$7::jsonb,true)',[cid,'monthly',common.version,JSON.stringify(common.expected_source),request,JSON.stringify([{id:null,client_key:'common-earning',section:'earning',unit:'month',name:'共通月額fixture',amount_yen:700},{id:null,client_key:'common-deduction',section:'deduction',unit:'month',name:'共通控除fixture',amount_yen:200}]),JSON.stringify(legacyRefs)]);
 let timeline=(await db.query('select public.read_company_common_payroll_publications($1) value',[cid])).rows[0].value;
 await db.query('select public.publish_company_common_payroll($1,$2,$3,$4,$5::jsonb,$6,$7)',[cid,'monthly',currentMonth,timeline.common_version,JSON.stringify(timeline.common_source),timeline.timeline_version,'80000000-0000-0000-0000-000000000002']);
 let withCommon=await statement(currentMonth);
 assert.equal(withCommon.gross_pay,300700);assert.equal(withCommon.deductions,32400);assert.equal(withCommon.net_pay,268300);
 assert.equal(withCommon.detail['健康保険料'],5000);assert.equal(withCommon.detail['所得税'],5000);assert.equal(withCommon.detail['住民税'],12000);
 const commonItems=withCommon.detail.unit_resolution.items.filter(x=>x.origin==='company_common');assert.equal(commonItems.length,2);
 const beforeConditions=(await db.query('select * from payroll_tax_private.worker_conditions where company_id=$1 and worker_id=$2',[cid,wid])).rows;
 const beforePublications=(await db.query('select * from company_common_allowance_private.payroll_publications')).rows;
 await db.query(`update public.worker_payroll_settings set custom_earnings='[{"name":"個別手当fixture","amount_yen":100}]' where company_id=$1 and worker_id=$2`,[cid,wid]);
 withCommon=await statement(currentMonth);assert.equal(withCommon.gross_pay,300800);assert.equal(withCommon.deductions,32400);assert.equal(withCommon.net_pay,268400);
 assert.deepEqual(withCommon.detail.unit_resolution.items.filter(x=>x.origin==='company_common'),commonItems);
 assert.deepEqual((await db.query('select * from payroll_tax_private.worker_conditions where company_id=$1 and worker_id=$2',[cid,wid])).rows,beforeConditions);
 assert.deepEqual((await db.query('select * from company_common_allowance_private.payroll_publications')).rows,beforePublications);
 // Finalized statements retain their exact recorded premiums and totals.
 saved=await statement();await db.query('insert into public.payroll_confirmers(company_id,user_id,position) values($1,$2,1)',[cid,owner]);
 await db.query('insert into public.payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[saved.id,owner,saved.revision]);
 await actor();await db.query('select public.finalize_payroll_statement($1,$2,true)',[saved.id,saved.revision]);
 const final=await statement();await actor();await save(5,{...manual,manual_insurance_premiums:{...premiums,health_insurance:5100}});
 assert.deepEqual(await statement(),final,'later manual edits never overwrite finalized statement');
 await db.exec('reset role');await assert.rejects(db.exec(read(candidate)),/baseline differs/);await db.exec('rollback');
 console.log('PASS explicit manual amounts: rates/legacy unchanged, no invented enrollment, empty versus zero, save/CAS/audit, tax/resident/common integration, named totals, final protection');
} catch(error) {console.error(error.message);process.exitCode=1;} finally {await db.close();}
