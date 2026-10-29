// Focused new catalog/capsule checks, not a rerun of the 73-case real-Auth suite.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const pg=(await import(process.argv[2])).default;
const url=new URL(process.env.SKO_BANK_CAPSULE_FIXTURE_URL??'');
assert.ok(['127.0.0.1','localhost'].includes(url.hostname)&&url.port==='5432'&&url.pathname==='/sko_bank_capsule_fixture'&&!url.search&&!url.hash&&url.username==='postgres'&&url.password==='synthetic_capsule_only');
const db=new pg.Client({connectionString:url.href});await db.connect();
const read=p=>fs.readFile(p,'utf8');
const dir='docs/candidates/employee_bank_preapply_capsule_20261029/';
let checks=0;
const eq=(a,b)=>{assert.deepEqual(a,b);checks++;};
try{
 assert.match((await db.query('show server_version')).rows[0].server_version,/^17\./);
 eq((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
 await db.query(`create role anon;create role authenticated;create role service_role;create role capsule_drift;
 create schema auth;create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
 create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
 create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz,encrypted_password text);
 create table auth.sessions(id uuid primary key,user_id uuid not null,not_after timestamptz);`);
 await db.query(await read('tool/security/employee_bank_initial/fixture-business.sql'));
 await db.query(await read('tool/security/employee_bank_initial/baseline-functions.sql'));
 const catalog=JSON.parse(await read('tool/security/employee_bank_preapply_capsule/catalog.json'));
 // Existing fixture baseline-functions.sql already attaches the genuine original trigger.
 // Seed through its normal own-worker branch with synthetic identities/claims.
 await db.query("insert into auth.users(id) values('40000000-0000-0000-0000-000000000005');insert into auth.sessions values('40000000-0000-0000-0000-000000000006','40000000-0000-0000-0000-000000000005',null);select set_config('request.jwt.claims','{\"sub\":\"40000000-0000-0000-0000-000000000005\",\"session_id\":\"40000000-0000-0000-0000-000000000006\",\"role\":\"authenticated\",\"is_anonymous\":false}',false)");
 await db.query("insert into public.companies values('40000000-0000-0000-0000-000000000001','SYNTHETIC');insert into public.workers(id,company_id,user_id) values('40000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000005');insert into public.worker_private_bank_accounts values('40000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000001','SYNTHETIC BANK','SYNTHETIC BRANCH','普通','0000001','SYNTHETIC HOLDER',now());insert into public.payroll_statements values('40000000-0000-0000-0000-000000000003','40000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002','{\"synthetic_original\":true}');insert into payroll_final_private.documents values('40000000-0000-0000-0000-000000000003','{\"synthetic_signature\":true}');insert into payroll_final_private.history values('40000000-0000-0000-0000-000000000004','{\"synthetic_history\":true}')");

 const forward=await read(dir+'install.sql.review-only'),restore=await read(dir+'restore-unused.sql.review-only');
 const snapshot=async()=>(await db.query(`select jsonb_build_object('functions',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'config',p.proconfig,'strict',p.proisstrict,'vol',p.provolatile,'leak',p.proleakproof,'parallel',p.proparallel) order by p.oid::regprocedure::text) from pg_proc p where p.oid=any($1::regprocedure[])),
 'bank',(select jsonb_agg(to_jsonb(t)) from public.worker_private_bank_accounts t),
 'status',(select jsonb_agg(to_jsonb(t)) from public.worker_document_statuses t),
 'payroll',(select jsonb_agg(to_jsonb(t)) from public.payroll_statements t),
 'documents',(select jsonb_agg(to_jsonb(t)) from payroll_final_private.documents t),'history',(select jsonb_agg(to_jsonb(t)) from payroll_final_private.history t),
 'trigger',(select jsonb_agg(jsonb_build_object('def',pg_get_triggerdef(t.oid),'enabled',t.tgenabled)) from pg_trigger t where t.tgrelid='public.worker_private_bank_accounts'::regclass and not t.tgisinternal)) v`,[catalog.functions.map(x=>x.signature)])).rows[0].v;
 const before=await snapshot();
 // Original definition MD5 alone accepts ACL/owner drift. The new capsule must not.
 const drifts=[
  'grant execute on function private.reauthentication_scope(text) to authenticated',
  'alter function private.reauthentication_scope(text) owner to capsule_drift',
  "alter function private.reauthentication_scope(text) set search_path=public",
  'alter function private.reauthentication_scope(text) security definer',
  'alter function private.reauthentication_scope(text) stable',
  'alter function private.reauthentication_scope(text) strict',
  'alter function private.reauthentication_scope(text) leakproof',
  'alter function private.reauthentication_scope(text) parallel safe',
  'alter table public.worker_private_bank_accounts disable trigger sync_bank_document_status'
 ];
 for(const sql of drifts){
  await db.query('begin');await db.query(sql);
  await assert.rejects(db.query(forward),error=>error.code==='55000'&&error.message.startsWith('employee_bank_capsule_'));checks++;
  await db.query('rollback');eq(await snapshot(),before);
  eq((await db.query("select to_regclass('private.employee_bank_initial_context') v")).rows[0].v,null);
 }
 await db.query(forward);eq((await db.query('select private.employee_bank_initial_enabled() v')).rows[0].v,false);
 // Proposed original module is intact; only its four reviewed bodies changed.
 const installed=await snapshot();for(const name of ['bank','status','payroll','documents','history','trigger'])eq(installed[name],before[name]);
 for(const sql of drifts.slice(0,2)){
  await db.query('begin');await db.query(sql);
  await assert.rejects(db.query(restore),error=>error.code==='55000'&&error.message.startsWith('employee_bank_capsule_'));checks++;
  await db.query('rollback');eq(await snapshot(),installed);
 }
 await db.query(restore);eq(await snapshot(),before);
 eq((await db.query("select to_regclass('private.employee_bank_initial_context') v")).rows[0].v,null);
 // A late installer failure must roll back all new objects and changed originals.
 const marker='commit;';assert.ok(forward.endsWith(marker+'\n'));
 const late=forward.slice(0,-(marker.length+1))+"do $$begin raise sqlstate 'P0001' using message='synthetic_late_failure';end $$;\ncommit;\n";
 await assert.rejects(db.query(late),error=>error.code==='P0001');await db.query('rollback');checks++;
 eq(await snapshot(),before);eq((await db.query("select to_regclass('private.employee_bank_initial_context') v")).rows[0].v,null);
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,owner_acl_and_attributes_drift_rejected:true,actual_bank_trigger_dependency_pinned:true,single_transaction_late_failure_rollback:true,unused_restore_exact_originals:true,old_auth_suites_repeated:false,production_changed:false}));
}finally{await db.end();}
