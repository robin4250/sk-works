// Extends the already source-bound closed-day proof without editing its source.
// Real clock guards + lock scopes + aggregation body; synthetic membership,
// report signature store, formal-entry projection and payroll refresh spy.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
const run=promisify(execFile);
const original=await readFile('tool/verify_closed_day_paid_hours_scope.mjs','utf8');
const marker=" phase='overlapping-source-evidence-and-same-minute';";
assert.equal(original.split(marker).length,2);
const extension=String.raw`
 phase='explicit-draft-dual-signature-ledger';
 await exec('create schema payroll_scope_private');
 const hourSources=JSON.parse(await readFile('tool/fixtures/checkout_paid_hours_actual_sources.json','utf8'));
 const lockSource=hourSources.functions.find(f=>f.signature==='payroll_scope_private.lock_scopes(jsonb,boolean)');
 eq(createHash('md5').update(body(lockSource.definition)).digest('hex'),lockSource.source_md5,'Actual shared lock exact body');
 await exec(lockSource.definition);
 await exec('create schema company_checkout_allowance_private');
 await exec(hourSources.functions.find(f=>f.signature==='company_checkout_allowance_private.aggregate(jsonb)').definition);
 await exec("alter table public.daily_reports add column representative_signature_json jsonb,\n add column supervisor_signature_json jsonb,add column representative_signer_name text,\n add column supervisor_signer_name text,add column signature_json jsonb,add column signed_at timestamptz,\n add column updated_by uuid,add column updated_at timestamptz;\n create table public.attendance_entries(company_id uuid,worker_id uuid,work_date date,source_report_id uuid);\n create table public.hour_fixture_refresh_spy(kind text,worker_id uuid,work_date date);\n create function private.refresh_automatic_payroll(cid uuid,wid uuid,day date) returns void language sql as $$insert into public.hour_fixture_refresh_spy values('refresh',wid,day)$$;\n create function private.sync_payroll_attendance_detail(cid uuid,wid uuid,day date) returns void language sql as $$insert into public.hour_fixture_refresh_spy values('detail',wid,day)$$;");
 await exec(await readFile('docs/candidates/checkout_paid_hours_ledger.sql.review-only','utf8'));
 const patches=await readFile(process.env.SKO_PAID_HOURS_PATCHES,'utf8');
 const aggregatePatch=patches.slice(patches.indexOf('CREATE OR REPLACE FUNCTION checkout_paid_hours_candidate_private.aggregate_with_hours'),patches.indexOf('CREATE OR REPLACE FUNCTION company_checkout_allowance_private.report_basis'));
 eq(aggregatePatch.length>2000,true,'Only produced exact-source aggregate installed in this private-ledger fixture');
 await exec(aggregatePatch);
 const input=async(hours,revision,hash)=>q('select checkout_paid_hours_candidate_private.save_draft($1,$2,$3,$4,$5) v',[R3,W,hours,revision,hash]);
 const currentScope=await scope(W,R3);
 await reject(()=>input(null,0,currentScope.source_fingerprint),/explicit paid hours/);
 await reject(()=>input('-0.1',0,currentScope.source_fingerprint),/explicit paid hours/);
 await reject(()=>input('24.0001',0,currentScope.source_fingerprint),/explicit paid hours/);
 await reject(()=>input('1.00001',0,currentScope.source_fingerprint),/explicit paid hours/);
 await reject(()=>input('NaN',0,currentScope.source_fingerprint),/explicit paid hours/);
 await reject(()=>input('7.25',0,'0'.repeat(64)),/source changed/);
 const savedHours=await input('7.25',0,currentScope.source_fingerprint);
 eq(savedHours.hours,7.25,'Explicit decimal preserved, not inferred from eight elapsed hours');
 eq(savedHours.revision,1,'First draft revision');
 eq((await input('7.25',1,currentScope.source_fingerprint)).changed,false,'Same hours idempotent');
 await reject(()=>input('8',0,currentScope.source_fingerprint),/revision changed/);
 const hourSign={strokes:[[[1,1],[2,2]]]};
 const hourEnvelope={version:3,representative:hourSign,supervisor:hourSign};
 await client.query('update daily_reports set representative_signature_json=$2 where id=$1',[R3,hourSign]);
 await reject(()=>client.query('select checkout_paid_hours_candidate_private.capture_report($1,$2)',[R3,hourEnvelope]),/both canonical signatures/);
 eq(await q('select count(*)::int v from checkout_paid_hours_candidate_private.ledger'),0,'One signature never creates time ledger');
 await client.query('update daily_reports set supervisor_signature_json=$2 where id=$1',[R3,hourSign]);
 await client.query('select checkout_paid_hours_candidate_private.capture_report($1,$2)',[R3,hourEnvelope]);
 await client.query('select checkout_paid_hours_candidate_private.capture_report($1,$2)',[R3,hourEnvelope]);
 eq(await q('select count(*)::int v from checkout_paid_hours_candidate_private.ledger'),1,'Two signatures capture once without requiring a final hour selection');
 await client.query("update daily_reports set status='signed',signature_json=$2,signed_at=now() where id=$1",[R3,hourEnvelope]);
 eq((await q('select checkout_paid_hours_candidate_private.read_hours($1,$2,$3) v',[A,W,D])).available,false,'Formal attendance missing remains unavailable');
 await client.query('insert into attendance_entries values($1,$2,$3,$4)',[A,W,D,R3]);
 const paidHours=await q('select checkout_paid_hours_candidate_private.read_hours($1,$2,$3) v',[A,W,D]);
 eq(paidHours.available,true,'Matching two signatures and formal entry unlock signed explicit hours');
 eq(paidHours.hours,7.25,'Daily real quantity preserved');
 const originalEvidence=await q('select to_jsonb(a) v from attendance_verifications a where id=$1',[id(100)]);
 const scopePair=await q('select checkout_paid_hours_candidate_private.clock_scopes($1::jsonb) v',[
  JSON.stringify([originalEvidence,{...originalEvidence,worker_id:WR}]),
 ]);
 eq(scopePair.map(s=>s.wid),[W,WR],'UPDATE scope derivation includes old and new workers');
 await reject(()=>client.query('update attendance_verifications set worker_id=$1 where id=$2',[WR,id(100)]),/chronology is immutable/);
 eq((await q('select checkout_paid_hours_candidate_private.read_hours($1,$2,$3) v',[A,W,D])).available,true,'Rejected scope move preserves original signed quantity');
 phase='shared-signature-clock-race';
 const raceClient=new pg.Client({connectionString:url.href,connectionTimeoutMillis:5000});
 await raceClient.connect();
 try{
  await client.query('begin');
  await client.query('select payroll_scope_private.lock_scopes($1::jsonb)',[JSON.stringify([{cid:A,wid:W,day:D}])]);
  await raceClient.query("select set_config('fixture.actor',$1,false)",[U]);
  await raceClient.query("set statement_timeout='150ms'");
  await reject(()=>raceClient.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,daily_report_id) values($1,$2,$3,$4,'clock_in',$5,$6)",[id(902),A,W,SITE2,D+'T19:10:00+09:00',R3]),/statement timeout/);
  await client.query('rollback');
 }finally{await client.query('rollback');await raceClient.end();}
 eq(await q('select count(*)::int v from attendance_verifications where id=$1',[id(902)]),0,'Concurrent new shift cannot bypass signature scope lock');
 phase='immutable-receipt-times-signed-quantity';
 const hourItem={id:id(900),origin:'company_common',name:'合成時間手当',section:'earning',unit:'hour',rate_yen:200};
 const dayItem={id:id(901),origin:'company_common',name:'合成日手当',section:'earning',unit:'day',rate_yen:500};
 const hoursReceipt=[{contract_version:1,work_date:D,items:[hourItem,dayItem]},{contract_version:1,work_date:D,items:[hourItem]}];
 const receiptDigest=createHash('sha256').update(JSON.stringify(hoursReceipt)).digest('hex');
 const calc=await q('select checkout_paid_hours_candidate_private.aggregate_with_hours($1,$2) v',[JSON.stringify(hoursReceipt),{[D]:paidHours}]);
 eq(calc.blocked,false,'Signed quantity supplies hour receipt');
 eq(calc.items.find(i=>i.unit==='hour').quantity,7.25,'Two site receipts use one daily quantity');
 eq(calc.items.find(i=>i.unit==='hour').amount_yen,1450,'Actual200 × signed7.25 =1450');
 eq(calc.items.find(i=>i.unit==='day').amount_yen,500,'Existing day calculation remains once');
 eq(calc.items.find(i=>i.unit==='hour').hours_evidence[0].evidence.ledger_id,paidHours.ledger_id,'Payroll detail carries exact ledger provenance');
 eq(createHash('sha256').update(JSON.stringify(hoursReceipt)).digest('hex'),receiptDigest,'Price receipt immutable');
 const missing=await q('select checkout_paid_hours_candidate_private.aggregate_with_hours($1,$2) v',[JSON.stringify(hoursReceipt),{}]);
 eq(missing.blocked,true,'Missing source is not a zero-hour payment');
 eq(missing.items.find(i=>i.unit==='hour').quantity,null,'Unknown quantity remains null');
 const zero=await q('select checkout_paid_hours_candidate_private.aggregate_with_hours($1,$2) v',[JSON.stringify(hoursReceipt),{[D]:{...paidHours,hours:0}}]);
 eq(zero.blocked,false,'Explicit signed zero is valid');
 eq(zero.items.find(i=>i.unit==='hour').amount_yen,0,'Explicit zero amount is zero');
 const conflict=await q('select checkout_paid_hours_candidate_private.aggregate_with_hours($1,$2) v',[JSON.stringify([...hoursReceipt,{contract_version:1,work_date:D,items:[{...hourItem,rate_yen:201}]}]),{[D]:paidHours}]);
 eq(conflict.blocked,true,'Same-day conflicting immutable prices still block');
 eq(await q("select has_function_privilege('authenticated','checkout_paid_hours_candidate_private.save_draft(uuid,uuid,numeric,bigint,text)','execute') v"),false,'No unreviewed endpoint exposed');
 phase='hours-input-edit-invalidates-signatures';
 await client.query("update daily_reports set status='draft' where id=$1",[R3]);
 const changedHours=await input('6',1,currentScope.source_fingerprint);
 eq(changedHours.revision,2,'Changed input increments revision');
 eq(await q('select representative_signature_json is null and supervisor_signature_json is null v from daily_reports where id=$1',[R3]),true,'Changing hours clears both signatures');
 eq((await q('select checkout_paid_hours_candidate_private.read_hours($1,$2,$3) v',[A,W,D])).available,false,'Old ledger cannot pay edited unsigned input');
 eq(await q('select count(*)::int v from checkout_paid_hours_candidate_private.ledger'),1,'Editing draft never deletes signed history');
`;
// JS replacement callbacks preserve SQL dollar delimiters literally.
const laterChecks=" eq((await q('select checkout_paid_hours_candidate_private.read_hours($1,$2,$3) v',[A,W,D])).available,false,'Later shift evidence invalidates prior signed quantity'); eq(await q('select count(*)::int v from hour_fixture_refresh_spy'),4,'New clock-in and clock-out request payroll and detail invalidation'); ";
const patched=original.replace(marker,()=>extension+String.fromCharCode(10)+marker)
 .replace(" phase='scope-access-and-source-immutability';",()=>laterChecks+" phase='scope-access-and-source-immutability';");
const dir=await mkdtemp(join(tmpdir(),'paid-hours-ledger-proof-'));
try{
 const file=join(dir,'proof.mjs');await writeFile(file,patched);
 const result=await run(process.execPath,[file,process.argv[2]],{env:process.env,maxBuffer:1024*1024});
 process.stdout.write(result.stdout);process.stderr.write(result.stderr);
}catch(e){process.stdout.write(e.stdout??'');process.stderr.write(e.stderr??'');throw e;}
finally{await rm(dir,{recursive:true,force:true});}
