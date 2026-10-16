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
const e=JSON.parse(fs.readFileSync(path.join(here,'live_policy_fixture_20261016.json'),'utf8'));
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
await db.exec(fs.readFileSync(path.join(here,'canonical_read_rpc_fixture.sql'),'utf8'));
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
const legacy=JSON.parse(fs.readFileSync(path.join(here,'legacy_read_rpc_fixture.json'),'utf8'));
const originalPrivate=legacy.find(x=>x.schema==='private').definition;
const originalPublic=legacy.find(x=>x.schema==='public').definition;
await db.exec(originalPrivate);await db.exec(originalPublic);
await db.exec('revoke all on function public.employee_personnel_rows() from public,anon;grant execute on function public.employee_personnel_rows() to authenticated,service_role');
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261016104441_personnel_direct_read_permission_guard.sql'),'utf8'));
async function capsule(){
 const rows={};for(const table of ['company_members','member_feature_permissions','workers','worker_personnel_profiles','worker_family_members','private.account_deletion_access_restrictions','auth.users','auth.identities','private.master_admins'])rows[table]=(await db.query(`select to_jsonb(t) payload from ${table} t order by to_jsonb(t)::text`)).rows;
 const functions=(await db.query("select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args,pg_get_userbyid(p.proowner) owner,p.proacl::text,p.proconfig,p.prosecdef,p.provolatile,p.prorettype::regtype::text,case when n.nspname='private' and p.proname='employee_personnel_rows' then null else pg_get_functiondef(p.oid) end definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','auth') and p.prokind='f' order by n.nspname,p.proname,args")).rows;
 const tables=(await db.query("select n.nspname,c.relname,c.relacl::text,c.relrowsecurity,c.relforcerowsecurity,a.attname,a.attacl::text from pg_class c join pg_namespace n on n.oid=c.relnamespace left join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped where n.nspname in ('public','private','auth') and c.relkind in ('r','p','v') order by n.nspname,c.relname,a.attnum")).rows;
 const policies=(await db.query("select schemaname,tablename,policyname,permissive,to_jsonb(roles) roles,cmd,qual,with_check from pg_policies where schemaname in ('public','private','auth') order by schemaname,tablename,policyname")).rows;
 const schemas=(await db.query("select nspname,nspacl::text from pg_namespace where nspname in ('public','private','auth') order by nspname")).rows;
 return {rows,functions,tables,policies,schemas};
}
const baseline=await capsule();
await actor(actors.managerOff);assert.deepEqual(await ownCounts(),[0,0]);
const before=(await db.query('select public.employee_personnel_rows() payload')).rows[0].payload;
assert.equal(before.length,1);assert.equal(before[0].address,'synthetic own-company address');assert.equal(before[0].family_members.length,1);
await actor(actors.deleted);assert.equal((await db.query('select public.employee_personnel_rows() payload')).rows[0].payload.length,1,'Original legacy RPC also bypasses blocked-account RLS');
await actor(actors.owner);const legitimateBefore=(await db.query('select public.employee_personnel_rows() payload')).rows[0].payload;
await db.exec('reset role');
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261016113335_personnel_legacy_read_permission_guard.sql'),'utf8');
const targetSource=async()=>(await db.query("select prosrc from pg_proc where oid='private.employee_personnel_rows()'::regprocedure")).rows[0].prosrc;
const originalSource=await targetSource();
async function drift(change,undo,label){
 await db.exec(change);const state=await capsule(),src=await targetSource();await assert.rejects(db.exec(migration),x=>x.code==='55000',label);await db.exec('rollback');assert.deepEqual(await capsule(),state,label+' unchanged capsule');assert.equal(await targetSource(),src,label+' unchanged target source');await db.exec(undo);assert.deepEqual(await capsule(),baseline);assert.equal(await targetSource(),originalSource);
}
await drift("create or replace function private.employee_personnel_rows() returns jsonb language plpgsql stable security definer set search_path='' as $$begin return '[]'::jsonb;end$$",originalPrivate,'Legacy private source drift');
await drift('grant execute on function public.employee_personnel_rows() to anon','revoke execute on function public.employee_personnel_rows() from anon','Public wrapper ACL drift');
await drift("create or replace function public.employee_personnel_rows() returns jsonb language sql set search_path='' as $$select '[]'::jsonb$$",originalPublic,'Public wrapper source drift');
await db.exec(migration);assert.deepEqual(await capsule(),baseline,'Only the targeted private function source may change');
const expectedSource=originalSource.replace('if v_company is null then',"if v_company is null\n     or private.account_access_allowed() is not true\n     or private.has_company_feature(v_company,'can_manage_people') is not true then").replace("raise exception '社員情報の閲覧権限がありません';","raise exception '社員情報の閲覧権限がありません' using errcode='42501';");
assert.equal(await targetSource(),expectedSource,'Private function changes only permission gate and authorization SQLSTATE');
for(const [key,expected]of Object.entries({managerOff:0,managerOn:2,owner:2,admin:2,viewer:1,self:1,retiredSelf:1,employee:0,outsider:0,deleted:0})){
 await actor(actors[key]);assert.deepEqual(await ownCounts(),[expected,expected],key+' direct personnel/family');
 const allowed=['managerOn','owner','admin'].includes(key);
 if(allowed)assert.deepEqual((await db.query('select public.employee_personnel_rows() payload')).rows[0].payload,legitimateBefore,key+' unchanged active-only legacy payload');
 else await assert.rejects(db.query('select public.employee_personnel_rows()'),x=>x.code==='42501',key+' legacy RPC denies coworkers');
 const viewAllowed=['managerOn','owner','admin','viewer'].includes(key);
 if(viewAllowed)assert.equal((await db.query('select public.employee_personnel_view($1) payload',[C])).rows[0].payload.records.length,1,key+' canonical view remains active-only');
 else await assert.rejects(db.query('select public.employee_personnel_view($1)',[C]),x=>x.code==='42501');
}
await db.exec('reset role');await db.query('update member_feature_permissions set can_manage_people=false where user_id=$1',[actors.managerOn]);await actor(actors.managerOn);assert.deepEqual(await ownCounts(),[0,0]);await assert.rejects(db.query('select public.employee_personnel_rows()'),x=>x.code==='42501','Permission revocation immediately affects legacy RPC');await db.exec('reset role');await db.query('update member_feature_permissions set can_manage_people=true where user_id=$1',[actors.managerOn]);
// Fault injection only: production permission column is NOT NULL. Simulate an
// unknown helper result and prove all normal personnel read paths fail closed.
await db.query('update member_feature_permissions set can_manage_people=null where user_id=$1',[actors.managerOn]);await actor(actors.managerOn);assert.equal((await db.query('select private.has_company_feature($1,$2) allowed',[C,'can_manage_people'])).rows[0].allowed,null);assert.deepEqual(await ownCounts(),[0,0]);await assert.rejects(db.query('select public.employee_personnel_rows()'),x=>x.code==='42501','NULL people permission must deny legacy RPC');await assert.rejects(db.query('select public.employee_personnel_view($1)',[C]),x=>x.code==='42501','NULL people permission denies canonical RPC');await db.exec('reset role');await db.query('update member_feature_permissions set can_manage_people=true where user_id=$1',[actors.managerOn]);
const accountDefinition=e.functions.find(x=>x.includes('FUNCTION private.account_access_allowed('));
await db.exec("create or replace function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$select null::boolean$$");await actor(actors.owner);assert.deepEqual(await ownCounts(),[0,0]);await assert.rejects(db.query('select public.employee_personnel_rows()'),x=>x.code==='42501','NULL account helper must deny legacy RPC');await db.exec('reset role');await db.exec(accountDefinition);assert.deepEqual(await capsule(),baseline,'Fault injection restores all helper source and permission state');
console.log('PASS: deliberate NULL people-permission fault denies legacy/canonical/direct reads; NULL account-helper fault denies hardened legacy RPC; production helper and NOT NULL schema restored unchanged');
await actor(null);await assert.rejects(db.query('select public.employee_personnel_rows()'),x=>x.code==='42501');await db.exec('reset role;set role anon');await assert.rejects(db.query('select public.employee_personnel_rows()'),x=>x.code==='42501');await db.exec('reset role');
if(process.env.SKO_PERSONNEL_POSTGREST_URL){
 const base=new URL(process.env.SKO_PERSONNEL_POSTGREST_URL);if(!['127.0.0.1','localhost'].includes(base.hostname))throw Error('Loopback fixture only');
 await db.exec("notify pgrst,'reload schema'");
 const token=uid=>{const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');const data=`${enc({alg:'HS256',typ:'JWT'})}.${enc({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+300})}`;return data+'.'+crypto.createHmac('sha256','synthetic-personnel-fixture-secret-at-least-32-characters').update(data).digest('base64url');};
 const call=(route,key,body)=>fetch(new URL(route,base),{method:body?'POST':'GET',headers:{Authorization:`Bearer ${token(actors[key])}`,...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
 for(let n=0;n<40;n++){try{const r=await call('/rpc/employee_personnel_rows','owner',{});if(r.ok)break;}catch{}if(n===39)throw Error('PostgREST not ready');await new Promise(r=>setTimeout(r,250));}
 for(const [key,count]of Object.entries({managerOff:0,managerOn:2,owner:2,admin:2,viewer:1,self:1,retiredSelf:1,employee:0,outsider:0,deleted:0})){
  const allowed=['managerOn','owner','admin'].includes(key);const r=await call('/rpc/employee_personnel_rows',key,{});assert.equal(r.status,allowed?200:403,'Legacy HTTP '+key);if(allowed)assert.deepEqual(await r.json(),legitimateBefore,'Unchanged HTTP payload '+key);
  for(const table of ['worker_personnel_profiles','worker_family_members']){const d=await call(`/${table}?company_id=eq.${C}&select=company_id`,key);assert.equal(d.status,200);assert.equal((await d.json()).length,count,'Direct REST '+key+'/'+table);}
  const canonical=await call('/rpc/employee_personnel_view',key,{p_company:C});assert.equal(canonical.status,['managerOn','owner','admin','viewer'].includes(key)?200:403,'Canonical HTTP '+key);
 }
 await db.query('update member_feature_permissions set can_manage_people=null where user_id=$1',[actors.managerOn]);
 for(const route of ['/rpc/employee_personnel_rows','/rpc/employee_personnel_view']){const r=await call(route,'managerOn',route.endsWith('_view')?{p_company:C}:{});assert.equal(r.status,403,'NULL permission signed RPC '+route);}
 for(const table of ['worker_personnel_profiles','worker_family_members']){const r=await call(`/${table}?company_id=eq.${C}&select=company_id`,'managerOn');assert.equal(r.status,200);assert.deepEqual(await r.json(),[],'NULL permission direct REST '+table);}
 await db.query('update member_feature_permissions set can_manage_people=true where user_id=$1',[actors.managerOn]);
 await db.exec("create or replace function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$select null::boolean$$");const nullAccount=await call('/rpc/employee_personnel_rows','owner',{});assert.equal(nullAccount.status,403,'NULL account helper signed legacy RPC');await db.exec(accountDefinition);
 const anon=await fetch(new URL('/rpc/employee_personnel_rows',base),{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});assert.equal(anon.status,401);
 console.log('PASS: PostgreSQL17 + signed HTTP actual legacy and canonical RPC/direct REST authorization matrix');
}
await db.exec('reset role');await db.exec(originalPrivate);assert.equal(await targetSource(),originalSource);assert.deepEqual(await capsule(),baseline,'Original definition restoration preserves every identity, role, membership, master/provider, source and ACL');
for(const key of ['owner','admin','managerOn']){await actor(actors[key]);assert.deepEqual((await db.query('select public.employee_personnel_rows() payload')).rows[0].payload,legitimateBefore,'Restored legitimate '+key);}
await actor(actors.self);assert.deepEqual(await ownCounts(),[1,1],'Self own-record access survives restoration');
await actor(actors.managerOff);assert.equal((await db.query('select public.employee_personnel_rows() payload')).rows[0].payload.length,1,'Emergency restoration REOPENS original known RPC leak');
await db.exec('reset role');await db.exec(migration);assert.deepEqual(await capsule(),baseline);assert.equal(await targetSource(),expectedSource);await actor(actors.managerOff);await assert.rejects(db.query('select public.employee_personnel_rows()'),x=>x.code==='42501');
await db.close();console.log('PASS: original legacy SECURITY DEFINER bypass reproduced after RLS fix; actual minimal gate closes it; drift fails closed; protected source/ACL/data/identity restoration and reapply verified, including known leak reopening');
