// Disposable synthetic fixture only. Never accepts production rows or checkpoints.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';
import {captureCodeCheckpoint,buildCodeRestore} from './expense_direction_code_checkpoint.mjs';
import {buildDefaultOffDeployment,defaultOffBusinessHashSql} from './expense_direction_default_off_preparation.mjs';
import {validatePayrollScopeFixtureUrl} from './payroll_scope_pg17_database_guard.mjs';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const candidate=fs.readFileSync('docs/candidates/expense_payment_direction_v2_20261019.sql.review-only','utf8');
try {
 await setupExpenseCostFixture(db);
 for(const file of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 await db.exec(`create role unexpected_expense_grantee;alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;insert into companies(id,tax_rate) values('${id(1)}',10);insert into company_members values('${id(1)}','${id(3)}','owner');insert into workers(id,company_id,name,user_id,partner_company_id) values('${id(2)}','${id(1)}','Synthetic','${id(3)}','${id(5)}');insert into partner_companies values('${id(5)}','${id(1)}','Synthetic');insert into private.expense_approval_settings(company_id,approver_ids,revision) values('${id(1)}',array['${id(3)}']::uuid[],1);set test.uid='${id(3)}';`);
 for(const [n,month] of [[10,'07'],[11,'08']])await db.exec(`insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen) values('${id(n)}','${id(1)}','${id(2)}','Synthetic','${id(3)}','2026-${month}-01','2026-${month}-01','Synthetic',1000);select public.expense_confirm_review('${id(n+100)}','${id(n)}',1,'approve','subcontractor','${id(5)}','cash','');`);
 await db.exec("update payment_certificates set status='finalized' where period_start='2026-08-01';update payment_certificates set deductions=375 where period_start='2026-07-01'");
 const before=await captureCodeCheckpoint(db);
 const expectedBusinessHash=(await db.query(defaultOffBusinessHashSql)).rows[0].value;
 const defaults=async()=>(await db.query("select coalesce(jsonb_agg(to_jsonb(d) order by oid),'[]') value from pg_default_acl d")).rows[0].value;
 const originalDefaults=await defaults();
 const business=async()=>(await db.query(`select jsonb_build_object(
 'payments',(select jsonb_agg(to_jsonb(x) order by id) from public.payment_certificates x),
 'claims',(select jsonb_agg(to_jsonb(x) order by id) from private.expense_claims x),
 'choices',(select jsonb_agg(to_jsonb(x) order by claim_id) from private.expense_settlement_choices x),
 'consumptions',(select jsonb_agg(to_jsonb(x) order by claim_id,purpose) from private.expense_amount_consumptions x),
 'snapshots',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.expense_document_snapshots x)) value`)).rows[0].value;
 const original=await business();assert.equal(original.payments.length,2);assert.equal(original.consumptions.length,1);
 assert.throws(()=>buildDefaultOffDeployment(before,candidate+'\n'),/independently reviewed/);
 assert.throws(()=>buildDefaultOffDeployment(before,candidate),/business checkpoint hash required/);
 const sql=buildDefaultOffDeployment(before,candidate,expectedBusinessHash);
 const ensureOriginal=async()=>{assert.deepEqual(await captureCodeCheckpoint(db),before);assert.deepEqual(await business(),original);assert.deepEqual(await defaults(),originalDefaults);assert.equal((await db.query("select to_regclass('pg_temp.sko_expense_off_before') value")).rows[0].value,null);};
 // The old candidate leaked public-schema default service_role EXECUTE.
 const missingServiceRevoke=sql.replace('from public,anon,service_role;','from public,anon;');
 assert.notEqual(missingServiceRevoke,sql);
 await assert.rejects(db.exec(missingServiceRevoke),/privilege\/config/);await db.exec('ROLLBACK');await ensureOriginal();
 async function rejectInjected(injection,stage,pattern){
  const boundary=stage==='pre'?'DO $sko_preflight$':'DO $sko_postflight$';
  const injected=sql.replace(boundary,()=>injection+';\n'+boundary);assert.notEqual(injected,sql);
  let failure;try{await db.exec(injected);}catch(error){failure=error;}
  await db.exec('ROLLBACK');
  assert(failure&&pattern.test(failure.message),'expected '+pattern+'; got '+failure?.message);await ensureOriginal();
 }
 await rejectInjected("update payment_certificates set snapshot=snapshot||'{\"expense_cost_basis\":{}}'::jsonb where period_start='2026-07-01'",'pre',/existing v2\/basis/);
 await rejectInjected('create table private.expense_payment_direction_conversions(id integer)','pre',/conversion or rollout/);
 await rejectInjected("create function private.expense_direction_v2_client_rollout_verified(uuid) returns boolean language sql as $$select false$$",'pre',/conversion or rollout/);
 await rejectInjected('grant execute on function public.expense_payment_direction_capability(uuid) to anon','post',/privilege\/config/);
 await rejectInjected('grant execute on function private.expense_payment_v2_envelope(uuid,uuid,uuid,date,integer,numeric,jsonb) to unexpected_expense_grantee','post',/privilege\/config/);
 await rejectInjected("alter function private.expense_payment_v2_envelope(uuid,uuid,uuid,date,integer,numeric,jsonb) set search_path=public",'post',/privilege\/config/);
 await rejectInjected("alter function private.read_expense_document(text,uuid) volatile",'post',/existing function metadata/);
 await rejectInjected('alter table public.payment_certificates disable trigger zz_expense_document_snapshot','post',/existing trigger drift/);
 await rejectInjected("create or replace function private.expense_cost_direction_v2_enabled(cid uuid) returns boolean language sql stable security invoker set search_path='' as $$select true$$",'post',/constant OFF/);
 await rejectInjected("update private.expense_claims set description='changed' where id='"+id(10)+"'",'post',/business data changed/);
 await rejectInjected('alter table public.payment_certificates disable trigger expense_direction_v2_guard','post',/new guard trigger/);
 await rejectInjected('alter function private.expense_payment_v2_envelope(uuid,uuid,uuid,date,integer,numeric,jsonb) security definer','post',/privilege\/config/);
 await rejectInjected("create or replace function public.expense_payment_direction_capability(p_company uuid) returns jsonb language sql stable security invoker set search_path='' as $$select '{}'::jsonb$$",'post',/source differs/);
 // Native-only second connection: active business writes must fail immediately.
 if(db.client){
  const pg=await import(process.argv[3]);const Client=pg.Client??pg.default?.Client;
  const peer=new Client({connectionString:validatePayrollScopeFixtureUrl(process.env.SKO_PAYROLL_SCOPE_FIXTURE_URL)});
  await peer.connect();let failure;
  try{await peer.query('BEGIN;LOCK TABLE private.expense_claims IN ROW EXCLUSIVE MODE');
   try{await db.exec(sql);}catch(error){failure=error;}
   await db.exec('ROLLBACK');assert.equal(failure?.code,'55P03','NOWAIT refuses an active writer without deadlock');
  }finally{await peer.query('ROLLBACK');await peer.end();}
  await ensureOriginal();console.log('PASS PG17 second connection: NOWAIT active-writer refusal leaves original code and data');
 }
 await rejectInjected('alter default privileges in schema public grant execute on functions to unexpected_expense_grantee','pre',/privilege\/config/);
 await assert.rejects(db.exec(buildDefaultOffDeployment(before,candidate,'0'.repeat(32))),/business checkpoint drift/);await db.exec('ROLLBACK');await ensureOriginal();
 await db.exec(sql);const after=await captureCodeCheckpoint(db);
 assert.equal(after.functions.length,8);assert.equal(after.triggers.length,before.triggers.length+1);assert.deepEqual(await business(),original);
 assert.equal((await db.query("select private.expense_cost_direction_v2_enabled('"+id(1)+"') value")).rows[0].value,false);
 assert.equal((await db.query("select public.expense_payment_direction_capability('"+id(1)+"') value")).rows[0].value.read_enabled,false);
 await db.exec("select private.refresh_automatic_payment_certificate('"+id(1)+"','"+id(5)+"','2026-07-01')");assert.deepEqual(await business(),original);
 const restore=buildCodeRestore(before,after);await db.exec(restore);await ensureOriginal();
 await db.exec('alter function private.read_expense_document(text,uuid) volatile');const drift=await captureCodeCheckpoint(db);
 await assert.rejects(db.exec(sql),/expense checkpoint drift/);await db.exec('ROLLBACK');assert.deepEqual(await captureCodeCheckpoint(db),drift);assert.deepEqual(await business(),original);
 await db.exec(before.functions.find(f=>f.signature==='private.read_expense_document(text,uuid)').definition);await ensureOriginal();
 console.log('PASS default-OFF preparation: fixed candidate SHA, complete metadata, exact new ACLs, no financial data changes, v1 nonzero deduction preservation, injected pre/postflight rollback and code-only restore');
} finally {await db.close();}
