import fs from 'node:fs';import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {captureSql,buildInstall,buildUnusedUndo,classify} from './stage2_plan.mjs';
const root=process.argv[2];const originalPath=process.argv[4],stage1Path=process.argv[5];assert(originalPath&&stage1Path,'Pass the two private source-checkpoint paths explicitly; never run in unconditional CI');const {PGlite}=await import(pathToFileURL(process.argv[3]));
const {setupExpenseCostFixture}=await import(pathToFileURL(root+'/tool/fixtures/expense_cost_fixture.mjs'));
const db=new PGlite();process.chdir(root);
try{
 await setupExpenseCostFixture(db);
 await db.exec("create role service_role;");
 for(const n of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])await db.exec(fs.readFileSync(root+'/supabase/migrations/'+n,'utf8'));
 const original=JSON.parse(fs.readFileSync(originalPath,'utf8'));
 for(const f of original.before.functions)await db.exec(f.definition);
 await db.exec(fs.readFileSync(root+'/docs/candidates/expense_payment_direction_v2_20261019.sql.review-only','utf8'));
 const baseline=fs.readFileSync(root+'/supabase/migrations/20261008035432_certificate_canonical_snapshot_math.sql','utf8');await db.exec(baseline.slice(baseline.indexOf('CREATE OR REPLACE FUNCTION public.payment_certificate_detail_rows')));
 await db.exec('alter table payment_certificates enable row level security;');
 async function capture(){return (await db.exec(captureSql)).find(x=>x.rows?.[0]?.value)?.rows[0].value;}
 const live=JSON.parse(fs.readFileSync(stage1Path,'utf8'));
 for(const f of Object.values(live.checkpoint.functions))await db.exec(f.definition);
 const before=await capture();assert(before);
 const converter=fs.readFileSync(new URL('./source/converter.sql.review-only',import.meta.url),'utf8'),negotiation=fs.readFileSync(new URL('./source/negotiation.sql.review-only',import.meta.url),'utf8');
 await db.exec(buildInstall(before,converter,negotiation));
 const after=await capture();assert.equal(classify(before,after),'installed_off_unused_undo_candidate');
 let refusals=0;for(const mutate of [a=>a.business='0'.repeat(32),a=>a.v2_count=1,a=>a.audit_count=1,a=>a.checkpoint.rights_safe=false,a=>a.checkpoint.functions['private.read_expense_document(text,uuid)'].proc.oid='1',a=>a.checkpoint.audit.columns[0].atttypid='25',a=>a.checkpoint.audit.triggers[0].tgenabled='D',a=>a.checkpoint.policy_expression='true',a=>a.checkpoint.functions['private.expense_direction_v2_client_rollout_verified(uuid)'].proc.prosrc='select true']){const bad=structuredClone(after);mutate(bad);assert.equal(classify(before,bad),'state_requires_review');assert.throws(()=>buildUnusedUndo(before,bad));refusals++;}
 assert.throws(()=>buildInstall(before,converter+' ',negotiation));assert.throws(()=>buildInstall(before,converter,negotiation+' '));
 await assert.rejects(db.exec(buildUnusedUndo(before,{...after,business:after.business}).replace("'"+before.business+"'","'00000000000000000000000000000000'")),/stage2 actual differs/);await db.exec('rollback');
 console.log('PASS stage2 '+refusals+' altered-after refusals, 2 source-pin refusals, live undo CAS refusal');
 await db.exec(buildUnusedUndo(before,after));const restored=await capture();assert.deepEqual(restored,before);
 console.log('PASS stage2 original candidate install / readonly capture / actual OID undo / exact restored checkpoint and financial digest');
}catch(e){console.error(e.code||'error',e.message);process.exitCode=1;}finally{await db.close();}
