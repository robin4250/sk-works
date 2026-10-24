// Diagnostic only, extending the immutable source-bound 118-check fixture.
// Loads exact observed approval source; surrounding request/notification tables
// and actor/session are explicitly synthetic. Never accepts production endpoints.
import {readFile,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
let source=await readFile('tool/verify_company_checkout_integration.mjs','utf8');
if(createHash('sha256').update(source).digest('hex')!=='a9588f8af73dee8c89cfcd81d7ba72e3f0f8d6208b736429f90b83da9449a73a')throw Error('Reviewed 118-check fixture changed');
const once=(text,a,b)=>{if(text.split(a).length!==2)throw Error('Diagnostic anchor changed');return text.replace(a,b);};
source=once(source," phase='source-bound-review-unit';",` phase='exact-attendance-approval-source';
 await exec(\`create table public.attendance_correction_requests(id uuid primary key,company_id uuid,status text,requested_by uuid,request_kind text,reviewed_by uuid,reviewed_at timestamptz,review_note text,updated_at timestamptz default now());
 create table public.attendance_correction_items(id uuid primary key,request_id uuid,company_id uuid,attendance_entry_id uuid,proposed_snapshot jsonb,created_at timestamptz default now());
 create table public.company_approval_assignees(company_id uuid,user_id uuid);
 alter table public.sites add column name text;
 alter table public.paid_leave_requests add column reviewed_by uuid,add column reviewed_at timestamptz,add column review_note text,add column updated_at timestamptz;
 create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns void language plpgsql as $$begin return;end$$;\`);
 const correctionSource=JSON.parse(await readFile('tool/fixtures/checkout_attendance_correction_source.json','utf8'));
 eq(md5(dbBody(correctionSource.definition)),correctionSource.source_md5,'Observed approval source exact');
 eq(correctionSource.source_md5,'87b46c1df058ad8b455bcd843cf7f851','Pinned actual production approval body');
 await exec(correctionSource.definition);
 phase='source-bound-review-unit';`);
source=once(source," const settingsBefore=await q(",` const CORRECTION_WORKER=id(27);
 await client.query("insert into workers(id,company_id,name) values($1,$2,'勤怠修正診断専用社員')",[CORRECTION_WORKER,A]);
 await client.query('insert into worker_payroll_settings(company_id,worker_id) values($1,$2)',[A,CORRECTION_WORKER]);
 const settingsBefore=await q(`);
source=once(source," phase='source-and-settings-preservation';",` phase='diagnostic-approved-allowance-removal';
 const correctionReport=await draft('2020-10-12',CORRECTION_WORKER,[days[0]]);await sign(correctionReport);
 const correctionSalaryBefore=await statement(CORRECTION_WORKER);
 eq(correctionSalaryBefore.gross_pay,10100,'Diagnostic starts with company day100 and ordinary wage10000');
 const correctionEntry=await q('select to_jsonb(a) v from attendance_entries a where a.source_report_id=$1 and a.worker_id=$2',[correctionReport,CORRECTION_WORKER]);
 const correctionChoicesBefore=await q('select company_allowance_selections v from daily_report_workers where report_id=$1 and worker_id=$2',[correctionReport,CORRECTION_WORKER]);
 const correctionReceiptBefore=await q('select snapshot v from company_checkout_allowance_private.receipts where id=$1',[correctionEntry.company_allowance_receipt_id]);
 await client.query("update public.sites set name='診断対象現場' where id=$1",[SITE]);
 await client.query('insert into company_approval_assignees(company_id,user_id) values($1,$2)',[A,U]);
 await client.query("insert into attendance_correction_requests(id,company_id,status,requested_by,request_kind) values($1,$2,'submitted',$3,'correction')",[id(900),A,U]);
 await client.query('insert into attendance_correction_items(id,request_id,company_id,attendance_entry_id,proposed_snapshot) values($1,$2,$3,$4,$5::jsonb)',[id(901),id(900),A,correctionEntry.id,JSON.stringify({siteName:'診断対象現場',allowanceNames:[]})]);
 eq(await q("select public.decide_attendance_correction_request($1,'approve',null) v",[id(900)]),'approved','Actual authorized approval function succeeds');
 const correctionAfter=await q('select to_jsonb(a) v from attendance_entries a where id=$1',[correctionEntry.id]);
 const correctionSalaryAfter=await statement(CORRECTION_WORKER);
 eq(correctionAfter.allowance_names,[],'Approved correction removed attendance selected names');
 eq(await q('select allowance_label v from daily_report_workers where report_id=$1 and worker_id=$2',[correctionReport,CORRECTION_WORKER]),'','Approved correction removed report visible label');
 eq(correctionAfter.company_allowance_receipt_id,correctionEntry.company_allowance_receipt_id,'DIAGNOSTIC: old receipt pointer remains');
 eq(await q('select company_allowance_selections v from daily_report_workers where report_id=$1 and worker_id=$2',[correctionReport,CORRECTION_WORKER]),correctionChoicesBefore,'DIAGNOSTIC: old typed selection remains');
 eq(await q('select snapshot v from company_checkout_allowance_private.receipts where id=$1',[correctionEntry.company_allowance_receipt_id]),correctionReceiptBefore,'Original immutable receipt history remains unchanged');
 eq(correctionSalaryAfter.gross_pay,10100,'DIAGNOSTIC: removed company item100 still paid through receipt');
 eq(correctionSalaryAfter.detail.custom_earnings_total,100,'DIAGNOSTIC: captured company amount survives approved removal');
 console.log(JSON.stringify({diagnostic:'approved_attendance_correction_stale_company_receipt',reproduced:true,
  approved:true,visible_allowance_names_empty:true,typed_selection_and_receipt_pointer_retained:true,
  observed_gross:correctionSalaryAfter.gross_pay,expected_after_removal_gross:10000,unremoved_company_allowance:100,
  correction_source_md5:correctionSource.source_md5,fix_implemented:false,production_changed:false}));
 phase='source-and-settings-preservation';`);
const dir=await mkdtemp(join(tmpdir(),'sko-checkout-correction-diagnostic-'));
try{const file=join(dir,'diagnostic.mjs');await writeFile(file,source);if(process.argv[2]==='--check-generated'){await promisify(execFile)(process.execPath,['--check',file]);process.stdout.write('Generated diagnostic syntax PASS\n');}else{const r=await promisify(execFile)(process.execPath,[file,process.argv[2]],{env:process.env,maxBuffer:1024*1024});process.stdout.write(r.stdout);process.stderr.write(r.stderr);}}
catch(error){process.stdout.write(error.stdout??'');process.stderr.write(error.stderr??'');process.exitCode=1;}
finally{await rm(dir,{recursive:true,force:true});}
