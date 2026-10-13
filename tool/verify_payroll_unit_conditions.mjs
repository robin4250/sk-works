// Disposable PGlite / loopback PostgreSQL 17 only. No production connection or credentials.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
let db;let pg;
if(process.argv[3]==='postgres') {
 pg=(await import(process.argv[2])).default;
 const url=new URL(process.env.SKO_UNIT_FIXTURE_URL??'');
 if(!['127.0.0.1','localhost'].includes(url.hostname)||url.pathname!=='/sko_unit_fixture') throw Error('only the disposable loopback unit fixture is allowed');
 pg.types.setTypeParser(20,Number);pg.types.setTypeParser(1700,Number);
 const client=new pg.Client({connectionString:url.href});await client.connect();
 db={query:(...args)=>client.query(...args),exec:sql=>client.query(sql),close:()=>client.end()};
} else {const {PGlite}=await import(process.argv[2]);db=new PGlite();}
const read=p=>fs.readFileSync(p,'utf8');
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
 // One invalid item rolls the entire settings + quantity transaction back.
 await assert.rejects(save(1,[{...saved.items[0],quantity:'99'},item('earning','hour','Invalid later item',100,{source:'manual_hours',quantity:'-1'})]),/explicit monthly hours/);
 assert.equal((await state()).items[0].quantity,2.5);
 assert.equal((await state()).version,1);
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
 // Existing automatic tax conditions use the unit-augmented gross and deductions.
 await actor(editor);
 const profile={insurance_mode:'fixed',health:false,pension:false,employment:false,child_support:false,nursing:false,birth_date:null,health_base_yen:0,pension_base_yen:0,income_mode:'koh',dependents:0,non_taxable_yen:0,employment_excluded_yen:0,additional_social_deduction_yen:0};
 await db.query('select public.save_worker_payroll_tax_conditions($1,$2,$3,0,$4::jsonb,true)',[cid,wid,month,JSON.stringify(profile)]);
 const taxed=await statement();
 const expectedIncome=(await db.query("select payroll_tax_private.monthly_income_tax('2026-10-25',$1,'koh',0) amount",[taxed.gross_pay])).rows[0].amount;
 assert.equal(taxed.detail['所得税'],expectedIncome);assert.equal(taxed.deductions,425+expectedIncome);
 // Future month retains a missing explicit quantity as null and blocks finalization.
 await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,'2026-10-01']);
 const future=(await db.query("select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[cid,wid])).rows[0];
 assert.equal(future.calculation_blocked,true);assert.equal(future.detail.unit_resolution.items[1].quantity,null);assert.equal(future.detail.unit_resolution.items[1].amount_yen,null);
 await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,'2026-10-01']);
 assert.equal((await db.query('select revision from public.payroll_statements where id=$1',[future.id])).rows[0].revision,future.revision,'unchanged missing quantity does not invalidate reviews repeatedly');
 await actor(editor);await save(2,changed.items,'2026-10-01');
 await db.exec('reset role');
 assert.equal((await db.query('select calculation_blocked from public.payroll_statements where id=$1',[future.id])).rows[0].calculation_blocked,false,'explicitly entered month quantity clears unit block');
 // Finalize through the genuine existing review/immutable snapshot contract.
 await db.query('insert into public.payroll_confirmers(company_id,user_id,position) values($1,$2,1)',[cid,owner]);
 await db.query('insert into public.payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[taxed.id,owner,taxed.revision]);
 let finalized;
 if(pg) {
  const first=new pg.Client({connectionString:process.env.SKO_UNIT_FIXTURE_URL}),second=new pg.Client({connectionString:process.env.SKO_UNIT_FIXTURE_URL});
  await first.connect();await second.connect();
  try {
   await first.query('begin');await first.query("select set_config('request.jwt.claim.sub',$1,true)",[owner]);
   await first.query('select 1 from public.workers where company_id=$1 and id=$2 for update',[cid,wid]);
   await second.query("select set_config('request.jwt.claim.sub',$1,false)",[editor]);await second.query('set role authenticated');
   const waiting=second.query('select public.save_payroll_unit_conditions($1,$2,$3,$4,$5::jsonb)',[cid,wid,month,2,JSON.stringify(changed.items)]).then(()=>({ok:true}),error=>({error}));
   let observed=false;
   for(let n=0;n<30;n++) {
    const row=(await db.query('select wait_event_type from pg_stat_activity where pid=$1',[second.processID])).rows[0];
    if(row?.wait_event_type==='Lock'){observed=true;break;}
    await new Promise(resolve=>setTimeout(resolve,50));
   }
   assert.equal(observed,true,'unit writer waits for the existing worker scope before checking immutable payroll');
   finalized=(await first.query('select public.finalize_payroll_statement($1,$2,true) result',[taxed.id,taxed.revision])).rows[0].result;
   await first.query('commit');
   const raced=await waiting;assert.match(raced.error?.message??'',/finalized\/manual/);
  } finally {await first.query('rollback');await first.end();await second.end();}
 } else {
  await actor(owner);
  finalized=(await db.query('select public.finalize_payroll_statement($1,$2,true) result',[taxed.id,taxed.revision])).rows[0].result;
 }
 assert.equal(finalized.finalized,true);assert.equal(finalized.snapshot.detail.unit_resolution.items[0].amount_yen,300);
 const frozen=await statement();
 await actor(editor);assert.equal((await state()).can_edit,false,'frozen payroll is visibly read-only, not a failed editable form');
 await assert.rejects(save(2,changed.items),/finalized\/manual/);assert.deepEqual(await statement(),frozen);
 console.log('PASS unit settings 6 bases, save/reload, quantity identity, direct amounts, taxes, stale version, reviewer scope, day dedup, source hours, missing future quantity, frozen manual payroll');
} finally {await db.close();}
