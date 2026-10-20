import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createHash} from 'node:crypto';
if(!process.env.SKO_PGLITE_MODULE)throw Error('Pinned PGlite 0.3.14 entrypoint required');
const {PGlite}=await import(process.env.SKO_PGLITE_MODULE),db=new PGlite();
const root=new URL('../../',import.meta.url),read=p=>fs.readFileSync(new URL(p,root),'utf8');
const id=n=>`30000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const company=id(1),owner=id(2),actor=id(3),worker=id(4),sid=id(5),ownerSid=id(6),outsider=id(7);
const token='bc'.repeat(32),hash=createHash('sha256').update(token).digest('hex');
const signature='public.approve_employee_onboarding(uuid)';
const patch=read('docs/candidates/employee_authenticated_invite_v2_approval_gate.sql.review-only');
const q=(s,a=[])=>db.query(s,a);let checks=0,receipt;
const reset=()=>db.exec('reset role');
async function login(uid,session=ownerSid){await reset();await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[uid,JSON.stringify({sub:uid,session_id:session})]);await db.exec('set role authenticated');}
const approve=()=>q('select public.approve_employee_onboarding($1)',[receipt.invite_id]);
const deny=async f=>{await assert.rejects(f,e=>['P0001','42501','55000'].includes(e.code));checks++;};
async function apply(){try{await db.exec(patch);}catch(e){await db.exec('rollback');throw e;}}
const meta=async()=>(await q(`select oid,prosrc,proacl::text acl,proowner,proconfig,prosecdef from pg_proc where oid='${signature}'::regprocedure`)).rows[0];
async function unchanged(){await reset();assert.equal((await q('select count(*)::int n from public.company_members where user_id=$1',[actor])).rows[0].n,0);assert.equal((await q('select user_id from public.workers where id=$1',[worker])).rows[0].user_id,null);assert.equal((await q('select status from public.employee_registration_invites where id=$1',[receipt.invite_id])).rows[0].status,'approval_pending');checks++;}
try{
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema private;
 create table auth.users(id uuid primary key,encrypted_password text,banned_until timestamptz,deleted_at timestamptz,is_anonymous boolean default false);
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create table private.account_deletion_access_restrictions(user_id uuid primary key);
 create function private.account_access_allowed() returns boolean language sql as $body$
 select auth.uid() is not null and not exists(
  select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())
$body$;
 create type public.app_role as enum('owner','admin','viewer','manager');
 create table public.companies(id uuid primary key);
 create table public.workers(id uuid primary key,company_id uuid,name text,phone text,affiliation text,user_id uuid,status text,role text,updated_at timestamptz);
 create table public.company_members(company_id uuid,user_id uuid,role public.app_role,primary key(company_id,user_id));
 create table public.company_approval_assignees(company_id uuid,user_id uuid,created_by uuid,primary key(company_id,user_id));
 create table public.user_profiles(user_id uuid primary key,display_name text,phone text,updated_at timestamptz);
 create table public.app_notifications(company_id uuid,recipient_user_id uuid,action_key text,action_id uuid,read_at timestamptz);
 create table private.fixture_notifications(id uuid default gen_random_uuid(),recipient uuid);
 create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language sql as $$insert into private.fixture_notifications(recipient) values($2) returning id$$;
 grant usage on schema public,auth,private to authenticated;`);
 await db.exec(read('tool/security/employee_invite_foundation.main.fixture.sql'));
 await db.exec(`alter table public.employee_registration_invites add column identity_verified_at timestamptz,add column approved_by uuid,add column approved_at timestamptz,add column requested_role text default 'viewer',add column requested_approval_assignee boolean default false,add column replace_approval_assignee_user_id uuid;
 alter table public.employee_registration_invites add column address text,add column blood_type text,add column family_composition text,add column emergency_relation text,add column emergency_name text,add column emergency_phone text,add column emergency_address text,add column portrait_path text,add column my_number_front_path text,add column my_number_back_path text,add column submitted_at timestamptz;`);
 await db.exec(read('docs/candidates/employee_authenticated_invite_v2.sql.review-only'));
 await db.exec(read('tool/security/employee_onboarding_profile.retained.fixture.sql'));
 await db.exec('revoke all on function public.save_employee_onboarding_profile(text,text,text,text,text,text,text,text,text,text) from public,anon,authenticated,service_role;grant execute on function public.save_employee_onboarding_profile(text,text,text,text,text,text,text,text,text,text) to authenticated,service_role;');
 await db.exec(read('docs/candidates/employee_authenticated_invite_v2_profile_gate.sql.review-only'));
 await db.exec(read('tool/security/employee_onboarding_approval.captured.fixture.sql'));
 await db.exec(`revoke all on function ${signature} from public,anon,authenticated,service_role;grant execute on function ${signature} to authenticated,service_role;`);
 await q('insert into auth.users(id,encrypted_password) values($1,$4),($2,$4),($3,$4)',[owner,actor,outsider,'unchanged-password-hash']);
 await q('insert into auth.sessions values($1,$2,null),($3,$4,null),($5,$6,null)',[sid,actor,ownerSid,owner,id(8),outsider]);
 await q('insert into public.companies values($1)',[company]);await q("insert into public.company_members values($1,$2,'owner')",[company,owner]);
 await q("insert into public.workers(id,company_id,name,phone,affiliation,status) values($1,$2,'Employee','09012345678','employee','active')",[worker,company]);
 await q('insert into private.employee_authenticated_invite_v2_rollout values($1,true)',[company]);
 await login(owner);const issued=(await q('select public.issue_employee_authenticated_invite_v2($1,$2,$3,$4) value',[company,worker,id(9),hash])).rows[0].value;
 await login(actor,sid);receipt=(await q('select public.redeem_employee_authenticated_invite_v2($1,$2,$3,$4,true) value',[issued.invite_id,issued.generation,token,id(10)])).rows[0].value;
 await q('select public.save_employee_onboarding_profile($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',['address','unknown','family','relation','contact','phone','address',null,null,null]);
 await reset();const before=await meta();await apply();const after=await meta();
 assert.deepEqual({...before,prosrc:undefined},{...after,prosrc:undefined});checks++;
 assert.equal(after.prosrc,before.prosrc.replace('  select *\n  into v_invite\n  from public.employee_registration_invites','  perform private.lock_employee_authenticated_invite_v2_for_approval(p_invite_id);\n\n  select *\n  into v_invite\n  from public.employee_registration_invites'));checks++;
 for(const [change,restore] of [
  ["update private.employee_authenticated_invite_v2 set state='cancelled'","update private.employee_authenticated_invite_v2 set state='redeemed'"],
  ["update private.employee_authenticated_invite_v2 set expires_at=now()-interval '1 second'","update private.employee_authenticated_invite_v2 set expires_at=now()+interval '1 day'"],
  ["update public.employee_registration_invites set expires_at=now()-interval '1 second'","update public.employee_registration_invites set expires_at=now()+interval '1 day'"],
  ["update private.employee_authenticated_invite_v2_rollout set enabled=false","update private.employee_authenticated_invite_v2_rollout set enabled=true"],
  ["update public.workers set name='changed'","update public.workers set name='Employee'"],
  ["update public.employee_registration_invites set requested_role='manager'","update public.employee_registration_invites set requested_role='viewer'"],
  [`update auth.sessions set not_after=now()-interval '1 second' where id='${sid}'`,`update auth.sessions set not_after=null where id='${sid}'`],
  [`delete from auth.sessions where id='${sid}'`,`insert into auth.sessions values('${sid}','${actor}',null)`],
  [`update auth.users set banned_until=now()+interval '1 day' where id='${actor}'`,`update auth.users set banned_until=null where id='${actor}'`],
  [`update auth.users set deleted_at=now() where id='${actor}'`,`update auth.users set deleted_at=null where id='${actor}'`],
  [`update auth.users set is_anonymous=true where id='${actor}'`,`update auth.users set is_anonymous=false where id='${actor}'`],
  [`insert into private.account_deletion_access_restrictions values('${actor}')`,`delete from private.account_deletion_access_restrictions where user_id='${actor}'`],
 ]){await reset();await db.exec(change);await login(owner);await deny(approve);await unchanged();await db.exec(restore);}
 await login(owner,id(11));await deny(approve);await unchanged();
 await login(outsider,id(8));await deny(approve);await unchanged();
 await login(actor,sid);await deny(approve);await unchanged();
 await db.exec(`insert into public.company_members values('${company}','${actor}','admin')`);await login(owner);await deny(approve);await reset();await db.exec(`delete from public.company_members where user_id='${actor}'`);await unchanged();
 await q('insert into public.companies values($1)',[id(25)]);await q("insert into public.company_members values($1,$2,'owner')",[id(25),actor]);
 await login(owner);await deny(approve);await reset();assert.equal((await q('select role from public.company_members where company_id=$1 and user_id=$2',[id(25),actor])).rows[0].role,'owner');checks++;
 await q('delete from public.company_members where company_id=$1 and user_id=$2',[id(25),actor]);await unchanged();
 const notificationDefinition=(await q("select pg_get_functiondef('private.enqueue_notification(uuid,uuid,text,text,text,text,uuid)'::regprocedure) definition")).rows[0].definition;
 await db.exec("create or replace function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language plpgsql as $$begin raise exception 'fixture notification failure';end$$");
 await login(owner);await deny(approve);await unchanged();await db.exec(notificationDefinition);
 await login(owner);await approve();await reset();
 assert.equal((await q('select role from public.company_members where company_id=$1 and user_id=$2',[company,actor])).rows[0].role,'viewer');assert.equal((await q('select user_id from public.workers where id=$1',[worker])).rows[0].user_id,actor);checks++;
 const done=(await q('select status,password_changed_at,identity_verified_at from public.employee_registration_invites where id=$1',[receipt.invite_id])).rows[0];assert.deepEqual(done,{status:'approved',password_changed_at:null,identity_verified_at:null});checks++;
 assert.equal((await q('select count(distinct encrypted_password)::int n from auth.users')).rows[0].n,1);checks++;
 await login(owner);await deny(approve);await reset();
 // Ordinary legacy path remains supported by the unchanged captured approval.
 await q('insert into auth.users(id) values($1)',[id(20)]);await q("insert into public.workers(id,company_id,name,phone,affiliation,status) values($1,$2,'Legacy','09000000001','employee','active')",[id(21),company]);
 const legacy=(await q("insert into public.employee_registration_invites(company_id,worker_id,auth_user_id,name,phone_e164,status,created_by,password_changed_at) values($1,$2,$3,'Legacy','+819000000001','approval_pending',$4,now()) returning id",[company,id(21),id(20),owner])).rows[0].id;
 await login(owner);await q('select public.approve_employee_onboarding($1)',[legacy]);await reset();assert.equal((await q('select status from public.employee_registration_invites where id=$1',[legacy])).rows[0].status,'approved');checks++;
 await deny(apply);
 assert.equal((await q("select has_function_privilege('authenticated','private.lock_employee_authenticated_invite_v2_for_approval(uuid)','execute') allowed")).rows[0].allowed,false);checks++;
 // New install must reject inherited grants and source drift atomically.
 await db.exec(read('tool/security/employee_onboarding_approval.captured.fixture.sql'));
 await db.exec('drop function private.lock_employee_authenticated_invite_v2_for_approval(uuid)');
 const original=await meta();
 await db.exec('create role unexpected_fixture_reader;alter default privileges grant execute on functions to unexpected_fixture_reader');
 await deny(apply);assert.deepEqual(await meta(),original);assert.equal((await q("select to_regprocedure('private.lock_employee_authenticated_invite_v2_for_approval(uuid)') value")).rows[0].value,null);checks++;
 await db.exec('alter default privileges revoke execute on functions from unexpected_fixture_reader');
 await db.exec(read('tool/security/employee_onboarding_approval.captured.fixture.sql').replace('employee cannot approve own onboarding','drifted self approval condition'));
 await deny(apply);
 await db.exec(read('tool/security/employee_onboarding_approval.captured.fixture.sql'));
 await db.exec('grant execute on function public.approve_employee_onboarding(uuid) to anon');await deny(apply);
 console.log(JSON.stringify({result:'PASS authenticated invite approval gate',checks,actual_captured_approval_executed:true,legacy_approval_preserved:true,oid_owner_acl_preserved:true,live_employee_and_reviewer_sessions:true,password_markers_not_fabricated:true,actual_http_jwt:false,concurrent_connections:false,storage_proven:false,production_changes:false}));
}catch(e){console.error(JSON.stringify({result:'FAIL',code:e.code,message:e.message}));process.exitCode=1;}finally{await db.close();}
