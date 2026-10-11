// Disposable PGlite only; real payroll calculators, scoped reads, and finalizer.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {validatePayrollScopeFixtureUrl} from './payroll_scope_pg17_database_guard.mjs';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
const runtime=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const pgMode=process.argv.includes('--postgres');
const Client=runtime.Client??runtime.default?.Client;
const db=pgMode?new Client({connectionString:validatePayrollScopeFixtureUrl(process.env.SKO_PAYROLL_SCOPE_FIXTURE_URL)}):new runtime.PGlite();
if(pgMode)db.exec=sql=>db.query(sql);
const read=p=>fs.readFileSync(p,'utf8');
const migration=process.argv.slice(3).find(arg=>arg!=='--postgres')??'supabase/migrations/20261011053152_payroll_draft_current_seal.sql';
const cid='0f117273-0a06-4a2f-85ec-720a3c9f4cf4',name='すみだ建設株式会社';
const baseCompany='10000000-0000-0000-0000-000000000001',baseWorker='40000000-0000-0000-0000-000000000001';
const wid='40000000-0000-0000-0000-000000000091',actorId='00000000-0000-0000-0000-000000000091';
const month='2026-08-01',offMonth='2026-09-01';
async function actor(){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[actorId]);await db.exec('set role authenticated');}
async function admin(){await db.exec('reset role');}
async function state(){return (await db.query("select jsonb_build_object('statements',(select coalesce(jsonb_agg(to_jsonb(p) order by id),'[]') from public.payroll_statements p),'documents',(select coalesce(jsonb_agg(to_jsonb(d) order by statement_id),'[]') from payroll_final_private.documents d),'history',(select coalesce(jsonb_agg(to_jsonb(h) order by id),'[]') from payroll_final_private.history h)) value")).rows[0].value;}
async function rows(){await actor();return(await db.query('select to_jsonb(r) value from public.my_payroll_statement_rows_with_adjustments() r')).rows.map(r=>r.value);}
try{
 if(pgMode){
  await db.connect();
  assert.equal((await db.query('select current_database() db')).rows[0].db,'sko_payroll_scope_fixture');
  assert.equal(Math.floor(Number((await db.query('show server_version_num')).rows[0].server_version_num)/10000),17,'PostgreSQL 17 fixture only');
  assert.equal((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth')")).rows[0].n,0,'Fixture must be empty before any DDL');
  assert.equal((await db.query("select count(*)::int n from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','auth')")).rows[0].n,0,'Fixture must have no existing application functions');
 }
 await setupPayrollScopeFixture(db);
 await db.exec(read('supabase/migrations/20261009171504_payroll_refresh_scope_order.sql'));
 await db.exec(read('supabase/migrations/20261009151946_company_payroll_rate_registry.sql'));
 await db.exec(read('supabase/migrations/20261010030208_connect_payroll_tax_calculation.sql'));
 await admin();
 await db.query("insert into auth.users values($1)",[actorId]);
 await db.query("insert into companies select (jsonb_populate_record(null::public.companies,to_jsonb(c)||jsonb_build_object('id',$1::uuid,'name',$2::text,'company_seal_style','legacy','company_seal_enabled',true))).* from companies c where id=$3",[cid,name,baseCompany]);
 await db.query("insert into company_members values($1,$2,'owner')",[cid,actorId]);
 await db.query("insert into workers select (jsonb_populate_record(null::public.workers,to_jsonb(w)||jsonb_build_object('id',$1::uuid,'company_id',$2::uuid,'user_id',$3::uuid,'name','Fixture Payroll Employee','status','active','affiliation','employee'))).* from workers w where id=$4",[wid,cid,actorId,baseWorker]);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[actorId]);
 await db.query("insert into worker_payroll_settings select (jsonb_populate_record(null::public.worker_payroll_settings,to_jsonb(s)||jsonb_build_object('worker_id',$1::uuid,'company_id',$2::uuid,'pay_type','monthly','monthly_salary_yen',300000,'custom_earnings','[]'::jsonb,'custom_deductions','[]'::jsonb))).* from worker_payroll_settings s where company_id=$3 and worker_id=$4",[wid,cid,baseCompany,baseWorker]);
 for(const m of [month,offMonth]){
  await db.query('select private.refresh_automatic_payroll($1,$2,$3)',[cid,wid,m]);
  await db.query('select private.sync_payroll_attendance_detail($1,$2,$3)',[cid,wid,m]);
 }
 const ps=(await db.query('select * from payroll_statements where company_id=$1 and worker_id=$2 and period_start=$3',[cid,wid,month])).rows[0];
 assert.ok(ps,'real calculator must create a monthly draft');
 const historical='50000000-0000-0000-0000-000000000091';
 await db.query("insert into payroll_statements(id,company_id,worker_id,period_start,period_end,gross_pay,deductions,net_pay,detail,workflow_state,automatic_calculation) values($1,$2,$3,'2024-02-01','2024-02-29',9000,1000,8000,'{}','finalized',false)",[historical,cid,wid]);
 // Represents an old persisted draft predating seal snapshots. No production writes.
 await db.exec('alter table payroll_statements disable trigger zz_company_seal_snapshot');
 await db.query("update payroll_statements set detail=detail-'company_seal_snapshot' where company_id=$1 and workflow_state='draft'",[cid]);
 await db.exec('alter table payroll_statements enable trigger zz_company_seal_snapshot');
 await db.query("update companies set company_seal_style='png_sumida_v1_standard' where id=$1",[cid]);
 const beforeApply=await state();
 assert.equal(beforeApply.statements.find(r=>r.id===ps.id).detail.company_seal_snapshot,undefined,'fixture must represent an existing draft with no persisted seal snapshot');
 const metadataSource=(await db.query("select pg_get_functiondef('private.payroll_live_document_metadata(uuid)'::regprocedure) definition")).rows[0].definition;
 await db.exec("create or replace function private.payroll_live_document_metadata(p_statement_id uuid) returns jsonb language sql stable security definer set search_path='' as $$select '{}'::jsonb$$");
 await assert.rejects(db.exec(read(migration)),/prerequisite differs/);
 await db.exec('rollback');
 assert.deepEqual(await state(),beforeApply,'unknown metadata guard must leave rows and snapshots unchanged');
 await db.exec(metadataSource);
 await db.exec(read(migration));
 assert.deepEqual(await state(),beforeApply,'migration must never backfill draft/final/history rows');
 const draft=(await rows()).find(r=>r.id===ps.id);
 assert.equal(draft.detail.company_seal_snapshot.style,'png_sumida_v1_standard');
 assert.equal(draft.detail.company_seal_snapshot.company_id,cid);
 assert.equal(draft.detail.company_seal_snapshot.name,name);
 assert.equal(draft.detail.company_seal_enabled,true);
 const historicalBefore=(await rows()).find(r=>r.id===historical);
 assert.equal(historicalBefore.detail.company_seal_snapshot.style,'legacy');
 await admin();
 await db.query('insert into payroll_confirmers(company_id,user_id,position) values($1,$2,1)',[cid,actorId]);
 // Confirm the actual persisted revision, then use the real first-finalize RPC.
 const revision=(await db.query('select revision from payroll_statements where id=$1',[ps.id])).rows[0].revision;
 await db.query('insert into payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[ps.id,actorId,revision]);
 await actor();
 const finalProof=(await db.query('select public.finalize_payroll_statement($1,$2,true) result',[ps.id,revision])).rows[0].result;
 assert.equal(finalProof.finalized,true,'real finalizer must freeze the current saved PNG seal');
 const finalized=(await rows()).find(r=>r.id===ps.id);
 assert.equal(finalized.detail.company_seal_snapshot.style,'png_sumida_v1_standard');
 await admin();
 const savedBefore=(await db.query('select value from payroll_final_private.documents where statement_id=$1',[ps.id])).rows[0].value;
 await db.query("update companies set company_seal_style='png_sumida_v1_worn' where id=$1",[cid]);
 const finalizedAfterStyleChange=(await rows()).find(r=>r.id===ps.id);
 assert.deepEqual(finalizedAfterStyleChange,finalized,'saved finalized RPC row must be unchanged');
 const historicalFinalized=(await rows()).find(r=>r.id===historical);
 assert.deepEqual(historicalFinalized,historicalBefore,'historical legacy finalization must never adopt current PNG');
 await admin();assert.deepEqual((await db.query('select value from payroll_final_private.documents where statement_id=$1',[ps.id])).rows[0].value,savedBefore);
 await db.query('update companies set company_seal_enabled=false where id=$1',[cid]);
 const offDraft=(await rows()).find(r=>r.period_start===offMonth);
 assert.equal(offDraft.detail.workflow_state,'draft');assert.equal(offDraft.detail.company_seal_enabled,false);
 assert.equal(offDraft.detail.company_seal_snapshot.style,'png_sumida_v1_worn');
 const output='build/payroll-current-seal/response.json';fs.mkdirSync(path.dirname(output),{recursive:true});
 fs.writeFileSync(output,JSON.stringify({draft,finalized,finalizedAfterStyleChange,historicalFinalized,offDraft},null,2)+'\n');
 console.log((pgMode?'PostgreSQL 17: ':'PGlite: ')+'PASS actual payroll draft current seal, genuine first finalization, frozen/legacy snapshots, OFF, guarded no-backfill rollback; '+output);
}catch(e){console.error(e.stack,e.where??'',e.position??'');process.exitCode=1;}finally{if(pgMode)await db.end();else await db.close();}
