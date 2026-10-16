// Disposable synthetic PGlite only; never reads a project or personal data.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const db=new PGlite();
const id=n=>'10000000-0000-0000-0000-'+String(n).padStart(12,'0');
const [c,u,w,r,n,other,foreign]=[1,2,3,4,5,6,7].map(id);
await db.exec(`create role authenticated;create role anon;create schema auth;create schema private;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.actor',true),'')::uuid$$;
create function private.account_access_allowed() returns boolean language sql stable as $$select current_setting('fixture.blocked',true) is distinct from 'true'$$;
create function private.has_company_feature(uuid,text) returns boolean language sql stable as $$select current_setting('fixture.feature',true) is distinct from 'false'$$;
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.workers(id uuid,company_id uuid,user_id uuid,status text);
create table public.worker_personnel_change_requests(id uuid,company_id uuid,worker_id uuid,requested_by uuid,status text,resolved_at timestamptz,proposed jsonb);
create table public.app_notifications(id uuid,company_id uuid,recipient_user_id uuid,action_key text,action_id uuid);
grant usage on schema public,private,auth to authenticated,anon;
grant select on public.company_members to authenticated;
alter table worker_personnel_change_requests enable row level security;
revoke all on worker_personnel_change_requests from anon,authenticated;
insert into company_members values('${c}','${u}','employee');
insert into workers values('${w}','${c}','${u}','active');
insert into worker_personnel_change_requests values('${r}','${c}','${w}','${u}','approved',now(),'{"secret":"must not return"}');
insert into app_notifications values('${n}','${c}','${u}','worker_personnel_change_completed','${r}');
set fixture.actor='${u}';`);
const source=fs.readFileSync(root+'/supabase/migrations/20261011204715_employee_personnel_read_view.sql','utf8');
const start=source.indexOf('create function private.personnel_view_allowed(');
const end=source.indexOf('create function private.personnel_portrait_path(');
assert(start>=0&&end>start);
await db.exec(source.slice(start,end));
const sql=fs.readFileSync(root+'/tool/staged/worker_personnel_completed_notification_target.sql','utf8');
const aclBefore=(await db.query("select relname,relacl::text from pg_class where oid in ('public.worker_personnel_change_requests'::regclass,'public.app_notifications'::regclass,'public.company_members'::regclass,'public.workers'::regclass) order by relname")).rows;
await db.exec(sql);
assert.deepEqual((await db.query("select relname,relacl::text from pg_class where oid in ('public.worker_personnel_change_requests'::regclass,'public.app_notifications'::regclass,'public.company_members'::regclass,'public.workers'::regclass) order by relname")).rows,aclBefore);
const call=async(company=c,notice=n,request=r)=>(await db.query('select public.worker_personnel_completed_notification_target($1,$2,$3) target',[company,notice,request])).rows[0].target;
const denied=async()=>assert.rejects(call(),e=>e.code==='42501'&&e.message==='通知の対象を確認できません');
await db.exec('set role authenticated');
assert.deepEqual(await call(),{company_id:c,request_id:r,worker_id:w,status:'approved'});
for(const args of [[null,n,r],[c,null,r],[c,n,null],[foreign,n,r],[c,other,r],[c,n,other]]){
 await assert.rejects(call(...args),e=>e.code==='42501'&&e.message==='通知の対象を確認できません');
}
await assert.rejects(db.query('select * from worker_personnel_change_requests'),e=>e.code==='42501');
await db.exec('reset role');
for(const role of ['owner','admin','viewer','manager']){
 await db.query('update workers set user_id=$1',[other]);
 await db.query('update company_members set role=$1',[role]);
 await db.exec('set role authenticated');
 assert.equal((await call()).worker_id,w);
 await db.exec('reset role');
}
await db.exec("set fixture.feature='false';set role authenticated");await denied();await db.exec('reset role');
await db.exec("set fixture.feature='true';update company_members set role='employee';set role authenticated");await denied();await db.exec('reset role');
await db.query('update workers set user_id=$1',[u]);
const mutations=[
 ["update app_notifications set recipient_user_id=$1",other,"update app_notifications set recipient_user_id=$1",u],
 ["update app_notifications set action_id=$1",other,"update app_notifications set action_id=$1",r],
 ["update app_notifications set company_id=$1",foreign,"update app_notifications set company_id=$1",c],
 ["update worker_personnel_change_requests set company_id=$1",foreign,"update worker_personnel_change_requests set company_id=$1",c],
 ["update worker_personnel_change_requests set requested_by=$1",other,"update worker_personnel_change_requests set requested_by=$1",u],
 ["update worker_personnel_change_requests set worker_id=$1",other,"update worker_personnel_change_requests set worker_id=$1",w],
 ["update workers set company_id=$1",foreign,"update workers set company_id=$1",c],
 ["update company_members set company_id=$1",foreign,"update company_members set company_id=$1",c],
];
for(const [change,value,restore,original] of mutations){
 await db.query(change,[value]);await db.exec('set role authenticated');await denied();await db.exec('reset role');await db.query(restore,[original]);
}
for(const status of ['pending','rejected']){
 await db.query('update worker_personnel_change_requests set status=$1',[status]);await db.exec('set role authenticated');await denied();await db.exec('reset role');
}
await db.exec("update worker_personnel_change_requests set status='approved';update app_notifications set action_key='worker_personnel_change';set role authenticated");await denied();await db.exec("reset role;update app_notifications set action_key='worker_personnel_change_completed'");
await db.exec("update workers set status='inactive';set role authenticated");await denied();await db.exec("reset role;update workers set status='active'");
await db.exec("set fixture.blocked='true';set role authenticated");await denied();await db.exec("reset role;set fixture.blocked='false';set fixture.actor='';set role authenticated");await denied();await db.exec("reset role;set role anon");
await assert.rejects(call(),e=>e.code==='42501');await db.exec("reset role;set fixture.actor='"+u+"'");
await db.exec("begin;update worker_personnel_change_requests set resolved_at=null;set role authenticated");await denied();await db.exec('rollback');
await db.exec("set fixture.actor='"+other+"';set role authenticated");await denied();await db.exec("reset role;set fixture.actor='"+u+"'");
await db.exec("begin;delete from app_notifications;set role authenticated");await denied();await db.exec('rollback');
await db.exec("begin;delete from worker_personnel_change_requests;set role authenticated");await denied();await db.exec('rollback');
await db.exec("begin;delete from workers;set role authenticated");await denied();await db.exec('rollback');
await db.exec("begin;delete from company_members;set role authenticated");await denied();await db.exec('rollback');
assert.equal((await db.query('select proposed->>\'secret\' secret from worker_personnel_change_requests')).rows[0].secret,'must not return');
await db.close();
console.log('PASS: exact completed notification request target; self + existing personnel scopes; revoked membership/account and forged/foreign/pending/deleted targets denied; table ACL unchanged; no personal payload returned.');
