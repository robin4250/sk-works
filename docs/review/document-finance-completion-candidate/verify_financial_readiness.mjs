// New focused PG17 READINESS proof. Reuses installers, not prior broad suites.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const here=fileURLToPath(new URL('.',import.meta.url)),doc=resolve(here,'../supervisor-document-candidate');
const folder=await mkdtemp(join(tmpdir(),'document-finance-readiness-'));
try{
 const bootstrap=join(folder,'document-bootstrap.mjs');
 const emitted=spawnSync(process.execPath,[resolve(doc,'verify_document_signatures.mjs')],{stdio:'inherit',env:{...process.env,SKO_DOCUMENT_EMIT_ONLY:bootstrap}});
 assert.equal(emitted.status,0);
 const original=await readFile(bootstrap,'utf8'),marker=" eq(await q('select count(*)::int v from shared_daily_report_private.document_rollout'),0,";
 assert.equal(original.split(marker).length,2);
 const setup=original.slice(0,original.indexOf(marker)),tail=original.slice(original.indexOf('}catch(error){'));
 const unit=String.raw`
 phase='document-finance-readiness-source-install';
 const snapshot=()=>q("select jsonb_build_object('reports',(select jsonb_agg(to_jsonb(r) order by id) from daily_reports r),'workers',(select jsonb_agg(to_jsonb(w) order by report_id,worker_id) from daily_report_workers w),'events',(select jsonb_agg(to_jsonb(e) order by id) from shared_daily_report_private.signature_events e),'confirmations',(select jsonb_agg(to_jsonb(c) order by id) from checkout_shared_hours_private.confirmations c),'ledger',(select jsonb_agg(to_jsonb(l) order by id) from checkout_shared_hours_private.ledger l),'entries',(select jsonb_agg(to_jsonb(a) order by id) from attendance_entries a),'payroll',(select jsonb_agg(to_jsonb(s) order by worker_id,period_start) from payroll_statements s)) v");
 const readinessInstallBefore=await snapshot();
 await exec(await readFile(process.env.SKO_FINANCE_READINESS_CANDIDATE,'utf8'));
 eq(await snapshot(),readinessInstallBefore,'Installation changes no report, signature, confirmation, ledger, attendance or salary row');
 eq(await q('select count(*)::int v from document_finance_readiness_private.rollout'),0,'No company/report enabled during install');
 await exec("select set_config('fixture.manager','on',false)");
 let status=await sharedCall(U,id(80),'select public.read_shared_report_financial_readiness($1) v',[rid]);
 eq(status.enabled,false,'Explicit default OFF');
 eq(status.can_finalize,false,'Default OFF cannot imply finance completion');
 // Reproduce the actual unsupported source shape BEFORE freezing real synthetic signatures.
 await client.query("update worker_payroll_settings set pay_type='monthly' where company_id=$1 and worker_id=$2",[A,reportWorker]);
 await client.query('update daily_report_workers set work_category=null where report_id=$1 and worker_id=$2',[rid,reportWorker]);
 await client.query("insert into shared_daily_report_private.document_rollout values($1,$2,'2026-10-01',true)",[A,rid]);
 await client.query('insert into document_finance_readiness_private.rollout values($1,$2,true)',[A,rid]);
 let context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,'representative','実報告者',signature,context.report_updated_at,context.signature_scope_fingerprint]);
 context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[rid]);
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[rid,'supervisor','実責任者',signature,context.report_updated_at,context.signature_scope_fingerprint]);
 const beforeRead=await snapshot();
 status=await sharedCall(U,id(80),'select public.read_shared_report_financial_readiness($1) v',[rid]);
 eq(status.signature_complete,true,'Actual saved document signatures can be complete while finance is not');
 eq(status.financial_complete,false,'Draft document signature is not a salary/invoice completion claim');
 eq(status.validation_ready,false,'NULL category / old daily selection / no confirmation cannot become ready');
 eq(status.can_finalize,false,'Readiness API never writes attendance to make displayed days agree');
 const actualWorker=status.workers.find(w=>w.worker_id===reportWorker);
 eq(actualWorker.reasons.some(r=>r.code==='work_category_required'),true,'Missing category is explicit; never guessed day');
 eq(actualWorker.reasons.some(r=>r.code==='allowance_registration_changed'),true,'Daily choice vs monthly salary is actionable rather than repriced');
 eq(actualWorker.reasons.some(r=>r.code==='worker_confirmation_missing'),true,'Missing actual confirmation is not fabricated');
 eq(status.workers.find(w=>w.worker_id===W2).reasons.some(r=>r.code==='source_unavailable'),true,'Open peer shift remains explicit');
 eq(await snapshot(),beforeRead,'Reading reasons does not change signatures, source rows or financial documents');
 const foreignSid=id(9599);
 await client.query('insert into auth.users(id) values($1)',[OTHER]);await client.query('insert into auth.sessions(id,user_id) values($1,$2)',[foreignSid,OTHER]);
 await reject(()=>sharedCall(OTHER,foreignSid,'select public.read_shared_report_financial_readiness($1) v',[rid]),{code:'42501',message:'shared_report_unavailable'});
 await reject(()=>sharedCall(U,foreignSid,'select public.read_shared_report_financial_readiness($1) v',[rid]),{code:'42501',message:'checkout_report_actor_access_unavailable'});
 // A second real synthetic report tests the exact eligible boundary, still without a finance writer.
 phase='document-finance-exact-valid-boundary';
 const goodDay='2026-10-20';await mkShift(9580,W3,goodDay);
 const goodId=await q('select public.save_daily_report_destination_draft(null,$1,null,$2,$3,$4::jsonb) v',[SITE,goodDay,'確認対象の実作業',JSON.stringify([worker(W3,[],{allowance_label:null})])]);
 await client.query("insert into shared_daily_report_private.document_rollout values($1,$2,'2026-10-01',true)",[A,goodId]);
 await client.query('insert into document_finance_readiness_private.rollout values($1,$2,true)',[A,goodId]);
 context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[goodId]);
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[goodId,'representative','実報告者',signature,context.report_updated_at,context.signature_scope_fingerprint]);
 const input=await sharedCall(U,id(80),'select public.read_shared_worker_facts($1,$2) v',[goodId,W3]);
 assert.ok(input.proposed_worker_facts,'Existing normalizer supplies valid explicit facts');
 await sharedCall(U,id(80),'select public.confirm_managed_shared_worker_facts($1,$2,$3::jsonb,$4::numeric,$5::bigint,$6,$7) v',[goodId,W3,JSON.stringify(Object.fromEntries(Object.entries(input.proposed_worker_facts).filter(([k])=>k!=='company_allowance_legacy_labels'))),null,input.revision,input.scope_fingerprint,'実際の勤務実績を管理者が確認']);
 context=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[goodId]);
 await sharedCall(U,id(80),'select public.manage_shared_report_signature($1,$2,$3,$4::jsonb,$5::timestamptz,$6) v',[goodId,'supervisor','実責任者',signature,context.report_updated_at,context.signature_scope_fingerprint]);
 const goodBefore=await snapshot();
 const good=await sharedCall(U,id(80),'select public.read_shared_report_financial_readiness($1) v',[goodId]);
 eq(good.signature_complete,true,'Eligible source still has actual saved signatures');
 eq(good.validation_ready,true,'Only current confirmation exactly matching signed raw facts qualifies');
 eq(good.can_finalize,false,'No unimplemented write operation is exposed or claimed complete');
 eq(good.completion_supported,false,'Consumer sees that this is diagnosis, not the missing financial writer');
 eq(good.financial_complete,false,'Actual financial status remains false');
 eq(await snapshot(),goodBefore,'Even eligible diagnosis never invokes sign_daily_report or creates a financial row');
 eq(await q("select has_function_privilege('anon','public.read_shared_report_financial_readiness(uuid)','execute') v"),false,'Anonymous caller cannot read readiness');
 eq(await q("select has_schema_privilege('authenticated','document_finance_readiness_private','usage') v"),false,'No client schema grant');
 eq(await q("select relrowsecurity v from pg_class where oid='document_finance_readiness_private.rollout'::regclass"),true,'Private rollout has RLS');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,diagnosis_only:true,financial_writer_implemented:false,old_suites_replayed:false,production_changed:false}));
`;
 const proof=join(folder,'proof.mjs');await writeFile(proof,setup+unit+tail);
 if(process.env.SKO_FINANCE_READINESS_EMIT_ONLY)await writeFile(process.env.SKO_FINANCE_READINESS_EMIT_ONLY,setup+unit+tail);
 else{
  const result=spawnSync(process.execPath,[proof,process.argv[2]],{stdio:'inherit',env:{...process.env,SKO_DOCUMENT_CANDIDATE:resolve(doc,'document-signature-and-edit.sql.review-only'),SKO_DOCUMENT_TRIGGER_PINS:resolve(doc,'trigger-source-pins.json'),SKO_FINANCE_READINESS_CANDIDATE:resolve(here,'financial-readiness.sql.review-only')}});
  if(result.error)throw result.error;process.exitCode=result.status??1;
 }
}finally{await rm(folder,{recursive:true,force:true});}

