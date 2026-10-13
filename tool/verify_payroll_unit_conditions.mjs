// Disposable PGlite only. No production connection or credentials.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();const read=p=>fs.readFileSync(p,'utf8');
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001';
const owner='00000000-0000-0000-0000-000000000001',editor='00000000-0000-0000-0000-000000000002',viewer='00000000-0000-0000-0000-000000000003',outsider='00000000-0000-0000-0000-000000000004';
const month='2026-09-01';
const actor=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
const save=async(version,items,m=month)=>(await db.query('select public.save_payroll_unit_conditions($1,$2,$3,$4,$5::jsonb) result',[cid,wid,m,version,JSON.stringify(items)])).rows[0].result;
const state=async(m=month)=>(await db.query('select public.payroll_unit_conditions($1,$2,$3) result',[cid,wid,m])).rows[0].result;
const statement=async()=>{await db.exec('reset role');return (await db.query('select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start=$3',[cid,wid,month])).rows[0];};
const item=(section,unit,name,rate_yen,extra={})=>({section,unit,name,rate_yen,...extra});
try {
 await setupPayrollScopeFixture(db);
 for(const path of ['supabase/migrations/20261009171504_payroll_refresh_scope_order.sql','supabase/migrations/20261009151946_company_payroll_rate_registry.sql','supabase/migrations/20261010030208_connect_payroll_tax_calculation.sql','supabase/migrations/20261013175452_payroll_unit_conditions.sql']) await db.exec(read(path));
 await db.exec(`delete from public.attendance_entries;delete from public.payroll_statements;delete from public.payroll_adjustments;
 update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=300000,custom_earnings='[{"name":"Old direct","amount_yen":100}]',custom_deductions='[{"name":"Old deduction","amount_yen":50}]',income_tax_monthly=0,social_insurance_monthly=0,resident_tax_monthly=0 where worker_id='${wid}';`);
 await actor(editor);
 const conditions=[item('earning','hour','Hourly',100,{source:'manual_hours',quantity:'2.5000'}),item('deduction','hour','Hourly removal',50,{source:'manual_hours',quantity:'1.5'}),item('earning','day','Daily',300),item('deduction','day','Daily removal',100),item('earning','month','Monthly',1000),item('deduction','month','Monthly removal',200)];
 const saved=await save(0,conditions);assert.equal(saved.version,1);assert.equal(saved.items.length,6);
 assert.equal(saved.items[0].quantity,2.5);assert.ok(saved.items.every(x=>/^[0-9a-f-]{36}$/.test(x.id)));
 const initial=await statement();assert.equal(initial.gross_pay,301350);assert.equal(initial.deductions,325);assert.equal(initial.net_pay,301025);
 assert.equal(initial.detail.unit_resolution.items[0].amount_yen,250);
 const before=initial.revision;await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,month]);assert.equal((await statement()).revision,before);
 await actor(editor);assert.deepEqual((await state()).items,saved.items);
 await assert.rejects(save(0,saved.items),/version conflict/);
 for(const id of [viewer,outsider,'']){await actor(id);await assert.rejects(save(1,saved.items),/access denied/);}
 await actor(viewer);assert.equal((await state()).can_edit,false);
 await assert.rejects(db.query('select * from payroll_unit_private.conditions'),/permission denied/);
 await assert.rejects(db.query('select payroll_unit_private.resolve($1,$2,$3,$4)',[cid,wid,month,'2026-09-30']),/permission denied/);
 await actor(editor);await assert.rejects(save(1,[item('earning','hour','Missing',100,{source:'manual_hours'})]),/explicit monthly hours/);
 await assert.rejects(save(1,[item('earning','hour','Fake source',100,{source:'base_man_days'})]),/explicit hours source/);
 await assert.rejects(save(1,[item(null,'month','Missing section',100)]),/invalid payroll unit item/);
 await assert.rejects(save(1,[{...saved.items[0],id:'50000000-0000-0000-0000-000000000099'}]),/identity/);
 await db.exec('reset role');
 // Same-date multiple records count as one actual day, never two man-days.
 await db.query(`insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
 values(gen_random_uuid(),$1,$2,'20000000-0000-0000-0000-000000000001','2026-09-02','day',0.5,2,0),
 (gen_random_uuid(),$1,$2,'20000000-0000-0000-0000-000000000001','2026-09-02','day',0.5,1,0)`,[cid,wid]);
 const worked=await statement();assert.equal(worked.detail.unit_resolution.items[2].quantity,1);assert.equal(worked.detail.unit_resolution.items[3].quantity,1);
 await actor(editor);const changed=await save(1,saved.items.map(x=>x.id===saved.items[0].id?{...x,source:'overtime_hours',quantity:null}:x));
 assert.equal(changed.resolved.items[0].quantity,3);
 const earned=await statement();assert.equal(earned.detail.unit_resolution.items[0].amount_yen,300);
 // Future month retains a missing explicit quantity as null and blocks finalization.
 await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,'2026-10-01']);
 const future=(await db.query("select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[cid,wid])).rows[0];
 assert.equal(future.calculation_blocked,true);assert.equal(future.detail.unit_resolution.items[1].quantity,null);assert.equal(future.detail.unit_resolution.items[1].amount_yen,null);
 // Finalize through the genuine existing review/immutable snapshot contract.
 await db.query('insert into public.payroll_confirmers(company_id,user_id,position) values($1,$2,1)',[cid,owner]);
 await db.query('insert into public.payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[earned.id,owner,earned.revision]);
 await actor(owner);
 const finalized=(await db.query('select public.finalize_payroll_statement($1,$2,true) result',[earned.id,earned.revision])).rows[0].result;
 assert.equal(finalized.finalized,true);assert.equal(finalized.snapshot.detail.unit_resolution.items[0].amount_yen,300);
 const frozen=await statement();
 await actor(editor);await assert.rejects(save(2,changed.items),/finalized\/manual/);assert.deepEqual(await statement(),frozen);
 console.log('PASS unit settings 6 bases, save/reload, quantity identity, direct amounts, taxes, stale version, reviewer scope, day dedup, source hours, missing future quantity, frozen manual payroll');
} finally {await db.close();}
