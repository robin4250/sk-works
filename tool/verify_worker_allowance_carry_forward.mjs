// Extends the reviewed source-bound fixture; no production endpoint or data.
import {readFile, mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
let source = await readFile('tool/verify_company_checkout_integration.mjs', 'utf8');
if (createHash('sha256').update(source).digest('hex') !== 'a9588f8af73dee8c89cfcd81d7ba72e3f0f8d6208b736429f90b83da9449a73a') throw Error('Reviewed fixture changed');
const anchor = " phase='source-and-settings-preservation';";
if (source.split(anchor).length !== 2) throw Error('Carry-forward anchor changed');
source = source.replace(anchor, () => `
 phase='worker-setting-continuation-across-months';
 const carryWorker=id(8010);
 await client.query("insert into workers(id,company_id,name) values($1,$2,'継続手当社員')",[carryWorker,A]);
 // Registered once only. Attendance, rather than a monthly settings copy,
 // selects this name for the actual payable days in each month.
 await client.query("insert into worker_payroll_settings(company_id,worker_id,allowance_name_1,allowance_1) values($1,$2,'継続PC',1500)",[A,carryWorker]);
 for(const date of ['2020-08-10','2020-09-10','2020-09-11']){
  await client.query("insert into attendance_entries(company_id,worker_id,site_id,work_date,base_man_days,allowance_names) values($1,$2,$3,$4,1,array['継続PC'])",[A,carryWorker,SITE,date]);
 }
 const carryStatement=month=>q('select to_jsonb(p) v from payroll_statements p where company_id=$1 and worker_id=$2 and period_start=$3',[A,carryWorker,month]);
 const august=await carryStatement('2020-08-01'),september=await carryStatement('2020-09-01');
 eq(august.gross_pay,11500,'One registration: first month one selected allowance day');
 eq(september.gross_pay,23000,'No re-registration: following month two actual selected allowance days');
 eq(august.deductions,0,'First month neutral synthetic tax deductions unchanged');
 eq(september.net_pay,23000,'Following month allowance reaches net payroll');
 eq(await q('select count(*)::int v from worker_payroll_settings where company_id=$1 and worker_id=$2',[A,carryWorker]),1,'One worker setting serves both months');
 eq(await q('select allowance_1 v from worker_payroll_settings where company_id=$1 and worker_id=$2',[A,carryWorker]),1500,'Saved rate never duplicated or changed');
 await client.query("update payroll_statements set workflow_state='approved' where company_id=$1 and worker_id=$2 and period_start='2020-08-01'",[A,carryWorker]);
 const frozenCarry=await carryStatement('2020-08-01');
 await client.query("select private.refresh_automatic_payroll($1,$2,'2020-08-01')",[A,carryWorker]);
 eq(await carryStatement('2020-08-01'),frozenCarry,'Existing finalized first month remains immutable');
 // Only the synthetic extra worker setting is removed before the original
 // fixture's all-settings-preserved assertion; no application table is queried.
 await client.query('delete from worker_payroll_settings where company_id=$1 and worker_id=$2',[A,carryWorker]);
` + anchor);
source=source.replace('source_bound_report_signature_and_payroll:true,','source_bound_report_signature_and_payroll:true,worker_allowance_carries_without_monthly_registration:true,');
if(process.argv.includes('--check-generated')){new (Object.getPrototypeOf(async function() {}).constructor)(source.replace(/^import .*;$/gm,'')); console.log('CARRY_FORWARD_GENERATED_OK');}
else{
 const dir=await mkdtemp(join(tmpdir(),'allowance-carry-forward-'));
 try{const entry=join(dir,'proof.mjs');await writeFile(entry,source);const result=await promisify(execFile)(process.execPath,[entry,process.argv[2]],{maxBuffer:2*1024*1024});process.stdout.write(result.stdout);process.stderr.write(result.stderr);}
 finally{await rm(dir,{recursive:true,force:true});}
}
