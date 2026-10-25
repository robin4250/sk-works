// Extends existing source-bound save/sign/receipt/payroll suite only after all
// original checks. No original writer or guard is weakened in the fixture.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const original=await readFile('tool/verify_company_checkout_integration.mjs','utf8');
const marker=" console.log(JSON.stringify({pass:true,checks,engine:'native PostgreSQL17'";
assert.equal(original.split(marker).length,2,'Exact end of original source-bound suite');
const extension=String.raw`
 phase='signed-hours-original-payroll-source-chain';
 const hourSources=JSON.parse(await readFile('tool/fixtures/checkout_paid_hours_actual_sources.json','utf8'));
 const clockSources=JSON.parse(await readFile('tool/fixtures/closed_day_actual_clock_sources.json','utf8'));
 // Only disposable fixture surroundings not present in original checkout proof.
 await exec("alter table workers add column user_id uuid,add column status text default 'active';create function private.has_company_feature(uuid,text) returns boolean language sql stable as $$select true$$;create table vehicles(id uuid primary key,company_id uuid);create table attendance_verifications(id uuid primary key,company_id uuid,worker_id uuid,site_id uuid,route_assignment_id uuid,vehicle_id uuid,event_type text,confirmed_at timestamptz,source_clock_in_id uuid,work_date date,daily_report_id uuid);create unique index hour_fixture_one_end on attendance_verifications(source_clock_in_id) where source_clock_in_id is not null;create table route_stops(id uuid,route_assignment_id uuid);create table private.route_journey_captures(id uuid,source_clock_in_id uuid);create table private.route_journey_visit_events(capture_id uuid,source_clock_in_id uuid,start_capture_id uuid,kind text,route_stop_id uuid);");
 await client.query('update workers set user_id=$1 where id=$2',[U,W5]);
 const lockRow=hourSources.functions.find(f=>f.signature==='payroll_scope_private.lock_scopes(jsonb,boolean)');
 eq(md5(dbBody(lockRow.definition)),lockRow.source_md5,'Exact live scope lock supplied');
 await exec('drop function payroll_scope_private.lock_scopes(jsonb,boolean)');
 await exec(lockRow.definition);
 const guardRow=clockSources.functions.find(f=>f.signature==='private.validate_attendance_shift_evidence()');
 eq(md5(dbBody(guardRow.definition)),guardRow.source_md5,'Exact live clock source guard');
 await exec(guardRow.definition);
 await exec('create trigger hour_fixture_clock_guard before insert or update on attendance_verifications for each row execute function private.validate_attendance_shift_evidence()');
 for(const row of hourSources.functions.filter(f=>/report_basis|\.aggregate\(|\.resolve\(|^sign_daily_report/.test(f.signature))){
  eq(md5(dbBody(row.definition)),row.source_md5,'Exact live body supplied '+row.signature);
  await exec(row.definition);
 }
 await exec(await readFile('docs/candidates/closed_day_paid_hours_scope.sql.review-only','utf8'));
 await exec(await readFile('docs/candidates/checkout_paid_hours_ledger.sql.review-only','utf8'));
 await exec(await readFile(process.env.SKO_PAID_HOURS_PATCHES,'utf8'));
 await exec("create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz);create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('fixture.hour_claims',true),''),'{}')::jsonb$$;");
 await exec(await readFile('tool/fixtures/checkout_paid_hours_session_helper.sql','utf8'));
 await exec(await readFile('docs/candidates/checkout_paid_hours_api.sql.review-only','utf8'));
 const hoursSession=id(930);
 await client.query('insert into auth.sessions values($1,$2,null)',[hoursSession,U]);
 await client.query('insert into auth.users values($1,false,null)',[U]);
 const claims={role:'authenticated',sub:U,session_id:hoursSession,is_anonymous:false};
 await client.query("select set_config('fixture.hour_claims',$1,false)",[JSON.stringify(claims)]);
 const fullSignatureSource=hourSources.functions.find(f=>f.signature==='private.save_daily_report_signature(uuid,text,text,jsonb)');
 eq(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',[fullSignatureSource.signature]),fullSignatureSource.source_md5,'Actual unmodified representative/supervisor writer');
 const hoursDate='2026-10-10';
 const earlyReport=await draft(hoursDate,W5,[choice('company_common',HOUR,'合成時間手当','hour')]);
 const finalReport=await draft(hoursDate,W5,[],{site:SITE2});
 const hourClockIn=id(920),hourClockOut=id(921),finalClockIn=id(922),finalClockOut=id(923);
 for(const [startId,endId,site,rid,startAt,endAt]of[[hourClockIn,hourClockOut,SITE,earlyReport,'09:00','12:00'],[finalClockIn,finalClockOut,SITE2,finalReport,'13:00','17:00']]){
  await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,daily_report_id) values($1,$2,$3,$4,'clock_in',$5,$6)",[startId,A,W5,site,hoursDate+'T'+startAt+':00+09:00',rid]);
  await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id,daily_report_id) values($1,$2,$3,$4,'clock_out',$5,$6,$7)",[endId,A,W5,site,hoursDate+'T'+endAt+':00+09:00',startId,rid]);
 }
 await sign(earlyReport);
 const hourStatement=()=>q("select to_jsonb(p) v from payroll_statements p where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,W5]);
 eq((await hourStatement()).calculation_blocked,true,'Original early-hour receipt waits for daily signed quantity');
 const hourReceiptBefore=await q('select jsonb_agg(to_jsonb(r) order by id) v from company_checkout_allowance_private.receipts r');
 const scope=await q('select checkout_paid_hours_candidate_private.read_closed_day_scope($1,$2,$3,$4) v',[A,W5,hoursDate,finalReport]);
 eq(scope.blocked,false,'Exact final saved clock source accepted');
 await exec('set role authenticated');
 try{
  const readInput=()=>q('select public.read_checkout_paid_work_hours($1,$2) v',[finalReport,W5]);
  const input=await readInput();
  eq(input.actor_id,U,'Public reader binds live actor');eq(input.required,true,'Earlier site hour selection requests final-day input');
  eq(input.hours,null,'Public input does not assume zero before first save');
  await reject(()=>q('select public.read_checkout_paid_work_hours($1,$2) v',[finalReport,W3]),/access_unavailable/);
  await reject(()=>q('select hours v from checkout_paid_hours_candidate_private.ledger limit 1'),/permission denied/);
  await client.query("select set_config('fixture.hour_claims',$1,false)",[JSON.stringify({...claims,sub:OTHER})]);
  await reject(readInput,/actor_access_unavailable/);
  await client.query("select set_config('fixture.hour_claims',$1,false)",[JSON.stringify({...claims,is_anonymous:true})]);
  await reject(readInput,/actor_access_unavailable/);
  await client.query("select set_config('fixture.hour_claims',$1,false)",[JSON.stringify(claims)]);
  const saved=await q('select public.save_checkout_paid_work_hours($1,$2,7.25,0,$3) v',[finalReport,W5,scope.source_fingerprint]);
  eq(saved.hours,7.25,'Live-session public save/readback preserves explicit hours');
  await reject(()=>q('select public.save_checkout_paid_work_hours($1,$2,8,0,$3) v',[finalReport,W5,scope.source_fingerprint]),/paid_hours_input_conflict/);
 }finally{await exec('reset role');}
 await client.query('delete from auth.sessions where id=$1',[hoursSession]);
 await exec('set role authenticated');
 try{await reject(()=>q('select public.read_checkout_paid_work_hours($1,$2) v',[finalReport,W5]),/actor_access_unavailable/);}
 finally{await exec('reset role');}
 await client.query('insert into auth.sessions values($1,$2,null)',[hoursSession,U]);
 for(const role of ['anon','service_role']){
  await exec('set role '+role);
  try{await reject(()=>q('select public.read_checkout_paid_work_hours($1,$2) v',[finalReport,W5]),/permission denied/);}
  finally{await exec('reset role');}
 }
 const finalBasis=await q('select company_checkout_allowance_private.report_basis($1) v',[finalReport]);
 eq(finalBasis.paid_work_hours[0].hours,7.25,'Time input is in same basis used by report edits');
 await client.query("select public.save_daily_report_signature($1,'representative','時間報告者',$2::jsonb)",[finalReport,signature]);
 eq(await q('select count(*)::int v from checkout_paid_hours_candidate_private.ledger'),0,'Actual first signature does not capture hours');
 await client.query("select public.save_daily_report_signature($1,'supervisor','時間責任者',$2::jsonb)",[finalReport,signature]);
 const after=await hourStatement();
 const hourLine=after.detail.unit_resolution.items.find(i=>i.id===HOUR);
 eq(after.calculation_blocked,false,'Actual second signature -> formal attendance -> payroll resolves waiting quantity');
 eq(hourLine.quantity,7.25,'Actual payroll saved exact signed daily hours');
 eq(hourLine.amount_yen,7250,'Saved company rate1000 × signed7.25 =7250');
 eq(after.detail.custom_earnings_total,7250,'Named earning feeds actual custom earnings total');
 eq(after.gross_pay,27250,'Actual base wages20000 plus signed allowance7250');
 eq(after.net_pay,Math.max(0,after.gross_pay-after.deductions),'Saved net agrees with saved gross/deductions');
 eq(await q('select jsonb_agg(to_jsonb(r) order by id) v from company_checkout_allowance_private.receipts r where id=any($1::uuid[])',[hourReceiptBefore.map(r=>r.id)]),hourReceiptBefore,'Final report without hour selection leaves prior immutable price receipt untouched');
 eq([await statement(W3),await statement(W4)],protectedBefore,'Finalized and manual statement snapshots unchanged');
 eq(await q('select jsonb_agg(to_jsonb(s) order by worker_id) v from worker_payroll_settings s'),settingsBefore,'No individual rates or insurance values rewritten');
 if(process.env.SKO_PAID_HOURS_EXPORT){
  const {writeFile:writeHoursExport}=await import('node:fs/promises');
  await writeHoursExport(process.env.SKO_PAID_HOURS_EXPORT,JSON.stringify({schema:1,synthetic_only:true,
   saved_statement:after,client_rpc_row:{...after,worker_name:'合成社員E',company_name:'合成会社'},
   expected:{hours:7.25,rate:1000,allowance:7250,gross_pay:27250,deductions:after.deductions,net_pay:after.net_pay}}));
 }
 const reopening=id(924);
 await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at) values($1,$2,$3,$4,'clock_in',$5)",[reopening,A,W5,SITE2,hoursDate+'T18:00:00+09:00']);
 eq((await hourStatement()).calculation_blocked,true,'Actual later clock-in re-runs normal payroll and invalidates old signed hours');
 eq(await q('select count(*)::int v from checkout_paid_hours_candidate_private.ledger'),1,'Reentry preserves historical signed ledger');
 console.log(JSON.stringify({pass:true,actual_save_sign_formal_attendance_payroll_hours_chain:true,hour_rate:1000,signed_hours:7.25,allowance:7250,finalized_manual_snapshots_unchanged:true,real_gotrue:false,production_changed:false}));
`;
const temp=await mkdtemp(join(tmpdir(),'paid-hours-actual-chain-'));
try{
 const file=join(temp,'proof.mjs');await writeFile(file,original.replace(marker,()=>extension+marker).replace('hour_source_connected:false','hour_source_connected:true'));
 const result=spawnSync(process.execPath,[file,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally{await rm(temp,{recursive:true,force:true});}
