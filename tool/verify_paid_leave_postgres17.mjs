// Disposable PostgreSQL 17 only. No Supabase credentials or real data.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {validatePaidLeaveFixtureUrl} from './paid_leave_pg17_database_guard.mjs';
const connectionString=validatePaidLeaveFixtureUrl(process.env.SKO_PAID_LEAVE_FIXTURE_URL);
const pgModule=await import(process.argv[2]);
const Client=pgModule.Client??pgModule.default?.Client;
assert.equal(typeof Client,'function','A pg Client constructor is required');
const db=new Client({connectionString,application_name:'sko-paid-leave-pg17'});
await db.connect();
db.exec=sql=>db.query(sql);
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const cid='10000000-0000-0000-0000-000000000001';
const wid='40000000-0000-0000-0000-000000000001';
const fixture='tool/fixtures/paid_leave_pg17/';
const signatureFor=m=>`private.${m.proname}(${m.arguments.split(',').map(x=>x.trim().replace(/^\w+ /,'')).join(',')})`;
const snapshots=async()=> (await db.query("select coalesce(jsonb_agg(to_jsonb(ps) order by id),'[]') rows from public.payroll_statements ps")).rows[0].rows;
const triggers=async()=> (await db.query("select oid,tgname,pg_get_triggerdef(oid) definition,tgenabled from pg_trigger where not tgisinternal order by oid")).rows;
try {
 assert.equal(Number((await db.query('show server_version_num')).rows[0].server_version_num)/10000|0,17,'PostgreSQL 17 required');
 assert.equal((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth') and c.relkind in ('r','v','m')")).rows[0].n,0,'Fixture must start empty');
 await db.query("set statement_timeout='30s'; set lock_timeout='10s'");
 await db.exec(read('supabase/tests/invoice_stamp_approval_workflow.sql'));
 await db.exec(read('supabase/tests/payroll_private_bank_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/payroll_pay_type_metadata_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/payroll_calculation_invariant_fixture.sql'));
 await db.exec(read('supabase/migrations/20261006162510_payroll_flexible_earnings_deductions_payment_day.sql'));
 await db.exec(read('supabase/migrations/20261007021000_worker_monthly_salary_mode.sql'));
 await db.exec(read('supabase/migrations/20261008001025_payroll_statement_pay_type_metadata.sql'));
 await db.exec(read('supabase/migrations/20261008035104_stabilize_automatic_payroll_totals.sql'));
 await db.exec(`create table public.paid_leave_requests(company_id uuid,worker_id uuid,leave_date date,status text); alter table public.workers add column status text default 'active',add column affiliation text default 'employee',add column hire_date date;`);
 await db.exec(read('supabase/migrations/20261008040428_generate_fixed_monthly_payroll_without_attendance.sql'));

 await db.exec(`alter table public.attendance_entries add primary key(id),add column night_hours numeric default 0;
 alter table public.worker_payroll_settings add column night_daily numeric default 15000,
 add column night_overtime numeric default 2000,add column night_early numeric default 2000,
 add column holiday_daily numeric default 13500,add column holiday_overtime numeric default 2000,
 add column holiday_early numeric default 2000,add column holiday_night_daily numeric default 16000,
 add column holiday_night_overtime numeric default 2500,add column holiday_night_early numeric default 2500,
 add column allowance_name_1 text,add column allowance_1 numeric default 0;
 delete from public.payroll_statements; delete from public.attendance_entries;
 update public.worker_payroll_settings set pay_type='daily',day_daily=10000,day_overtime=1563,day_early=1563,
 monthly_salary_yen=0,custom_earnings='[]',custom_deductions='[]' where worker_id='${wid}';`);
 await db.exec(read('supabase/tests/payroll_live_linkage_snapshot.sql'));
 await db.exec(`create trigger attendance_refresh_payroll after insert or update or delete on public.attendance_entries
 for each row execute function private.attendance_refresh_payroll();
 create trigger attendance_sync_payroll_detail after insert or update or delete on public.attendance_entries
 for each row execute function private.attendance_sync_payroll_detail();
 create trigger settings_refresh_payroll after insert or update on public.worker_payroll_settings
 for each row execute function private.settings_refresh_payroll();
 create trigger paid_leave_sync_payroll_detail after insert or update or delete on public.paid_leave_requests
 for each row execute function private.paid_leave_sync_payroll_detail();`);
 // Optional reviewed migration(s) under test can override snapshots without editing them.
 for(const migration of ['supabase/migrations/20261008042817_prevent_paid_leave_attendance_overlap.sql','supabase/migrations/20261008043151_align_future_attendance_monthly_payroll_boundary.sql','supabase/migrations/20261008045401_preserve_payroll_named_financial_details.sql']) await db.exec(read(migration));
 await db.exec(`alter table public.worker_payroll_settings add column if not exists rate_formula jsonb default '{}', add column if not exists hourly_rate_yen numeric default 0;`);
 // Replace the five target functions and six direct guards/callers with code-only
 // read-only live definitions; no user rows, credentials or snapshots enter CI.
 await db.exec(read(fixture+'old_functions.sql'));
 const meta=JSON.parse(read(fixture+'old_function_metadata.json'));
 for (const m of meta) {
   const signature=signatureFor(m);
   if(m.acl!==null) await db.query(`revoke all on function ${signature} from public,anon,authenticated`);
   const row=(await db.query('select md5(pg_get_functiondef($1::regprocedure)) hash',[signature])).rows[0];
   assert.equal(row.hash,m.definition_md5,`Code-only baseline definition differs: ${m.proname}`);
 }
 await db.exec(read(fixture+'rollout_seed.sql'));
 const before=await snapshots();
 const triggerBefore=await triggers();
 const oldDefs=(await db.query(`select p.oid::regprocedure::text signature,pg_get_functiondef(p.oid) definition,p.proacl::text acl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname=any($1::text[]) order by p.proname`,[meta.map(x=>x.proname)])).rows;
 const oldWarnings=(await db.query(`select private.payroll_condition_warnings($1,$2,date_trunc('month',now() at time zone 'Asia/Tokyo')::date,(date_trunc('month',now() at time zone 'Asia/Tokyo')+interval '1 month - 1 day')::date) warnings`,[cid,wid])).rows[0].warnings;
 assert.ok(oldWarnings.some(x=>x.includes('現在の自動計算に含まれていません')));
 await db.exec(read('supabase/migrations/20261008200018_paid_leave_wage_contract.sql'));
 assert.deepEqual(await snapshots(),before,'DDL alone changed saved statements');
 assert.deepEqual(await triggers(),triggerBefore,'DDL replaced/disabled existing triggers');
 assert.equal((await db.query('select public.paid_leave_wage_contract_version() version')).rows[0].version,1);
 assert.equal((await db.query("select has_function_privilege('authenticated','public.paid_leave_wage_contract_version()','EXECUTE') allowed,has_function_privilege('anon','public.paid_leave_wage_contract_version()','EXECUTE') anon_allowed")).rows[0].allowed,true);
 assert.equal((await db.query("select has_function_privilege('anon','public.paid_leave_wage_contract_version()','EXECUTE') allowed")).rows[0].allowed,false);
 for(const m of meta.filter(x=>['refresh_automatic_payroll_internal','sync_payroll_attendance_detail','paid_leave_sync_payroll_detail','payroll_condition_warnings','ensure_monthly_payroll_drafts'].includes(x.proname))){
   const privileges=(await db.query("select has_function_privilege('anon',$1,'EXECUTE') anon_allowed,has_function_privilege('authenticated',$1,'EXECUTE') authenticated_allowed",[signatureFor(m)])).rows[0];
   assert.deepEqual(privileges,{anon_allowed:false,authenticated_allowed:false},'Internal function is directly executable');
 }
 await db.query('set role authenticated');
 try {assert.equal((await db.query('select public.paid_leave_wage_contract_version() version')).rows[0].version,1);}
 finally {await db.query('reset role');}
 console.log('PASS PostgreSQL 17: DDL alone leaves every statement and trigger unchanged; capability immediately 1');
 const immutable=before.filter(x=>x.workflow_state!=='draft'||!x.automatic_calculation||x.detail.probe==='past');
 const assertProtected=async()=>assert.deepEqual((await snapshots()).filter(x=>immutable.some(y=>y.id===x.id)),immutable,'Protected full row changed');
 await db.query("select private.ensure_monthly_payroll_drafts((now() at time zone 'Asia/Tokyo')::date)");
 let draft=(await snapshots()).find(x=>x.worker_id===wid&&x.detail.probe!=='past');
 assert.equal(draft.gross_pay,12000);
 assert.equal(draft.detail['有給支給額'],12000);
 assert.equal(draft.detail.paid_leave_wage_contract,1);
 await assertProtected();
 // Approval transition through the real existing paid-leave trigger.
 await db.query("update public.paid_leave_requests set status='pending' where company_id=$1 and worker_id=$2",[cid,wid]);
 assert.ok(!(await snapshots()).some(x=>x.worker_id===wid&&x.detail.probe!=='past'),'Revoked leave-only automatic draft remains');
 await assertProtected();
 await db.query("update public.paid_leave_requests set status='approved' where company_id=$1 and worker_id=$2",[cid,wid]);
 assert.equal((await snapshots()).find(x=>x.worker_id===wid&&x.detail.probe!=='past').gross_pay,12000);
 await assertProtected();
 const newWarnings=(await db.query(`select private.payroll_condition_warnings($1,$2,date_trunc('month',now() at time zone 'Asia/Tokyo')::date,(date_trunc('month',now() at time zone 'Asia/Tokyo')+interval '1 month - 1 day')::date) warnings`,[cid,wid])).rows[0].warnings;
 assert.ok(!newWarnings.some(x=>x.includes('現在の自動計算に含まれていません')));
 console.log('PASS normal triggers/scheduler update current automatic draft; manual/finalized/past full rows unchanged; old leave warning resolved');
 const beforeRestore=await snapshots();
 await db.query('begin');
 try {
   for(const m of oldDefs){
     await db.query(m.definition);
     await db.query(`revoke all on function ${m.signature} from public,anon,authenticated`);
     if(m.acl===null) await db.query(`grant execute on function ${m.signature} to public`);
   }
   await db.query('drop function public.paid_leave_wage_contract_version(); drop function private.paid_leave_daily_amount(jsonb)');
   await db.query('commit');
 } catch(e){await db.query('rollback');throw e;}
 assert.deepEqual(await snapshots(),beforeRestore,'Restoring DDL modified saved statements');
 assert.deepEqual(await triggers(),triggerBefore);
 assert.equal((await db.query("select to_regprocedure('public.paid_leave_wage_contract_version()') is null absent")).rows[0].absent,true);
 for(const m of meta){
   const row=(await db.query('select md5(pg_get_functiondef($1::regprocedure)) hash,proacl::text acl from pg_proc where oid=$1::regprocedure',[signatureFor(m)])).rows[0];
   assert.equal(row.hash,m.definition_md5);
   if(m.acl!==null) assert.equal(row.acl,m.acl);
   else {
     const privileges=(await db.query("select has_function_privilege('anon',$1,'EXECUTE') anon_allowed,has_function_privilege('authenticated',$1,'EXECUTE') authenticated_allowed",[signatureFor(m)])).rows[0];
     assert.deepEqual(privileges,{anon_allowed:true,authenticated_allowed:true},'Default PUBLIC EXECUTE semantics not restored');
   }
 }
 assert.equal((await snapshots()).find(x=>x.worker_id===wid&&x.detail.probe!=='past').gross_pay,12000,'DDL restore must not pretend to restore old draft amounts');
 console.log('PASS old function definitions/ACL restored transactionally; triggers preserved; DDL rollback does not restore draft data');
 // Preserve the existing PGlite assertions and run the same contracts on PG17.
 await db.exec(read('supabase/migrations/20261008200018_paid_leave_wage_contract.sql'));
 await db.exec(read('supabase/tests/payroll_named_financial_detail_assertions.sql'));
 await db.exec(read('supabase/tests/paid_leave_wage_assertions.sql'));
 console.log('PASS existing named-financial and paid-leave trigger assertions on PostgreSQL 17');
} finally {await db.end();}
