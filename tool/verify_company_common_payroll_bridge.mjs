import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
let db;
if(process.argv[3]==='postgres') {
 const pg=(await import(process.argv[2])).default;
 const url=new URL(process.env.SKO_COMMON_BRIDGE_FIXTURE_URL??'');
 if(!['127.0.0.1','localhost'].includes(url.hostname)||url.pathname!=='/sko_common_bridge_fixture') throw Error('only disposable loopback common bridge fixture allowed');
 pg.types.setTypeParser(20,Number);pg.types.setTypeParser(1700,Number);
 const client=new pg.Client({connectionString:url.href});await client.connect();
 db={query:(...a)=>client.query(...a),exec:sql=>client.query(sql),close:()=>client.end()};
} else {const {PGlite}=await import(process.argv[2]);db=new PGlite();}
const read=p=>fs.readFileSync(p,'utf8');
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001',owner='00000000-0000-0000-0000-000000000001';
const iid=n=>`70000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const refresh=async()=>db.query("select private.refresh_automatic_payroll($1,$2,'2026-09-01')",[cid,wid]);
const statement=async()=> (await db.query("select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-09-01'",[cid,wid])).rows[0];
try {
 await setupPayrollScopeFixture(db);
 for(const p of ['20261009171504_payroll_refresh_scope_order.sql','20261009151946_company_payroll_rate_registry.sql','20261010030208_connect_payroll_tax_calculation.sql','20261013175452_payroll_unit_conditions.sql']) await db.exec(read('supabase/migrations/'+p));
 await db.exec(`reset role;delete from public.attendance_entries;delete from public.payroll_statements;delete from public.payroll_adjustments;
 update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=300000,
 custom_earnings='[{"name":"Individual retained","amount_yen":100}]',custom_deductions='[]',family_monthly=0,transport_monthly=0,income_tax_monthly=0,social_insurance_monthly=0,resident_tax_monthly=0 where worker_id='${wid}';`);
 await db.exec('create role service_role nologin');
 const storage=read('tool/staged_company_common_allowances.sql.review-only');
 await db.exec(storage.slice(storage.indexOf('create schema company_common_allowance_private;'),storage.indexOf('-- Exactly the old RPC')));
 const metadata=async()=>(await db.query("select oid,proowner,proacl from pg_proc where oid='payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)'::regprocedure")).rows[0];
 const before=await metadata();await db.exec(read('docs/candidates/company_common_payroll_bridge_20261020.sql.review-only'));assert.deepEqual(await metadata(),before);
 await refresh();const baseline=await statement();
 const add=async(n,typ,section,unit,amount)=>db.query(`insert into company_common_allowance_private.items(id,company_id,payroll_type,section,unit,name,amount_yen,position,created_by,updated_by) values($1,$2,$3,$4,$5,$6,$7,$8,$9,$9)`,[iid(n),cid,typ,section,unit,'Common '+n,amount,n,owner]);
 await add(1,'monthly','earning','month',1000);await add(2,'monthly','deduction','month',200);await add(3,'monthly','earning','day',300);await add(4,'monthly','deduction','day',50);await add(5,'daily','earning','month',9000);await add(6,'hourly','earning','month',8000);
 await refresh();assert.deepEqual(await statement(),baseline,'inactive company preserved');
 await db.query("insert into company_common_allowance_private.payroll_activation values($1,'2026-09-01')",[cid]);
 assert.equal((await db.query("select payroll_unit_private.resolve_company_common($1,$2,'2026-08-01','2026-08-31') value",[cid,wid])).rows[0].value.items.length,0);
 await refresh();let row=await statement();assert.equal(row.gross_pay,baseline.gross_pay+1000);assert.equal(row.deductions,baseline.deductions+200);assert.equal(row.detail.unit_resolution.items.length,4);
 await db.query(`insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days,overtime_hours,early_hours) values(gen_random_uuid(),$1,$2,'20000000-0000-0000-0000-000000000001','2026-09-02','day',0.5,0,0),(gen_random_uuid(),$1,$2,'20000000-0000-0000-0000-000000000001','2026-09-02','day',0.5,0,0)`,[cid,wid]);
 row=await statement();assert.equal(row.gross_pay,baseline.gross_pay+1300);assert.equal(row.deductions,baseline.deductions+250);assert.equal(row.detail.unit_resolution.items[2].quantity,1);assert.equal(row.net_pay,row.gross_pay-row.deductions);
 await add(7,'monthly','earning','hour',100);await refresh();row=await statement();assert.equal(row.calculation_blocked,true);assert.equal(row.detail.unit_resolution.items.at(-1).quantity,null);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[owner]);
 const common=async()=>(await db.query("select public.payroll_unit_conditions($1,$2,'2026-09-01') value",[cid,wid])).rows[0].value.company_common;
 const oldSource=(await common()).source;
 const saveHours=async(source,hours)=>(await db.query("select public.save_payroll_common_hours($1,$2,'2026-09-01',$3::jsonb,$4::jsonb) value",[cid,wid,JSON.stringify(source),JSON.stringify(hours)])).rows[0].value;
 await assert.rejects(saveHours(oldSource,[{id:iid(7),quantity:'-1'}]),/explicit company common hours/);
 await assert.rejects(saveHours(oldSource,[{id:iid(6),quantity:'2.5'}]),/identity/);
 await assert.rejects(saveHours(oldSource,[{id:iid(7),quantity:'99999999'}]),/amount exceeds range/);
 assert.deepEqual((await common()).source,oldSource,'overflow rolls back quantity write and payroll together');
 const savedHours=await saveHours(oldSource,[{id:iid(7),quantity:'2.5'}]);
 assert.equal(savedHours.company_common.items.at(-1).quantity,2.5);
 await assert.rejects(saveHours(oldSource,[{id:iid(7),quantity:'3'}]),/source conflict/);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",['00000000-0000-0000-0000-000000000003']);
 await assert.rejects(saveHours((await common()).source,[{id:iid(7),quantity:'3'}]),/access denied/);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[owner]);
 row=await statement();assert.equal(row.calculation_blocked,false);assert.equal(row.gross_pay,baseline.gross_pay+1550);
 await add(8,'monthly','deduction','hour',50);await refresh();assert.equal((await statement()).calculation_blocked,true);
 await saveHours((await common()).source,[{id:iid(8),quantity:'0'}]);
 row=await statement();assert.equal(row.calculation_blocked,false);assert.equal(row.detail.unit_resolution.items.find(x=>x.id===iid(7)).quantity,2.5,'partial hour save preserves other common quantities');
 const revision=row.revision;await refresh();assert.equal((await statement()).revision,revision);
 await db.query("update company_common_allowance_private.items set retired_at=now(),retired_by=$1 where id=$2",[owner,iid(1)]);await refresh();assert.equal((await statement()).gross_pay,baseline.gross_pay+550);

 // The existing tax calculator consumes the augmented gross; no premiums are invented.
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[owner]);
 const profile={insurance_mode:'fixed',health:false,pension:false,employment:false,child_support:false,nursing:false,birth_date:null,health_base_yen:0,pension_base_yen:0,income_mode:'koh',dependents:0,non_taxable_yen:0,employment_excluded_yen:0,additional_social_deduction_yen:0};
 await db.query("select public.save_worker_payroll_tax_conditions($1,$2,'2026-09-01',0,$3::jsonb,true)",[cid,wid,JSON.stringify(profile)]);
 row=await statement();
 const expected=(await db.query("select payroll_tax_private.monthly_income_tax('2026-10-25',$1,'koh',0) value",[row.gross_pay])).rows[0].value;
 assert.equal(row.detail['所得税'],expected);assert.equal(row.deductions,250+expected);
 // Reuse the real finalization contract, then change current common rates.
 await db.query('insert into public.payroll_confirmers(company_id,user_id,position) values($1,$2,1)',[cid,owner]);
 await db.query('insert into public.payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[row.id,owner,row.revision]);
 await db.query('select public.finalize_payroll_statement($1,$2,true)',[row.id,row.revision]);
 const frozen=await statement();
 await db.query('update company_common_allowance_private.items set amount_yen=9999 where id=$1',[iid(3)]);
 await refresh();assert.deepEqual(await statement(),frozen,'finalized payroll and saved detail preserved');
 await assert.rejects(saveHours((await common()).source,[{id:iid(7),quantity:'3'}]),/finalized\/manual/);
 assert.equal((await db.query("select has_function_privilege('authenticated','payroll_unit_private.resolve_company_common(uuid,uuid,date,date)','EXECUTE') value")).rows[0].value,false);
 assert.equal((await db.query("select has_table_privilege('authenticated','company_common_allowance_private.payroll_activation','SELECT') value")).rows[0].value,false);
 console.log('PASS common extras use actual payroll augmentation: units, types, cutoff, manual hours, totals, blocked state, stable identity, retirement and ACL');
} catch(error) {console.error(error.message);process.exitCode=1;} finally {await db.close();}
