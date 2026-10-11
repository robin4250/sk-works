// Disposable SQL fixture only; never connect this verifier to an application database.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const runtime=await import(pathToFileURL(resolve(process.argv[2])).href);
const pgMode=process.argv.includes('--postgres');
const read=p=>readFile(resolve(root,p),'utf8');
const db=pgMode?new runtime.Client({connectionString:process.env.FIXTURE_DATABASE_URL}):new runtime.PGlite();
if(pgMode) await db.connect();
const exec=sql=>pgMode?db.query(sql):db.exec(sql);
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
function section(sql,start,end){const a=sql.indexOf(start);assert.ok(a>=0,start);const b=sql.indexOf(end,a+start.length);assert.ok(b>a,end);return sql.slice(a,b);}
try{
 await exec(`create role authenticated;create role anon;create schema private;create schema auth;create schema payroll_final_private;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.actor',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql stable as $$select auth.uid() is not null and coalesce(current_setting('fixture.active',true),'true')='true'$$;
 create function private.payroll_confirmer_eligible(uuid,uuid,date) returns boolean language sql stable as $$select false$$;
 create function private.payroll_confirmed_all(uuid) returns boolean language sql stable as $$select false$$;
 create function private.payroll_document_metadata(uuid) returns jsonb language sql stable as $$select '{}'::jsonb$$;
 create type public.app_role as enum('owner','admin','manager','viewer','member');
 create table companies(id uuid primary key,name text);
 create table company_members(company_id uuid,user_id uuid,role app_role);
 create table workers(id uuid primary key,company_id uuid,name text,status text,affiliation text);
 create table payroll_confirmers(company_id uuid,user_id uuid);
 create table payroll_manager_worker_visibility(company_id uuid,worker_id uuid,visible_to_manager boolean);
 create table payroll_statements(id uuid primary key,company_id uuid,worker_id uuid,period_start date,period_end date,issued_at timestamptz,gross_pay integer,deductions integer,net_pay integer,detail jsonb,revision integer,workflow_state text);
 create table payroll_statement_reviews(statement_id uuid,reviewer_id uuid,checked_revision integer,confirmed_revision integer);
 create table payroll_adjustments(company_id uuid,worker_id uuid,effective_date date,cancelled_at timestamptz,label_snapshot text,direction text,amount_yen integer);
 create table payroll_final_private.documents(statement_id uuid primary key,revision integer,value jsonb);
 grant usage on schema private,auth to authenticated;grant usage on schema auth to anon;
 grant execute on function auth.uid() to authenticated,anon;
 insert into companies values('${id(1)}','Fixture company'),('${id(2)}','Other company');
 insert into company_members values('${id(1)}','${id(10)}','owner'),('${id(1)}','${id(11)}','admin'),('${id(1)}','${id(12)}','viewer'),('${id(1)}','${id(13)}','manager'),('${id(1)}','${id(14)}','member'),('${id(2)}','${id(15)}','owner');
 insert into workers values('${id(20)}','${id(1)}','Visible','active','employee'),('${id(21)}','${id(1)}','Hidden','active','employee'),('${id(22)}','${id(2)}','Foreign','active','employee');
 insert into payroll_manager_worker_visibility values('${id(1)}','${id(20)}',true);
 insert into payroll_statements values
 ('${id(30)}','${id(1)}','${id(20)}','2026-09-01','2026-09-30','2026-09-30',100,10,90,'{"bank_account":{"secret":"fixture"}}',1,'draft'),
 ('${id(31)}','${id(1)}','${id(21)}','2026-09-01','2026-09-30','2026-09-30',200,20,180,'{}',2,'finalized'),
 ('${id(32)}','${id(1)}','${id(20)}','2026-09-01','2026-09-30','2026-09-30',300,30,270,'{}',3,'finalized'),
 ('${id(33)}','${id(2)}','${id(22)}','2026-09-01','2026-09-30','2026-09-30',400,40,360,'{}',4,'finalized');
 insert into payroll_final_private.documents select id,revision,jsonb_build_object('worker_name','Saved worker','company_name','Saved company','period_start',period_start,'period_end',period_end,'issued_at',issued_at,'result',jsonb_build_object('gross_pay',gross_pay,'deductions',deductions,'net_pay',net_pay),'detail',jsonb_build_object('saved',true),'document_metadata',jsonb_build_object('payroll_confirmations','[]'::jsonb)) from payroll_statements where workflow_state='finalized';`);
 const final=await read('supabase/migrations/20261009165026_finalized_payroll_document_snapshot.sql');
 await exec(section(final,'CREATE OR REPLACE FUNCTION private.payroll_live_review_workspace(',"revoke all on function private.payroll_live_review_workspace(date)"));
 await exec('revoke all on function private.payroll_live_review_workspace(date) from public,anon,authenticated');
 const scope=await read('supabase/migrations/20261009171504_payroll_refresh_scope_order.sql');
 await exec(section(scope,'create or replace function private.payroll_review_workspace(', '-- Vehicle child mutation'));
 await exec('revoke all on function private.payroll_review_workspace(date) from public,anon,authenticated');
 const original=await read('supabase/migrations/20261004110609_add_payroll_review_confirmation.sql');
 await exec(section(original,'create or replace function public.payroll_review_workspace(', 'create or replace function private.my_payroll_review_statuses()'));
 // Exact public body captured via read-only pg_get_functiondef, MD5 a955dcbe1f15dfb56d7fc795b4117ac5.
 await exec("create or replace function public.payroll_review_workspace(p_period_start date default null) returns jsonb language sql stable set search_path='' as $function$ select private.payroll_review_workspace(p_period_start) $function$;");
 assert.equal((await db.query("select prosecdef from pg_proc where oid='public.payroll_review_workspace(date)'::regprocedure")).rows[0].prosecdef,false,'real public wrapper must remain INVOKER');
 const snapshot=async()=>JSON.stringify((await db.query("select * from (select 'statements' k,to_jsonb(s) v from payroll_statements s union all select 'documents',to_jsonb(d) from payroll_final_private.documents d) q order by k,v::text")).rows);
 const before=await snapshot();
 const metadata=async()=>JSON.stringify((await db.query("select oid::regprocedure::text fn,md5(pg_get_functiondef(oid)) definition,prosecdef,proconfig,pg_get_userbyid(proowner) owner from pg_proc where oid in ('public.payroll_review_workspace(date)'::regprocedure,'private.payroll_review_workspace(date)'::regprocedure,'private.payroll_live_review_workspace(date)'::regprocedure) order by fn")).rows);
 const originalMetadata=await metadata();
 const unchangedAcl=async()=>JSON.stringify((await db.query("select p.oid::regprocedure::text fn,proacl::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.oid<>'private.payroll_review_workspace(date)'::regprocedure order by fn")).rows);
 const originalAcl=await unchangedAcl();
 const actor=async(n,role='authenticated')=>{await exec('reset role');await db.query("select set_config('fixture.actor',$1,false)",[n===null?'':id(n)]);await exec(`set role ${role}`);};
 const workspace=async()=> (await db.query("select public.payroll_review_workspace('2026-09-01') v")).rows[0].v;
 await actor(10);
 await assert.rejects(workspace(),e=>e.code==='42501'&&/payroll_review_workspace/.test(e.message),'old private EXECUTE denial must reproduce');
 await exec('reset role');
 if(process.argv[3]) {const hashes=(await db.query("select oid::regprocedure::text fn,md5(prosrc) hash from pg_proc where oid in ('public.payroll_review_workspace(date)'::regprocedure,'private.payroll_review_workspace(date)'::regprocedure,'private.payroll_live_review_workspace(date)'::regprocedure) order by fn")).rows;assert.deepEqual(hashes.map(x=>x.hash),['a955dcbe1f15dfb56d7fc795b4117ac5','fa27af8bdff62e3ab2223263d05add61','d006962129b4f0cc4e958370f04308bf']);await exec(await readFile(resolve(process.argv[3]),'utf8'));}
 else throw new Error('Pass the reviewed minimal-grant migration as argv 3');
 assert.equal(await metadata(),originalMetadata,'migration must not change function definitions, ownership or execution mode');
 for(const n of [10,11,12]){await actor(n);const w=await workspace();assert.deepEqual(w.statements.map(s=>s.id).sort(),[id(30),id(31),id(32)]);assert.equal(w.statements.find(s=>s.id===id(32)).detail.saved,true);assert.equal(w.statements.find(s=>s.id===id(32)).net_pay,270);}
 await actor(13);assert.deepEqual((await workspace()).statements.map(s=>s.id).sort(),[id(30),id(32)]);
 await actor(15);assert.deepEqual((await workspace()).statements.map(s=>s.id),[id(33)]);
 for(const n of [14,99,null]){await actor(n);await assert.rejects(workspace(),e=>e.code==='P0001');await assert.rejects(db.query("select private.payroll_review_workspace('2026-09-01')"),e=>e.code==='P0001');}
 await actor(10);await exec("set fixture.active='false'");await assert.rejects(workspace(),e=>e.code==='P0001');await exec("set fixture.active='true'");
 await actor(10,'anon');await assert.rejects(workspace(),e=>e.code==='42501');
 await exec('reset role');
 assert.equal(await unchangedAcl(),originalAcl,'other function ACLs remain unchanged');
 assert.equal((await db.query("select has_function_privilege('anon','private.payroll_review_workspace(date)','execute') v")).rows[0].v,false,'private wrapper remains unavailable to anon');
 assert.equal(await snapshot(),before,'workspace reads must preserve all draft/final statement and saved snapshot fields');
 assert.equal((await db.query("select has_function_privilege('authenticated','private.payroll_live_review_workspace(date)','execute') v")).rows[0].v,false,'inner live helper remains closed');
 console.log('PASS real INVOKER payroll workspace: old denial, minimal grant, scoped roles, actor/account rejection and immutable saved rows');
}finally{if(pgMode)await db.end();else await db.close();}
