// Disposable PGlite only. Uses the saved payroll fixture and exact production body.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
let db;
const native=process.argv[3]==='postgres';
if(native) {
 const reject=()=>{throw Error('Only the local disposable sko_unit_fixture PostgreSQL 17 URL is permitted');};
 let url;try{url=new URL(process.env.SKO_UNIT_FIXTURE_URL??'');}catch{reject();}
 if(!['postgres:','postgresql:'].includes(url.protocol)||!['127.0.0.1','localhost'].includes(url.hostname)||url.port!=='5432'||url.pathname!=='/sko_unit_fixture'||url.search||url.hash||url.username!=='postgres'||url.password!=='fixture-only')reject();
 const pg=(await import(process.argv[2])).default;
 pg.types.setTypeParser(20,Number);pg.types.setTypeParser(1700,Number);
 const client=new pg.Client({connectionString:url.href,application_name:'sko-payroll-null-category-fixture'});
 await client.connect();
 db={query:(...args)=>client.query(...args),exec:sql=>client.query(sql),close:()=>client.end()};
 try {
  assert.equal(Math.floor(Number((await client.query('show server_version_num')).rows[0].server_version_num)/10000),17,'PostgreSQL 17 required');
  assert.equal(Number((await client.query("select count(*) n from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where ns.nspname not in ('pg_catalog','information_schema') and ns.nspname not like 'pg_toast%' and c.relkind in ('r','v','m')")).rows[0].n),0,'Disposable database must start empty');
  await client.query("set statement_timeout='30s';set lock_timeout='10s'");
 } catch(error) {await client.end();throw error;}
} else {const {PGlite}=await import(process.argv[2]);db=new PGlite();}
const read=p=>fs.readFileSync(p,'utf8');
const candidate=process.argv[native?4:3]??'supabase/migrations/20261018215043_fix_payroll_null_work_category.sql';
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001';
const site='20000000-0000-0000-0000-000000000001';
const oid="'private.refresh_automatic_payroll_internal(uuid,uuid,date)'::regprocedure";
const metadata=async()=>(await db.query(`select prosrc,proowner,proacl,proconfig,prosecdef,provolatile,proparallel from pg_proc where oid=${oid}`)).rows[0];
const refresh=async()=>db.query('select private.refresh_automatic_payroll_internal($1,$2,$3)',[cid,wid,'2026-09-01']);
const row=async()=>(await db.query("select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-09-01'",[cid,wid])).rows[0];
async function begin({category='day',type='daily',trade=false}={}) {
 await db.exec('begin;reset role');
 await db.exec(`delete from public.attendance_entries;delete from public.payroll_statements;delete from public.payroll_adjustments;
 update public.worker_payroll_settings set pay_type='${type}',day_daily=20000,day_overtime=2500,day_early=2500,
 monthly_salary_yen=300000,custom_earnings='[]',custom_deductions='[]',family_monthly=0,transport_monthly=0,
 income_tax_monthly=0,social_insurance_monthly=0,resident_tax_monthly=0,other_deduction_monthly=0 where worker_id='${wid}';`);
 if(trade) await db.exec(`insert into public.trade_companies(id,company_id) values('90000000-0000-0000-0000-000000000099','${cid}');
 insert into public.trade_company_contracts(company_id,trade_company_id,contract_method,daily_rate_yen) values('${cid}','90000000-0000-0000-0000-000000000099','daily',32000);
 insert into public.site_calculation_source_preferences(company_id,site_id,output_type,source,trade_company_id) values('${cid}','${site}','payroll','trade_company','90000000-0000-0000-0000-000000000099');`);
 for(const date of ['2026-09-12','2026-09-16']) await db.query(`insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days,overtime_hours,early_hours) values(gen_random_uuid(),$1,$2,$3,$4,$5,1,2,1)`,[cid,wid,site,date,category]);
 await refresh(); return row();
}
try {
 await setupPayrollScopeFixture(db);
 for(const path of ['supabase/migrations/20261009171504_payroll_refresh_scope_order.sql','supabase/migrations/20261009151946_company_payroll_rate_registry.sql','supabase/migrations/20261010030208_connect_payroll_tax_calculation.sql','supabase/migrations/20261013175452_payroll_unit_conditions.sql','supabase/migrations/20261014033249_payroll_fixed_deduction_overrides.sql']) await db.exec(read(path));
 const before=await metadata();assert.equal((await db.query(`select md5(prosrc) hash from pg_proc where oid=${oid}`)).rows[0].hash,'2c5230eea880fe8cddbe60bc6c4c0782');
 const broken=await begin({category:null});
 assert.equal(broken.gross_pay,0,'negative control must reproduce the NULL-category lost-rate bug');
 assert.ok(broken.detail['基本給']>0,'existing detail uses day fallback independently');
 await db.exec('rollback');
 console.log('PASS parent negative control: NULL category loses total while saved basic remains positive');
 const oldDefinition=(await db.query(`select pg_get_functiondef(${oid}) definition`)).rows[0].definition;
 await db.exec('begin');
 await db.exec("create or replace function private.refresh_automatic_payroll_internal(cid uuid,wid uuid,day date) returns void language plpgsql security definer set search_path='' as $$begin return;end$$");
 await assert.rejects(db.exec(read(candidate)),/prerequisite differs/);
 await db.exec('rollback');
 assert.equal((await metadata()).prosrc,before.prosrc);
 await db.exec(read(candidate));
 const after=await metadata();
 assert.equal(after.prosrc,before.prosrc.replace('category:=a.work_category;',"category:=coalesce(a.work_category,'day');"));
 for(const key of ['proowner','proacl','proconfig','prosecdef','provolatile','proparallel']) assert.deepEqual(after[key],before[key],key+' changed');
 const fixed=await begin({category:null});assert.equal(fixed.gross_pay,55000);assert.equal(fixed.detail['基本給'],40000);assert.equal(fixed.deductions,0);assert.equal(fixed.net_pay,fixed.gross_pay);await db.exec('rollback');
 const day=await begin();assert.equal(day.gross_pay,fixed.gross_pay);assert.equal(day.detail['基本給'],fixed.detail['基本給']);await db.exec('rollback');
 console.log('PASS fixed NULL and explicit day: two days + overtime + early, saved basic and totals agree');
 for(const category of ['day','night','holiday','holiday_night']) for(const type of ['daily','hourly','monthly']) {
   const fixedRow=await begin({category,type});const output={gross:fixedRow.gross_pay,deductions:fixedRow.deductions,net:fixedRow.net_pay,detail:fixedRow.detail};await db.exec('rollback');
   await db.exec('begin');await db.exec(oldDefinition);const baseline=(await db.query(`select pg_get_functiondef(${oid}) definition`)).rows[0].definition;await db.exec('commit');
   const oldRow=await begin({category,type});assert.deepEqual({gross:oldRow.gross_pay,deductions:oldRow.deductions,net:oldRow.net_pay,detail:oldRow.detail},output,category+'/'+type);await db.exec('rollback');
   assert.equal(baseline,oldDefinition);await db.exec(read(candidate));
 }
 console.log('PASS 12 unchanged explicit-category daily/hourly/monthly cases');
 const tradeFixed=await begin({category:null,trade:true});assert.equal(tradeFixed.gross_pay,64000);await db.exec('rollback');
 await db.exec(oldDefinition);const tradeOld=await begin({category:null,trade:true});assert.equal(tradeOld.gross_pay,tradeFixed.gross_pay);await db.exec('rollback');await db.exec(read(candidate));
 console.log('PASS existing trade-company calculation source unchanged');
 for(const state of ['finalized','manual']) {
  await begin({category:null});
  await db.exec(`update public.payroll_statements set workflow_state='${state==='manual'?'draft':'finalized'}',automatic_calculation=${state!=='manual'} where company_id='${cid}' and worker_id='${wid}' and period_start='2026-09-01'`);
  const frozen=await row();await refresh();assert.deepEqual(await row(),frozen,state+' statement changed');await db.exec('rollback');
 }
 console.log('PASS finalized/manual statements preserved; candidate writes only function definition');
} finally {await db.close();}
