// Disposable SQL regression: real calculator and all monetary normalization triggers.
// node tool/verify_payroll_calculation_invariants.mjs /path/to/pglite/dist/index.js
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const cid='10000000-0000-0000-0000-000000000001';
const wid='40000000-0000-0000-0000-000000000001';
const reviewer='00000000-0000-0000-0000-000000000002';
let failures=0;
function check(condition,label,actual) {
 if(condition) console.log(`PASS ${label}`);
 else {failures++;console.error(`FAIL ${label}: ${JSON.stringify(actual)}`);}
}
const db=new PGlite();
try {
 await db.exec(read('supabase/tests/invoice_stamp_approval_workflow.sql'));
 await db.exec(read('supabase/tests/payroll_private_bank_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/payroll_pay_type_metadata_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/payroll_calculation_invariant_fixture.sql'));
 await db.exec(read('supabase/migrations/20261006162510_payroll_flexible_earnings_deductions_payment_day.sql'));
 await db.exec(read('supabase/migrations/20261007021000_worker_monthly_salary_mode.sql'));
 await db.exec(read('supabase/migrations/20261008001025_payroll_statement_pay_type_metadata.sql'));
 await db.exec(read('supabase/migrations/20261008035104_stabilize_automatic_payroll_totals.sql'));
 const refresh=()=>db.exec(`select private.refresh_automatic_payroll('${cid}','${wid}','2026-08-03');`);
 const row=async()=> (await db.query(`select gross_pay,deductions,net_pay,revision,updated_at,approved_ids,calculation_fingerprint,detail->>'支払日' as payment_day from public.payroll_statements where company_id='${cid}' and worker_id='${wid}' and period_start='2026-08-01'`)).rows[0];
 for(const scenario of [
  {name:'daily',payType:'daily',base:10000,ot:1563,monthly:0,custom:0,expected:13126},
  {name:'hourly',payType:'hourly',base:12000,ot:1875,monthly:0,custom:0,expected:15750},
  {name:'monthly',payType:'monthly',base:10000,ot:2000,monthly:300000,custom:0,expected:304000},
  {name:'monthly named earning',payType:'monthly',base:10000,ot:2000,monthly:300000,custom:5000,expected:309000},
  {name:'hourly named earning',payType:'hourly',base:12000,ot:1875,monthly:0,custom:5000,expected:20750},
 ]) {
  await db.exec(`delete from public.payroll_statements where period_start='2026-08-01'; delete from public.attendance_entries;
  update public.worker_payroll_settings set pay_type='${scenario.payType}',day_daily=${scenario.base},day_overtime=${scenario.ot},monthly_salary_yen=${scenario.monthly},custom_earnings='[{"name":"役職手当","amount_yen":${scenario.custom}}]',custom_deductions='[]' where worker_id='${wid}';
  insert into public.attendance_entries(company_id,worker_id,site_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
  values('${cid}','${wid}','70000000-0000-0000-0000-000000000001','2026-08-03','day',1,2,0);`);
  await refresh(); const first=await row();
  check(first.gross_pay===scenario.expected,`${scenario.name} independent initial amount`,first);
  await db.exec(`update public.payroll_statements set approved_ids=array['${reviewer}'::uuid] where period_start='2026-08-01';`);
  const before=await row(); const auditsBefore=(await db.query('select count(*)::int n from public.payroll_audit')).rows[0].n;
  await refresh(); const unchanged=await row();
  check(unchanged.gross_pay===scenario.expected,`${scenario.name} unchanged refresh keeps amount`,unchanged);
  check(unchanged.revision===before.revision,`${scenario.name} unchanged refresh keeps revision`,{before,unchanged});
  check(JSON.stringify(unchanged.approved_ids)===JSON.stringify(before.approved_ids),`${scenario.name} unchanged refresh keeps confirmation`,unchanged);
  check(String(unchanged.updated_at)===String(before.updated_at),`${scenario.name} unchanged refresh keeps update timestamp`,{before,unchanged});
  check((await db.query('select count(*)::int n from public.payroll_audit')).rows[0].n===auditsBefore,`${scenario.name} unchanged refresh adds no audit`,unchanged);
  await db.exec(`update public.attendance_entries set overtime_hours=3;`);
  await refresh(); const changed=await row();
  check(changed.gross_pay===scenario.expected+scenario.ot,`${scenario.name} changed attendance updates amount`,changed);
  check(changed.revision===unchanged.revision+1,`${scenario.name} changed attendance advances revision once`,changed);
  check(changed.approved_ids.length===0,`${scenario.name} changed attendance invalidates confirmation`,changed);
  // The existing attendance-detail hook performs detail-only writes. Named earnings
  // must survive this path without addition or subtraction being applied twice.
  await db.exec(`update public.payroll_statements set detail=detail||'{"出勤日数":1}'::jsonb where period_start='2026-08-01';`);
  const detailEdited=await row();
  check(detailEdited.gross_pay===changed.gross_pay,`${scenario.name} detail-only enrichment preserves amount`,detailEdited);
  const beforeSettings=await row();
  await db.exec(`update public.worker_payroll_settings set custom_earnings='[{"name":"役職手当","amount_yen":7000}]',custom_deductions='[{"name":"道具代","amount_yen":1100}]' where worker_id='${wid}';`);
  await refresh(); const settingsChanged=await row();
  const expectedAfterSettings=scenario.expected+scenario.ot-scenario.custom+7000;
  check(settingsChanged.gross_pay===expectedAfterSettings,`${scenario.name} changed named earning applied once`,settingsChanged);
  check(settingsChanged.deductions===1100 && settingsChanged.net_pay===expectedAfterSettings-1100,`${scenario.name} changed named deduction applied once`,settingsChanged);
  check(settingsChanged.revision===beforeSettings.revision+1,`${scenario.name} settings change advances revision once`,settingsChanged);
  await refresh(); const repeatSettings=await row();
  check(repeatSettings.gross_pay===settingsChanged.gross_pay && repeatSettings.revision===settingsChanged.revision,`${scenario.name} repeated settings refresh is stable`,repeatSettings);
  await db.exec(`update public.companies set payroll_payment_day=28 where id='${cid}'; update public.worker_payroll_settings set payment_day=25 where worker_id='${wid}';`);
  await refresh(); const companyPolicy=await row();
  check(companyPolicy.payment_day==='28',`${scenario.name} company payment day overrides old worker day`,companyPolicy);
  await db.exec(`update public.worker_payroll_settings set payment_day=27 where worker_id='${wid}';`);
  await refresh(); const legacyPolicy=await row();
  check(legacyPolicy.payment_day==='28' && legacyPolicy.revision===companyPolicy.revision,`${scenario.name} legacy worker day change is ignored`,legacyPolicy);

  await db.exec(`update public.payroll_statements set workflow_state='finalized' where period_start='2026-08-01'; update public.attendance_entries set overtime_hours=4;`);
  const frozen=await row(); await refresh(); const afterFrozen=await row();
  check(JSON.stringify(afterFrozen)===JSON.stringify(frozen),`${scenario.name} finalized statement is immutable to refresh`,afterFrozen);

 }
} finally {await db.close();}
if(failures) {console.error(`${failures} payroll calculation invariant failures`);process.exitCode=1;}
