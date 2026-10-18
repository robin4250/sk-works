// Synthetic PGlite only. Real helpers/calculator reused; no URL or private input.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();
const read=p=>fs.readFileSync(p,'utf8');
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001',site='20000000-0000-0000-0000-000000000001';
const editor='00000000-0000-0000-0000-000000000002',viewer='00000000-0000-0000-0000-000000000003',outside='00000000-0000-0000-0000-000000000004';
const row=async()=>(await db.query("select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-09-01'",[cid,wid])).rows[0];
const actor=async(uid,role='authenticated')=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);await db.exec(`set role ${role}`);};
let original;let expectedSource;
const call=async(overrides={})=>db.query('select public.recalculate_one_payroll_draft($1,$2,$3,$4,$5,$6,$7) result',[overrides.id??original.id,overrides.revision??original.revision,overrides.company??cid,overrides.worker??wid,overrides.month??'2026-09-01',overrides.confirmed??true,overrides.source??expectedSource]);
const originalSources=async()=>(await db.query(`select jsonb_build_object('attendance',(select jsonb_agg(to_jsonb(a) order by id) from public.attendance_entries a),'settings',(select jsonb_agg(to_jsonb(s) order by worker_id) from public.worker_payroll_settings s),'reviews',(select jsonb_agg(to_jsonb(r)) from public.payroll_statement_reviews r),'documents',(select jsonb_agg(to_jsonb(d)) from payroll_final_private.documents d),'history',(select jsonb_agg(to_jsonb(h)) from payroll_final_private.history h),'adjustments',(select jsonb_agg(to_jsonb(a)) from public.payroll_adjustments a)) data`)).rows[0].data;
async function rejected(uid,overrides,pattern,role='authenticated') {await actor(uid,role);await db.exec('begin');await assert.rejects(call(overrides),pattern);await db.exec('rollback');await db.exec('reset role');assert.deepEqual(await row(),original,'rejected call changed draft');}
try {
 await setupPayrollScopeFixture(db);
 for(const file of ['20261009171504_payroll_refresh_scope_order.sql','20261009151946_company_payroll_rate_registry.sql','20261010030208_connect_payroll_tax_calculation.sql','20261013175452_payroll_unit_conditions.sql','20261014033249_payroll_fixed_deduction_overrides.sql'])await db.exec(read('supabase/migrations/'+file));
 await db.exec(`delete from public.attendance_entries;delete from public.payroll_statements;delete from public.payroll_adjustments;update public.worker_payroll_settings set pay_type='daily',day_daily=20000,day_overtime=2500,day_early=2500,custom_earnings='[]',custom_deductions='[]',family_monthly=0,transport_monthly=0,income_tax_monthly=0,social_insurance_monthly=0,resident_tax_monthly=0,other_deduction_monthly=0 where worker_id='${wid}';`);
 for(const date of ['2026-09-12','2026-09-16'])await db.query('insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days,overtime_hours,early_hours) values(gen_random_uuid(),$1,$2,$3,$4,null,1,2,1)',[cid,wid,site,date]);
 original=await row();assert.equal(original.gross_pay,0,'saved parent regression needed');
 const sources=await originalSources();
 const fix=process.argv[4]??process.argv[3];if(!fix)throw Error('Provide saved reviewed NULL-category migration path; do not inline another calculator');await db.exec(read(fix));
 await db.exec(read('docs/candidates/payroll_single_draft_recalculation_20261019.sql.review-only'));
 expectedSource=(await db.query('select private.payroll_draft_source_fingerprint($1,$2,$3) h',[cid,wid,'2026-09-01'])).rows[0].h;
 await rejected(editor,{source:'0'.repeat(32)},/source changed/);
 await rejected(viewer,{},/access denied/);await rejected(outside,{},/access denied/);await rejected('',{},/access denied/);await rejected(editor,{},/permission denied/,'anon');
 await rejected(editor,{confirmed:false},/explicit exact draft scope/);await rejected(editor,{revision:original.revision+1},/revision or scope changed/);await rejected(editor,{month:'2026-08-01'},/access denied/);await rejected(editor,{company:'90000000-0000-0000-0000-000000000001'},/access denied/);await rejected(editor,{worker:'90000000-0000-0000-0000-000000000002'},/access denied/);
 for(const mode of ['manual','finalized','snapshot']) {
  await db.exec('begin');await db.query('update public.payroll_statements set automatic_calculation=$1,workflow_state=$2,finalized_at=$3 where id=$4',[mode!=='manual',mode==='finalized'?'finalized':'draft',mode==='finalized'?new Date():null,original.id]);
  if(mode==='snapshot')await db.query("insert into payroll_final_private.documents(statement_id,company_id,worker_id,period_start,period_end,revision,value,finalized_by,finalized_at) values($1,$2,$3,'2026-09-01','2026-09-30',$4,'{}',$5,now())",[original.id,cid,wid,original.revision,editor]);
  await actor(editor);await assert.rejects(call(),/only unfinalized automatic draft/);await db.exec('rollback');await db.exec('reset role');assert.deepEqual(await row(),original);
 }
 // Synthetic fault injection changes the digest only at postcondition time.
 const fingerprintDefinition=(await db.query("select pg_get_functiondef('private.payroll_draft_source_fingerprint(uuid,uuid,date)'::regprocedure) d")).rows[0].d;
 await db.exec(`create sequence public.synthetic_source_digest_calls;create or replace function private.payroll_draft_source_fingerprint(cid uuid,wid uuid,month date) returns text language sql volatile security definer set search_path='' as $$select case when nextval('public.synthetic_source_digest_calls')=1 then '${expectedSource}' else repeat('f',32) end$$`);
 await rejected(editor,{},/source changed/);await db.exec(fingerprintDefinition);
 assert.deepEqual(await originalSources(),sources,'source-drift rejection altered original source');
 await actor(editor);const response=(await call()).rows[0].result;await db.exec('reset role');const fixed=await row();
 assert.equal(response.finalized,false);assert.equal(response.workflow_state,'draft');assert.equal(response.changed,true);assert.equal(fixed.gross_pay,55000);assert.equal(fixed.net_pay,55000);assert.equal(fixed.detail['基本給'],40000);assert.equal(fixed.revision,original.revision+1);assert.deepEqual(fixed.approved_ids,[]);assert.deepEqual(await originalSources(),sources,'original attendance/settings/reviews/final snapshots/adjustments changed');
 const audit=(await db.query("select count(*)::int n from public.payroll_audit where statement_id=$1 and revision=$2 and action='automatic_recalculation' and actor_id=$3",[fixed.id,fixed.revision,editor])).rows[0].n;assert.equal(audit,1);
 original=fixed;await actor(editor);const again=(await call()).rows[0].result;assert.equal(again.changed,false);assert.equal(again.revision,fixed.revision);await db.exec('reset role');const repeat=await row();delete repeat.updated_at;const fixedNoTime={...fixed};delete fixedNoTime.updated_at;assert.deepEqual(repeat,fixedNoTime);
 console.log('PASS exact one-draft real calculator+sync, NULL bug corrected, revision/audit/approval invalidation, unchanged source/review/final snapshots, repeat semantic no-op (existing sync may touch updated_at), source digest pre/post drift refusal; viewer/outsider/anonymous/confirmation/revision/scope/manual/finalized/snapshot refusals');
} catch(error){console.error(error.message);console.error(error.stack?.split('\n').filter(x=>x.includes('verify_payroll_single')).join('\n'));process.exitCode=1;}finally{await db.close();}
