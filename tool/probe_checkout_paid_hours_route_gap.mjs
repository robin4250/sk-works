// Diagnostic only: a green result proves the route/hour gap, not a fix.
// Exact current guard is retained; no production endpoint/data is accepted.
import {readFile,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
let source=await readFile('tool/verify_company_checkout_integration.mjs','utf8');
if(createHash('sha256').update(source).digest('hex')!=='a9588f8af73dee8c89cfcd81d7ba72e3f0f8d6208b736429f90b83da9449a73a')throw Error('Reviewed source fixture changed');
const once=(text,a,b)=>{if(text.split(a).length!==2)throw Error('Diagnostic anchor changed');return text.replace(a,()=>b);};
source=once(source," phase='immutable-rate-and-name-snapshot';",`
 phase='route-intermediate-final-hour-gap-diagnostic';
 const paidSources=JSON.parse(await readFile('tool/fixtures/checkout_paid_hours_before.json','utf8'));
 const guardRow=paidSources.functions.find(x=>x.signature==='company_checkout_allowance_private.guard_receipt_pointer()');
 eq(guardRow.source_md5,'ac08fbea5766d279f8bf764a0744e089','Retain production name-correction protection');
 eq(md5(dbBody(guardRow.definition)),guardRow.source_md5,'Guard fixture exact');
 await exec(guardRow.definition);
 const ROUTE_HOUR_WORKER=id(8110);
 await client.query("insert into workers(id,company_id,name) values($1,$2,'時間源診断社員')",[ROUTE_HOUR_WORKER,A]);
 await client.query('insert into worker_payroll_settings(company_id,worker_id) values($1,$2)',[A,ROUTE_HOUR_WORKER]);
 const hourChoice=choice('company_common',HOUR,'合成時間手当','hour');
 // Two saved destinations stand for a route's intermediate/final reports.
 // No fictitious clock-out is fabricated: the fixture intentionally cannot
 // prove an actual final-shift link and reports that limitation explicitly.
 // Keep the report's company/site/date identity disjoint from the original
 // partial-signature fixture on 2020-10-22; worker ID alone is not its key.
 const intermediateReport=await draft('2020-10-18',ROUTE_HOUR_WORKER,[hourChoice],{site:SITE});
 await sign(intermediateReport);
 const intermediateReceipt=await q('select snapshot v from company_checkout_allowance_private.receipts where report_id=$1 and worker_id=$2',[intermediateReport,ROUTE_HOUR_WORKER]);
 const finalReport=await draft('2020-10-18',ROUTE_HOUR_WORKER,[hourChoice],{site:SITE2,extra:{paid_work_hours:'7.5'}});
 await sign(finalReport);
 const finalReceipt=await q('select snapshot v from company_checkout_allowance_private.receipts where report_id=$1 and worker_id=$2',[finalReport,ROUTE_HOUR_WORKER]);
 eq(finalReceipt,intermediateReceipt,'Current server does not bind the unsupported final-only input into the captured time basis');
 const hourResolution=await q("select company_checkout_allowance_private.resolve($1,$2,'2020-10-01','2020-10-31') v",[A,ROUTE_HOUR_WORKER]);
 eq(hourResolution.blocked,true,'A final-only unsupported hours payload cannot complete the hourly allowance');
 eq(hourResolution.items[0].quantity,null,'Unknown daily paid-hours remains null, never implicit zero/eight');
 eq(hourResolution.items[0].amount_yen,null,'Unknown hours never fabricates a payable amount');
 eq(hourResolution.reasons.some(x=>x.code==='actual_work_hours_unavailable'),true,'Specific missing-source blocker survives two signed reports');
 eq(await q('select snapshot v from company_checkout_allowance_private.receipts where report_id=$1 and worker_id=$2',[intermediateReport,ROUTE_HOUR_WORKER]),intermediateReceipt,'Later final report never rewrites intermediate immutable receipt');
 eq(await q("select md5(prosrc) v from pg_proc where oid='company_checkout_allowance_private.guard_receipt_pointer()'::regprocedure"),guardRow.source_md5,'Production correction guard retained throughout');
 await client.query('delete from worker_payroll_settings where company_id=$1 and worker_id=$2',[A,ROUTE_HOUR_WORKER]);
 phase='immutable-rate-and-name-snapshot';`);
source=source.replace('source_bound_report_signature_and_payroll:true,','source_bound_report_signature_and_payroll:true,diagnostic_only:true,route_final_hour_source_gap_reproduced:true,actual_final_checkout_link_proven:false,');
if(process.argv.includes('--check-generated')){
 new (Object.getPrototypeOf(async function(){}).constructor)(source.replace(/^import .*;$/gm,''));
 console.log('PAID_HOURS_DIAGNOSTIC_GENERATED_OK');
}else{
 const dir=await mkdtemp(join(tmpdir(),'paid-hours-diagnostic-'));
 try{
  const p=join(dir,'proof.mjs');await writeFile(p,source);
  const result=await promisify(execFile)(process.execPath,[p,process.argv[2]],{maxBuffer:2*1024*1024});
  process.stdout.write(result.stdout);process.stderr.write(result.stderr);
 }finally{await rm(dir,{recursive:true,force:true});}
}
