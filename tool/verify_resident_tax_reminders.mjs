import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite}=await import(process.env.PGLITE_PACKAGE||'@electric-sql/pglite');
const db=new PGlite();let assertions=0;
const eq=(a,b)=>{assert.deepEqual(a,b);assertions++;};
const q=async(s,args=[]) => (await db.query(s,args)).rows;
const scalar=async(s,args=[]) => Object.values((await q(s,args))[0])[0];
const deny=async(s,args=[])=>{await assert.rejects(()=>db.query(s,args));assertions++;};
const sql=await readFile(process.env.REMINDER_SQL||new URL('reminder.sql.review-only',import.meta.url),'utf8');
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const company=id(100),otherCompany=id(200),owner=id(1),viewer=id(2),employee=id(3),stale=id(4),banned=id(5),deleted=id(6),restricted=id(7),manager=id(8),outsider=id(9);
async function as(actor){await db.exec(`reset role;set test.uid='${actor}';set test.allowed='true';set role authenticated;`);}
const dispatch='select private.enqueue_resident_tax_cutover_reminders($1::timestamptz,$2::boolean)';
const read='select public.read_resident_tax_reminder_settings($1::uuid)';
const save='select public.save_resident_tax_reminder_settings($1::uuid,$2::boolean,$3::timestamptz)';
try{
await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create role unexpected_grantee;
create schema auth;create schema private;create table auth.users(id uuid primary key,deleted_at timestamptz,banned_until timestamptz);
create table companies(id uuid primary key);create type public.fixture_company_role as enum('owner','admin','manager','viewer','employee');create table company_members(company_id uuid,user_id uuid,role public.fixture_company_role,created_at timestamptz not null default now(),primary key(company_id,user_id));
create table company_module_settings(company_id uuid references companies, module_key text,is_enabled boolean,updated_by uuid references auth.users,updated_at timestamptz,primary key(company_id,module_key),
constraint company_module_settings_module_key_check CHECK ((module_key = ANY (ARRAY['qualifications'::text, 'documents'::text, 'attendance'::text, 'sites'::text, 'chat'::text, 'notes'::text, 'albums'::text, 'invoices'::text, 'line_bridge'::text, 'vehicle_routes'::text]))));
alter table company_module_settings enable row level security;grant select,insert,update,maintain on company_module_settings to authenticated;grant select on company_members to authenticated;
create table private.account_deletion_access_restrictions(user_id uuid);create table workers(company_id uuid,user_id uuid,status text);
create table member_feature_permissions(company_id uuid,user_id uuid,can_manage_payroll boolean);
create table payroll_access(company_id uuid,user_id uuid,can_view boolean,can_edit boolean);
create table payroll_approvers(company_id uuid,user_id uuid,position int);
create table private.professional_invites(company_id uuid,claimed_by uuid,status text,payroll_access text);
create table app_notifications(id uuid primary key default gen_random_uuid(),company_id uuid,recipient_user_id uuid,kind text,title text,body text,action_key text,action_id uuid,read_at timestamptz);
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create function private.account_access_allowed() returns boolean language sql as $$select current_setting('test.allowed',true)='true'$$;
create function private.payroll_approver_ids(cid uuid) returns uuid[] language sql as $$select coalesce(array_agg(user_id),'{}'::uuid[]) from public.payroll_approvers where company_id=cid$$;
create function private.enqueue_notification(c uuid,u uuid,k text,t text,b text,a text,i uuid) returns uuid language plpgsql as $$declare n uuid;begin insert into public.app_notifications(company_id,recipient_user_id,kind,title,body,action_key,action_id) values(c,u,k,t,b,a,i) returning id into n;return n;end$$;
grant usage on schema private,auth to authenticated;`);
await db.exec(await readFile(process.env.REMINDER_MODULE_POLICIES||new URL('module_policies.sql',import.meta.url),'utf8'));
await db.exec(await readFile(process.env.REMINDER_PERMISSION_BASELINE||new URL('permission_baseline.sql',import.meta.url),'utf8'));
eq(await scalar("select md5(pg_get_constraintdef(oid)) from pg_constraint where conname='company_module_settings_module_key_check'"),'7ecc05d1fbddecb5564b3183346098d2');
const before=await scalar("select jsonb_build_array(relacl::text,(select jsonb_agg(jsonb_build_array(polname,polcmd,polpermissive,pg_get_expr(polqual,polrelid),pg_get_expr(polwithcheck,polrelid)) order by polname) from pg_policy where polrelid='public.company_module_settings'::regclass)) from pg_class where oid='company_module_settings'::regclass");
for(const [grant,revoke] of [
 ['alter default privileges in schema private grant select on tables to unexpected_grantee','alter default privileges in schema private revoke select on tables from unexpected_grantee'],
 ['alter default privileges in schema private grant execute on functions to unexpected_grantee','alter default privileges in schema private revoke execute on functions from unexpected_grantee'],
 ['alter default privileges in schema public grant execute on functions to unexpected_grantee','alter default privileges in schema public revoke execute on functions from unexpected_grantee']]){
 await db.exec(grant);await assert.rejects(()=>db.exec(sql),/unexpected reminder/);assertions++;await db.exec('rollback');
 eq(await scalar("select to_regclass('private.resident_tax_reminder_receipts') is null"),true);await db.exec(revoke);
}
await db.exec(`begin;alter table company_module_settings drop constraint company_module_settings_module_key_check;alter table company_module_settings add constraint company_module_settings_module_key_check check(module_key<>'unknown')`);
await assert.rejects(()=>db.exec(sql),/CHECK drift/);assertions++;await db.exec('rollback');
await db.exec("create or replace function private.payroll_allowed(cid uuid,capability text) returns boolean language sql as $$select true$$");
await assert.rejects(()=>db.exec(sql),/permission source drift/);assertions++;await db.exec('rollback');
await db.exec(await readFile(process.env.REMINDER_PERMISSION_BASELINE||new URL('permission_baseline.sql',import.meta.url),'utf8'));
await db.exec('begin;drop policy \"owners and admins can update module settings\" on company_module_settings');
await assert.rejects(()=>db.exec(sql),/RLS drift/);assertions++;await db.exec('rollback');
await db.exec('begin;alter table company_module_settings disable row level security');
await assert.rejects(()=>db.exec(sql),/RLS state changed/);assertions++;await db.exec('rollback');
await db.exec('alter default privileges in schema public grant execute on functions to anon,authenticated,service_role');
await db.exec(sql);
eq(await scalar("select jsonb_build_array(relacl::text,(select jsonb_agg(jsonb_build_array(polname,polcmd,polpermissive,pg_get_expr(polqual,polrelid),pg_get_expr(polwithcheck,polrelid)) order by polname) from pg_policy where polrelid='public.company_module_settings'::regclass)) from pg_class where oid='company_module_settings'::regclass"),before);
for(const role of ['anon','service_role','authenticated']){
 eq(await scalar("select has_function_privilege($1,'public.read_resident_tax_reminder_settings(uuid)','EXECUTE')",[role]),role==='authenticated');
 eq(await scalar("select has_function_privilege($1,'private.enqueue_resident_tax_cutover_reminders(timestamptz,boolean)','EXECUTE')",[role]),false);
}
await db.exec(`insert into companies values('${company}'),('${otherCompany}');`);
for(let n=1;n<=9;n++) await q('insert into auth.users(id) values($1)',[id(n)]);
for(const [user,role] of [[owner,'owner'],[viewer,'viewer'],[employee,'employee'],[stale,'viewer'],[banned,'admin'],[deleted,'admin'],[restricted,'admin'],[manager,'manager']]) await q('insert into company_members values($1,$2,$3,now())',[company,user,role]);
await q('insert into company_members values($1,$2,\'owner\',now())',[otherCompany,outsider]);
await q('insert into payroll_access values($1,$2,true,false),($1,$3,true,false)',[company,viewer,stale]);
await q('insert into workers values($1,$2,\'inactive\')',[company,stale]);
await q('update auth.users set banned_until=now()+interval \'1day\' where id=$1',[banned]);
await q('update auth.users set deleted_at=now() where id=$1',[deleted]);
await q('insert into private.account_deletion_access_restrictions values($1)',[restricted]);
await q('insert into company_module_settings values($1,\'chat\',true,$2,now())',[company,owner]);
// Direct REST-equivalent paths retain the existing production RLS boundary.
for(const user of [viewer,manager]){await as(user);await deny('insert into company_module_settings values($1,\'resident_tax_reminders\',true,$2,now())',[company,user]);}
await as(owner);await q('insert into company_module_settings values($1,\'resident_tax_reminders\',false,$2,now())',[company,owner]);
for(const user of [viewer,manager]){await as(user);eq((await q('update company_module_settings set is_enabled=true,updated_by=$2 where company_id=$1 and module_key=\'resident_tax_reminders\' returning module_key',[company,user])).length,0);}
await as(owner);await deny('insert into company_module_settings values($1,\'resident_tax_reminders\',true,$2,now())',[otherCompany,owner]);
eq((await q('update company_module_settings set is_enabled=true,updated_by=$2 where company_id=$1 and module_key=\'resident_tax_reminders\' returning module_key',[company,owner])).length,1);
await db.exec("set test.allowed='false'");eq((await q('update company_module_settings set is_enabled=false where company_id=$1 returning module_key',[company])).length,0);
await db.exec("reset role;delete from company_module_settings where module_key='resident_tax_reminders'");
await as(owner);let settings=await scalar(read,[company]);eq(settings.enabled,false);eq(settings.can_edit,true);
await deny(read,[otherCompany]);await deny('select private.enqueue_resident_tax_cutover_reminders()');
await db.exec('reset role');eq((await scalar(dispatch,['2026-04-30T14:59:59Z',true])).due,false);
eq((await scalar(dispatch,['2026-04-30T15:00:00Z',true])).delivered,0);
await as(owner);settings=await scalar(save,[company,true,null]);eq(settings.enabled,true);
await deny(save,[company,false,null]);
await as(viewer);eq((await scalar(read,[company])).can_edit,false);await deny(save,[company,false,settings.updated_at]);
for(const user of [employee,stale,banned,deleted,restricted,manager]){await as(user);await deny(read,[company]);}
await as(owner);await db.exec("set test.allowed='false'");await deny(read,[company]);
await db.exec('reset role');let preview=await scalar(dispatch,['2026-05-01T00:00:00Z',false]);eq(preview.delivered,0);eq(preview.enabled_recipients,2);
eq(await scalar('select count(*)::int from app_notifications'),0);
eq((await scalar(dispatch,['2026-05-01T00:00:00Z',true])).delivered,2);
eq((await scalar(dispatch,['2026-05-01T00:00:00Z',true])).delivered,0);
eq(await scalar('select bool_and(body not like \'%円%\' and body like \'%一括更新%\') from app_notifications'),true);
let notification=await scalar('select id from app_notifications where recipient_user_id=$1',[owner]);
await as(owner);let target=await scalar('select public.resident_tax_reminder_target($1)',[notification]);eq(target.complete,false);eq(target.tax_year,2026);
await as(viewer);await deny('select public.resident_tax_reminder_target($1)',[notification]);
await db.exec('reset role');await db.exec(`create schema resident_tax_annual_private;create table resident_tax_annual_private.fixture_complete(company_id uuid,year int,complete boolean);create function resident_tax_annual_private.year_complete(cid uuid,p_tax_year integer) returns boolean language sql security definer set search_path='' as $$select coalesce((select complete from resident_tax_annual_private.fixture_complete where company_id=cid and year=p_tax_year),false)$$;revoke all on function resident_tax_annual_private.year_complete(uuid,integer) from public;`);
await db.exec('alter function resident_tax_annual_private.year_complete(uuid,integer) set search_path=public');
await as(owner);await deny('select public.resident_tax_reminder_target($1)',[notification]);
await db.exec("reset role;alter function resident_tax_annual_private.year_complete(uuid,integer) set search_path=''");
await q('insert into resident_tax_annual_private.fixture_complete values($1,2026,true)',[company]);
await as(owner);eq((await scalar('select public.resident_tax_reminder_target($1)',[notification])).complete,true);
await db.exec('reset role');eq((await scalar(dispatch,['2026-05-25T00:00:00Z',true])).delivered,0);
await db.exec('update resident_tax_annual_private.fixture_complete set complete=false');
await as(owner);eq((await scalar('select public.resident_tax_reminder_target($1)',[notification])).complete,false);
await db.exec('reset role');eq((await scalar(dispatch,['2026-05-25T00:00:00Z',true])).delivered,2);
await q('delete from app_notifications where id=$1',[notification]);
eq((await scalar(dispatch,['2026-05-01T00:00:00Z',true])).delivered,0);
eq((await scalar(dispatch,['2027-05-01T00:00:00Z',true])).delivered,2);
notification=await scalar('select notification_id from private.resident_tax_reminder_receipts where recipient_user_id=$1 and tax_year=2027',[owner]);
await q('update company_members set created_at=created_at+interval \'1second\' where company_id=$1 and user_id=$2',[company,owner]);
await as(owner);await deny('select public.resident_tax_reminder_target($1)',[notification]);
await db.exec('reset role');eq((await scalar(dispatch,['2027-05-01T00:00:00Z',true])).delivered,0);
eq(await scalar("select is_enabled from company_module_settings where module_key='chat'"),true);
await deny(dispatch,[null,true]);await deny(dispatch,['infinity',true]);
// Native-only regression: scheduler pauses after module lock, admin toggles
// concurrently, then scheduler continues into company-FK receipt insertion.
// Before the company-first fix this creates the actual two-session deadlock.
if(process.env.SKO_RESIDENT_REMINDER_FIXTURE_URL){
 const {resident_reminderFixtureUrl}=await import('./security/resident_reminder_fixture_guard.mjs');
 const {default:pg}=await import('./security/fixture_dependencies/node_modules/pg/lib/index.js');
 const connectionString=resident_reminderFixtureUrl(process.env.SKO_RESIDENT_REMINDER_FIXTURE_URL);
 const sender=new pg.Client({connectionString}),admin=new pg.Client({connectionString});
 let sendPending,savePending;
 const barrier='900000000000001';
 await db.exec(`update company_module_settings set is_enabled=true where module_key='resident_tax_reminders';
 create function private.resident_reminder_fixture_pause() returns trigger language plpgsql as $$begin perform pg_advisory_xact_lock(900000000000001);return new;end$$;
 create trigger resident_reminder_fixture_pause before insert on private.resident_tax_reminder_receipts for each row execute function private.resident_reminder_fixture_pause();`);
 await db.query('select pg_advisory_lock($1::bigint)',[barrier]);
 try{
  await sender.connect();await admin.connect();
  for(const peer of [sender,admin])await peer.query("set statement_timeout='5s';set lock_timeout='4s'");
  await admin.query("select set_config('test.uid',$1,false),set_config('test.allowed','true',false)",[owner]);await admin.query('set role authenticated');
  const senderPid=(await sender.query('select pg_backend_pid() pid')).rows[0].pid;
  const adminPid=(await admin.query('select pg_backend_pid() pid')).rows[0].pid;
  const stamp=await scalar("select to_jsonb(updated_at) from company_module_settings where company_id=$1 and module_key='resident_tax_reminders'",[company]);
  sendPending=sender.query(dispatch,['2030-05-01T00:00:00Z',true]).then(value=>({value}),error=>({error}));
  let paused=false;
  for(let attempt=0;attempt<100;attempt++){
   if(await scalar("select exists(select 1 from pg_locks where pid=$1 and locktype='advisory' and not granted)",[senderPid])){paused=true;break;}
   await new Promise(resolve=>setTimeout(resolve,20));
  }
  eq(paused,true);
  savePending=admin.query(save,[company,false,stamp]).then(value=>({value}),error=>({error}));
  let blocked=false;
  for(let attempt=0;attempt<100;attempt++){
   if(await scalar('select $2::integer=any(pg_blocking_pids($1::integer))',[adminPid,senderPid])){blocked=true;break;}
   await new Promise(resolve=>setTimeout(resolve,20));
  }
  eq(blocked,true);
  await db.query('select pg_advisory_unlock($1::bigint)',[barrier]);
  const [sent,saved]=await Promise.all([sendPending,savePending]);
  eq(sent.error?.message,undefined);eq(saved.error?.message,undefined);
  eq(Object.values(sent.value.rows[0])[0].delivered,2);
  eq(Object.values(saved.value.rows[0])[0].enabled,false);
  eq(await scalar('select count(*)::int from private.resident_tax_reminder_receipts where company_id=$1 and tax_year=2030',[company]),2);
 }finally{
  await db.query('select pg_advisory_unlock($1::bigint)',[barrier]);
  await Promise.allSettled([sendPending,savePending].filter(Boolean));
  await sender.end();await admin.end();
  await db.exec('drop trigger resident_reminder_fixture_pause on private.resident_tax_reminder_receipts;drop function private.resident_reminder_fixture_pause()');
 }
}
await db.exec("update company_module_settings set is_enabled=false where module_key='resident_tax_reminders'");
await db.exec(`create schema cron;create table cron.job(jobid bigint primary key,jobname text,schedule text,active boolean,command text);
create function cron.alter_job(job_id bigint,command text) returns void language sql as $$update cron.job set command=$2 where jobid=$1$$;
create table public.fixture_payroll_runs(n int);
create function private.ensure_monthly_payroll_drafts() returns void language sql as $$insert into public.fixture_payroll_runs values(1)$$;
create function private.enqueue_payroll_confirmation_notifications() returns void language sql as $$insert into public.fixture_payroll_runs values(2)$$;
insert into cron.job values(1,'payroll-confirmation-daily-jst','0 15 * * *',true,'select private.ensure_monthly_payroll_drafts(); select private.enqueue_payroll_confirmation_notifications();');`);
const scheduler=await readFile(process.env.REMINDER_SCHEDULER||new URL('scheduler.sql.review-only',import.meta.url),'utf8');
const restore=await readFile(process.env.REMINDER_RESTORE||new URL('scheduler-restore.sql.review-only',import.meta.url),'utf8');
await db.exec(scheduler);const appended=await scalar('select command from cron.job');
await db.exec(scheduler);eq(await scalar('select command from cron.job'),appended);
await db.exec(restore);eq(await scalar('select md5(command) from cron.job'),'0c29cad612ce5304210faafb8a46ba26');
await db.exec("update cron.job set command='select 42'");await assert.rejects(()=>db.exec(scheduler),/command changed/);assertions++;await db.exec('rollback');eq(await scalar('select command from cron.job'),'select 42');
await db.exec("update cron.job set command='select private.ensure_monthly_payroll_drafts(); select private.enqueue_payroll_confirmation_notifications();'");
await db.exec(scheduler);
await db.exec(`create or replace function private.enqueue_resident_tax_cutover_reminders(p_now timestamptz default clock_timestamp(),p_deliver boolean default false) returns jsonb language plpgsql as $$begin insert into public.fixture_payroll_runs values(3);raise exception 'fixture failure';end$$;`);
await db.exec(await scalar('select command from cron.job'));eq((await q('select n from public.fixture_payroll_runs order by n')).map(x=>x.n),[1,2]);
for(const role of ['anon','authenticated','service_role']){
 await db.exec('set role '+role);await deny('select * from private.resident_tax_reminder_receipts');await db.exec('reset role');
}
console.log(`resident-tax reminder candidate: ${assertions} assertions PASS (no production delivery)`);
}finally{await db.close();}
