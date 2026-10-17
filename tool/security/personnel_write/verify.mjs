// Disposable synthetic database only. Definitions captured from live catalogs;
// no production credentials, records, calls or deployment are used by this test.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';
import crypto from 'node:crypto';
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../../..');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const db=new PGlite();
const e=JSON.parse(fs.readFileSync(path.join(here,'../personnel_rls/live_policy_fixture_20261016.json'),'utf8'));
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const C=id(1),F=id(2),W=id(3),WF=id(4),WR=id(5);
const actors={managerOff:id(11),managerOn:id(12),owner:id(13),admin:id(14),viewer:id(15),self:id(16),employee:id(17),outsider:id(18),deleted:id(19),retiredSelf:id(20)};
await db.exec(`create role authenticated;create role anon;create role service_role;create schema auth;create schema private;
create function auth.uid() returns uuid language sql stable as $$select coalesce(nullif(current_setting('fixture.actor',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
create table private.account_deletion_access_restrictions(user_id uuid);
-- Synthetic identity/provider/master sentinels: no production IDs are used.
create table auth.users(id uuid primary key);
create table auth.identities(id uuid primary key,user_id uuid,provider text,provider_id text);
create table private.master_admins(user_id uuid primary key,enabled boolean);
create type public.app_role as enum ('owner','admin','manager','employee','viewer');
create table company_members(company_id uuid,user_id uuid,role public.app_role);
create table member_feature_permissions(company_id uuid,user_id uuid,can_view_invoices boolean default false,can_manage_invoices boolean default false,can_manage_payroll boolean default false,can_manage_people boolean default false,can_manage_attendance boolean default false,can_approve_daily_report_edits boolean default false,can_manage_partner_chat boolean default false);
create table workers(id uuid,company_id uuid,user_id uuid);
create table worker_personnel_profiles(worker_id uuid,company_id uuid,address text);
create table worker_family_members(id uuid,worker_id uuid,company_id uuid,name text);
create function private.has_company_role(uuid,public.app_role[]) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.company_members where company_id=$1 and user_id=auth.uid() and role=any($2))$$;
grant usage on schema public,private,auth to authenticated,anon;
grant select on company_members,member_feature_permissions,worker_personnel_profiles,worker_family_members to authenticated;
grant select(id,company_id,user_id) on workers to authenticated;`);
for(const f of e.functions)await db.exec(f);
await db.exec('revoke all on function private.personnel_view_allowed(uuid) from public,anon;grant execute on function private.personnel_view_allowed(uuid) to authenticated');
// Columns used by the ACTUAL canonical read RPC; all values remain synthetic.
await db.exec(`alter table workers add column name text default 'synthetic worker',add column affiliation text default 'employee',add column role text,add column phone text,add column employee_number text,add column department text,add column hire_date date,add column status text default 'active',add column created_at timestamptz default now(),add column updated_at timestamptz default now();
alter table worker_personnel_profiles add column blood_type text,add column emergency_name text,add column emergency_relation text,add column emergency_phone text,add column emergency_address text,add column family_composition text,add column updated_at timestamptz default now();
alter table worker_family_members add column relation text,add column birth_date date,add column is_dependent boolean;`);
await db.exec('grant select(status) on workers to authenticated');
await db.exec(fs.readFileSync(path.join(here,'../personnel_rls/canonical_read_rpc_fixture.sql'),'utf8'));
for(const t of ['company_members','member_feature_permissions','workers','worker_personnel_profiles','worker_family_members'])await db.exec(`alter table ${t} enable row level security`);
for(const p of e.policies){let q=`create policy "${p.policyname}" on ${p.tablename} as ${p.permissive} for ${p.cmd} to ${p.roles.map(r=>'"'+r.replaceAll('"','""')+'"').join(',')}`;if(p.qual)q+=` using (${p.qual})`;if(p.with_check)q+=` with check (${p.with_check})`;await db.exec(q);}
for(const [key,actor]of Object.entries(actors)){const role=key.startsWith('manager')?'manager':key==='deleted'?'owner':['owner','admin','viewer'].includes(key)?key:'employee';await db.query('insert into company_members values($1,$2,$3)',[key==='outsider'?F:C,actor,role]);await db.query('insert into member_feature_permissions(company_id,user_id,can_manage_people)values($1,$2,$3)',[C,actor,key==='managerOn']);}
for(const [key,uid]of Object.entries(actors)){await db.query('insert into auth.users values($1)',[uid]);await db.query('insert into auth.identities values($1,$2,$3,$4)',[id(100+Number(uid.slice(-2))),uid,'synthetic-fixture-provider','synthetic-'+key]);}
await db.query('insert into private.master_admins values($1,true)',[actors.owner]);
await db.query('insert into private.account_deletion_access_restrictions values($1)',[actors.deleted]);
await db.query('insert into workers(id,company_id,user_id) values($1,$2,$3),($4,$5,$6)',[W,C,actors.self,WF,F,actors.outsider]);
await db.query('insert into worker_personnel_profiles(worker_id,company_id,address) values($1,$2,$3),($4,$5,$6)',[W,C,'synthetic own-company address',WF,F,'synthetic foreign address']);
await db.query('insert into worker_family_members(id,worker_id,company_id,name) values($1,$2,$3,$4),($5,$6,$7,$8)',[id(30),W,C,'synthetic family',id(31),WF,F,'foreign family']);
await db.query("insert into workers(id,company_id,user_id,status)values($1,$2,$3,'inactive')",[WR,C,actors.retiredSelf]);
await db.query('insert into worker_personnel_profiles(worker_id,company_id,address)values($1,$2,$3)',[WR,C,'synthetic retired address']);
await db.query('insert into worker_family_members(id,worker_id,company_id,name)values($1,$2,$3,$4)',[id(32),WR,C,'synthetic retired family']);
async function actor(uid){await db.exec('reset role');await db.query("select set_config('fixture.actor',$1,false)",[uid??'']);await db.exec('set role authenticated');}
async function ownCounts(){return [(await db.query('select address from worker_personnel_profiles where company_id=$1',[C])).rows.length,(await db.query('select name from worker_family_members where company_id=$1',[C])).rows.length];}
// Actual live legacy endpoint, including the public ACL and unmodified private ACL.
const legacy=JSON.parse(fs.readFileSync(path.join(here,'../personnel_rls/legacy_read_rpc_fixture.json'),'utf8'));
const originalPrivate=legacy.find(x=>x.schema==='private').definition;
const originalPublic=legacy.find(x=>x.schema==='public').definition;
await db.exec(originalPrivate);await db.exec(originalPublic);
await db.exec('revoke all on function public.employee_personnel_rows() from public,anon;grant execute on function public.employee_personnel_rows() to authenticated,service_role');
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261016104441_personnel_direct_read_permission_guard.sql'),'utf8'));
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261016113335_personnel_legacy_read_permission_guard.sql'),'utf8'));
await db.exec(`alter table worker_personnel_profiles add primary key(worker_id),add column created_by uuid,add column updated_by uuid;
alter table worker_family_members alter column id set default gen_random_uuid(),add column created_by uuid,add column updated_by uuid;
update worker_family_members set relation='child',birth_date='2020-01-01',is_dependent=false;
alter table worker_family_members add primary key(id),alter column name set not null,alter column relation set not null,alter column is_dependent set not null;
create table worker_personnel_approvers(company_id uuid,user_id uuid,primary key(company_id,user_id));
create table worker_personnel_change_requests(id uuid primary key default gen_random_uuid(),company_id uuid,worker_id uuid,requested_by uuid,proposed jsonb,required_approvals int,status text default 'pending',resolved_at timestamptz);
create table worker_personnel_change_approvals(request_id uuid,approver_user_id uuid,decision text,primary key(request_id,approver_user_id));
create table app_notifications(id uuid primary key default gen_random_uuid(),company_id uuid,recipient_user_id uuid,kind text,title text,body text,action_key text,action_id uuid);
alter table worker_personnel_approvers enable row level security;alter table worker_personnel_change_requests enable row level security;alter table worker_personnel_change_approvals enable row level security;alter table app_notifications enable row level security;`);
const writes=JSON.parse(fs.readFileSync(path.join(here,'live_function_fixture.json'),'utf8'));
for(const name of ['account_deletion_barrier_key','check_account_access','can_edit_worker_personnel','worker_personnel_payload','apply_worker_personnel_payload','is_worker_personnel_approver','save_worker_personnel_profile','decide_worker_personnel_change'])await db.exec(writes.find(x=>x.name===name).definition);
await db.exec(`revoke all on function public.save_worker_personnel_profile(uuid,jsonb),public.decide_worker_personnel_change(uuid,boolean) from public,anon;grant execute on function public.save_worker_personnel_profile(uuid,jsonb),public.decide_worker_personnel_change(uuid,boolean) to authenticated,service_role;
revoke all on function private.account_deletion_barrier_key(uuid) from public,anon;grant execute on function private.account_deletion_barrier_key(uuid) to authenticated,service_role;
revoke all on function private.check_account_access() from public;grant execute on function private.check_account_access() to anon,authenticated,service_role;`);
await db.query('insert into worker_personnel_approvers values($1,$2)',[C,actors.owner]);
const fresh=id(55);await db.query('insert into workers(id,company_id,user_id,name)values($1,$2,$3,$4)',[fresh,C,actors.employee,'synthetic untouched target']);
await db.exec(`create function public.fixture_account_hook_status() returns jsonb language sql stable set search_path='' as $$select jsonb_build_object('hook',current_setting('sko.account_access_barrier_ran',true),'actor_present',auth.uid() is not null)$$;revoke all on function public.fixture_account_hook_status() from public,anon;grant execute on function public.fixture_account_hook_status() to authenticated;`);
const businessTables=['workers','worker_personnel_profiles','worker_family_members','worker_personnel_change_requests','worker_personnel_change_approvals','app_notifications'];
const protectedTables=['company_members','member_feature_permissions','private.account_deletion_access_restrictions','auth.users','auth.identities','private.master_admins','worker_personnel_approvers'];
async function capsule(){
 const rows={};for(const t of [...businessTables,...protectedTables])rows[t]=(await db.query(`select to_jsonb(t) value from ${t} t order by to_jsonb(t)::text`)).rows.map(x=>x.value);
 const functions=(await db.query("select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args,pg_get_userbyid(p.proowner) owner,p.proacl::text,p.proconfig,p.prosecdef,p.provolatile,p.prorettype::regtype::text,case when n.nspname='private' and p.proname='can_edit_worker_personnel' then null else pg_get_functiondef(p.oid) end definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','auth') and p.prokind='f' order by n.nspname,p.proname,args")).rows;
 const policies=(await db.query("select schemaname,tablename,policyname,permissive,to_jsonb(roles) roles,cmd,qual,with_check from pg_policies where schemaname in ('public','private','auth') order by schemaname,tablename,policyname")).rows;
 const acl=(await db.query("select n.nspname,c.relname,c.relacl::text,c.relrowsecurity,c.relforcerowsecurity,a.attname,a.attacl::text from pg_class c join pg_namespace n on n.oid=c.relnamespace left join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped where n.nspname in ('public','private','auth') and c.relkind='r' order by n.nspname,c.relname,a.attnum")).rows;
 return {rows,functions,policies,acl};
}
const baseline=await capsule();
const originalPayload=(await db.query('select private.worker_personnel_payload($1) payload',[fresh])).rows[0].payload;
const malicious={...originalPayload,address:'synthetic unauthorized initial address',phone:'synthetic unauthorized phone',family_members:[{name:'synthetic family',relation:'child',birth_date:'2020-01-01',is_dependent:true}]};
await db.exec('begin');await actor(actors.managerOff);await db.query('select private.check_account_access()');
assert.equal((await db.query('select private.has_company_feature($1,$2) allowed',[C,'can_manage_people'])).rows[0].allowed,false);
const created=(await db.query('select public.save_worker_personnel_profile($1,$2::jsonb) payload',[fresh,JSON.stringify(malicious)])).rows[0].payload;assert.equal(created.status,'saved');assert.equal(created.saved_directly,true);assert.equal(created.requires_approval,false);
await db.exec('reset role');assert.equal((await db.query('select address from worker_personnel_profiles where worker_id=$1',[fresh])).rows[0].address,malicious.address);assert.equal((await db.query('select phone from workers where id=$1',[fresh])).rows[0].phone,malicious.phone);assert.equal((await db.query('select count(*)::int n from worker_family_members where worker_id=$1',[fresh])).rows[0].n,1);await db.exec('rollback');
assert.equal((await db.query('select count(*)::int n from worker_personnel_profiles where worker_id=$1',[fresh])).rows[0].n,0);assert.deepEqual((await db.query('select private.worker_personnel_payload($1) payload',[fresh])).rows[0].payload,originalPayload);
console.log(JSON.stringify({result:'REPRODUCED',scope:'isolated synthetic actual save/helper/apply and actual DataAPI pre-request function; both read fixes already applied',managerPeoplePermission:false,initialProfileStatus:created.status,savedDirectly:created.saved_directly,approvalRequired:created.requires_approval,profilePhoneFamilyWritesVerifiedInsideTransaction:true,rolledBackBusinessStateExactly:true}));
const existingPayload=(await db.query('select private.worker_personnel_payload($1) payload',[W])).rows[0].payload;
await db.exec('begin');await actor(actors.managerOff);await db.query('select private.check_account_access()');const requested=(await db.query('select public.save_worker_personnel_profile($1,$2::jsonb) payload',[W,JSON.stringify({...existingPayload,address:'synthetic unauthorized request'})])).rows[0].payload;assert.equal(requested.status,'pending');await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from worker_personnel_change_requests where worker_id=$1',[W])).rows[0].n,1);await db.exec('rollback');
console.log(JSON.stringify({result:'REPRODUCED',managerPeoplePermission:false,existingProfileStatus:requested.status,unauthorizedRequestCreatedInsideTransaction:true,rolledBack:true}));
assert.deepEqual(await capsule(),baseline,'Original-bypass proof transactions restore all business and protected identities');
const helper=writes.find(x=>x.name==='can_edit_worker_personnel').definition;
const source=async()=>(await db.query("select prosrc from pg_proc where oid='private.can_edit_worker_personnel(uuid)'::regprocedure")).rows[0].prosrc;
const oldSource=await source();
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261016120458_personnel_write_permission_guard.sql'),'utf8');
await db.exec("create or replace function private.can_edit_worker_personnel(p_worker_id uuid) returns boolean language sql stable security definer set search_path='' as $$select false$$");const changedSource=await source(),drift=await capsule();await assert.rejects(db.exec(migration),x=>x.code==='55000');await db.exec('rollback');assert.equal(await source(),changedSource);assert.deepEqual(await capsule(),drift,'Drift must never be overwritten');await db.exec(helper);assert.equal(await source(),oldSource);
await db.exec(migration);assert.deepEqual(await capsule(),baseline,'Actual migration changes only the helper source');const fixedSource=await source();
async function transactionCase(key,target,status,approve=false){
 const original=(await db.query('select private.worker_personnel_payload($1) payload',[target])).rows[0].payload;
 const data={...original,address:'synthetic proposed '+key,phone:original.phone||'synthetic phone',family_members:[{name:'synthetic child',relation:'child',birth_date:'2020-01-01',is_dependent:true}]};
 await db.exec('begin');await actor(actors[key]);await db.query('select private.check_account_access()');
 if(status==='denied'){await assert.rejects(db.query('select public.save_worker_personnel_profile($1,$2::jsonb)',[target,JSON.stringify(data)]),x=>x.code==='P0001'||x.code==='42501');await db.exec('rollback;reset role');assert.deepEqual(await capsule(),baseline,key+' denial untouched');return;}
 const result=(await db.query('select public.save_worker_personnel_profile($1,$2::jsonb) payload',[target,JSON.stringify(data)])).rows[0].payload;assert.equal(result.status,status,key);
 if(status==='pending'){await db.exec('reset role');assert.equal((await db.query('select address from worker_personnel_profiles where worker_id=$1',[target])).rows[0].address,original.address);if(approve){await actor(actors.owner);await db.query('select private.check_account_access()');const approved=(await db.query('select public.decide_worker_personnel_change($1,true) payload',[result.request_id])).rows[0].payload;assert.equal(approved.status,'approved');}}
 await db.exec('reset role');if(status==='saved'||approve)assert.equal((await db.query('select address from worker_personnel_profiles where worker_id=$1',[target])).rows[0].address,data.address);
 await db.exec('rollback;reset role');assert.deepEqual(await capsule(),baseline,key+' legitimate save/approval rollback preserves all IDs and business state');
}
for(const key of ['owner','admin','managerOn','employee'])await transactionCase(key,fresh,'saved');
for(const key of ['owner','admin'])await transactionCase(key,W,'saved');
for(const key of ['managerOn','self'])await transactionCase(key,W,'pending',true);
// A separately registered approval assignee with people-management OFF keeps
// approval authority: decide_worker_personnel_change does not call our helper.
await db.exec('begin');await db.query('insert into worker_personnel_approvers values($1,$2)',[C,actors.managerOff]);await actor(actors.managerOn);await db.query('select private.check_account_access()');const normal=(await db.query('select public.save_worker_personnel_profile($1,$2::jsonb) payload',[W,JSON.stringify({...existingPayload,address:'synthetic two-approver update'})])).rows[0].payload;assert.equal(normal.required_approvals,2);await actor(actors.owner);await db.query('select private.check_account_access()');assert.equal((await db.query('select public.decide_worker_personnel_change($1,true) payload',[normal.request_id])).rows[0].payload.status,'pending');await actor(actors.managerOff);await db.query('select private.check_account_access()');assert.equal((await db.query('select public.decide_worker_personnel_change($1,true) payload',[normal.request_id])).rows[0].payload.status,'approved');await db.exec('rollback;reset role');assert.deepEqual(await capsule(),baseline,'Registered approver roles and ordinary approval path preserved');
for(const target of [fresh,W])await transactionCase('managerOff',target,'denied');
await transactionCase('employee',W,'denied');await transactionCase('owner',WF,'denied');
await transactionCase('viewer',W,'denied');
await db.exec('begin');await db.query('update member_feature_permissions set can_manage_people=null where user_id=$1',[actors.managerOn]);await actor(actors.managerOn);await db.query('select private.check_account_access()');await assert.rejects(db.query('select public.save_worker_personnel_profile($1,$2::jsonb)',[fresh,JSON.stringify(malicious)]),x=>x.code==='P0001');await db.exec('rollback;reset role');assert.deepEqual(await capsule(),baseline,'Unknown permission cannot write');
await db.exec('begin');await actor(actors.deleted);await assert.rejects(db.query('select private.check_account_access()'),x=>x.code==='42501');await db.exec('rollback;reset role');assert.deepEqual(await capsule(),baseline);
// Direct REST write attempts are sent only to disposable loopback PostgreSQL17.
// Normal probes use rollback preference; the two-request approval case commits
// synthetic rows, verifies actual approval, then restores only business tables.
if(process.env.SKO_PERSONNEL_POSTGREST_URL){
 const base=new URL(process.env.SKO_PERSONNEL_POSTGREST_URL);if(!['127.0.0.1','localhost'].includes(base.hostname))throw Error('Loopback fixture only');await db.exec("notify pgrst,'reload schema'");
 const token=uid=>{const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');const data=`${enc({alg:'HS256',typ:'JWT'})}.${enc({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+300})}`;return data+'.'+crypto.createHmac('sha256','synthetic-personnel-fixture-secret-at-least-32-characters').update(data).digest('base64url');};
 const call=(rpc,key,args,commit=false)=>fetch(new URL('/rpc/'+rpc,base),{method:'POST',headers:{Authorization:`Bearer ${token(actors[key])}`,'Content-Type':'application/json',Prefer:commit?'tx=commit':'tx=rollback'},body:JSON.stringify(args)});
 for(let n=0;n<40;n++){try{const r=await call('fixture_account_hook_status','owner',{});if(r.ok){const p=await r.json();assert.equal(p.hook,'data-api-v1');assert.equal(p.actor_present,true);break;}}catch{}if(n===39)throw Error('Actual pre-request fixture not ready');await new Promise(r=>setTimeout(r,250));}
 async function payload(target){return {...(await db.query('select private.worker_personnel_payload($1) payload',[target])).rows[0].payload,address:'synthetic HTTP proposal'};}
 for(const key of ['owner','admin','managerOn','employee']){const r=await call('save_worker_personnel_profile',key,{p_worker_id:fresh,p_payload:await payload(fresh)});assert.equal(r.status,200,key+' initial HTTP');assert.match(r.headers.get('preference-applied')||'',/tx=rollback/);assert.equal((await r.json()).status,'saved');assert.deepEqual(await capsule(),baseline);}
 for(const target of [fresh,W]){const r=await call('save_worker_personnel_profile','managerOff',{p_worker_id:target,p_payload:await payload(target)});assert.equal(r.status,400);assert.equal((await r.json()).code,'P0001');assert.deepEqual(await capsule(),baseline,'OFF HTTP must not change any business state');}
 for(const key of ['owner','admin','managerOn','self']){const r=await call('save_worker_personnel_profile',key,{p_worker_id:W,p_payload:await payload(W)});assert.equal(r.status,200);assert.equal((await r.json()).status,['owner','admin'].includes(key)?'saved':'pending');assert.deepEqual(await capsule(),baseline);}
 const blocked=await call('save_worker_personnel_profile','deleted',{p_worker_id:W,p_payload:await payload(W)});assert.equal(blocked.status,403);assert.equal((await blocked.json()).code,'42501');
 const foreign=await call('save_worker_personnel_profile','owner',{p_worker_id:WF,p_payload:await payload(WF)});assert.equal(foreign.status,400);assert.equal((await foreign.json()).code,'P0001');
 const anonymous=await fetch(new URL('/rpc/save_worker_personnel_profile',base),{method:'POST',headers:{'Content-Type':'application/json',Prefer:'tx=rollback'},body:JSON.stringify({p_worker_id:fresh,p_payload:malicious})});assert.equal(anonymous.status,401);assert.deepEqual(await capsule(),baseline);
 // Exercise the actual two-actor approval API across separate committed HTTP
 // requests. Protected users/membership/provider/master tables are never reset.
 for(const key of ['managerOn','self']){
  const proposed=await payload(W);const req=await call('save_worker_personnel_profile',key,{p_worker_id:W,p_payload:proposed},true);assert.equal(req.status,200);const p=await req.json();assert.equal(p.status,'pending');
  const approved=await call('decide_worker_personnel_change','owner',{p_request_id:p.request_id,p_approve:true},true);assert.equal(approved.status,200);assert.equal((await approved.json()).status,'approved');assert.equal((await db.query('select address from worker_personnel_profiles where worker_id=$1',[W])).rows[0].address,proposed.address);
  await db.exec('begin');for(const t of [...businessTables].reverse())await db.exec(`delete from ${t}`);for(const t of businessTables)await db.query(`insert into ${t} select * from jsonb_populate_recordset(null::${t},$1::jsonb)`,[JSON.stringify(baseline.rows[t])]);await db.exec('commit');assert.deepEqual(await capsule(),baseline,'Synthetic committed approval restored without touching protected identities');
 }
 // Reproduce the original bug through actual HTTP with actual pre_request,
 // restoring the old helper only inside this synthetic database.
 await db.exec(helper);
 for(const target of [fresh,W]){const r=await call('save_worker_personnel_profile','managerOff',{p_worker_id:target,p_payload:await payload(target)});assert.equal(r.status,200);const p=await r.json();assert.equal(p.status,target===fresh?'saved':'pending');if(target===fresh){assert.equal(p.saved_directly,true);assert.equal(p.requires_approval,false);}assert.deepEqual(await capsule(),baseline);}
 await db.exec(migration);assert.equal(await source(),fixedSource);assert.deepEqual(await capsule(),baseline);
 console.log('PASS: actual save/decide HTTP with actual pre_request, OFF original leak vs fixed denial, owner/admin/self/delegated-manager saves and approvals, rollback/committed-recovery protected identity invariants');
}
await db.exec(helper);assert.equal(await source(),oldSource);assert.deepEqual(await capsule(),baseline);await db.exec(migration);assert.equal(await source(),fixedSource);assert.deepEqual(await capsule(),baseline);
await db.close();console.log('PASS: helper-only candidate, original write bypass reproduction, legitimate self/admin/delegated-manager and existing approver paths, drift abort, exact helper restoration/reapply and all protected business/identity/ACL/source invariants');
