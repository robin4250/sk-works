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
await db.exec(`create role authenticated;create role anon;create schema auth;create schema private;
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
await actor(actors.managerOff);
assert.equal((await db.query('select private.personnel_view_allowed($1) allowed',[C])).rows[0].allowed,false);
await assert.rejects(db.query('select public.employee_personnel_view($1)',[C]),x=>x.code==='42501','Actual canonical company-list RPC denies disabled manager');
assert.deepEqual(await ownCounts(),[2,2],'Original live policies MUST reproduce the permission bypass, including retired records');
await db.exec('reset role');
async function migrationInvariant(){
 const rows={};for(const table of ['company_members','member_feature_permissions','workers','worker_personnel_profiles','worker_family_members','private.account_deletion_access_restrictions','auth.users','auth.identities','private.master_admins'])rows[table]=(await db.query(`select to_jsonb(t) payload from ${table} t order by to_jsonb(t)::text`)).rows;
 const grants=(await db.query("select n.nspname,c.relname,c.relacl::text,c.relrowsecurity,c.relforcerowsecurity,a.attname,a.attacl::text from pg_class c join pg_namespace n on n.oid=c.relnamespace left join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped where n.nspname in ('public','private','auth') and c.relkind in ('r','p','v') order by n.nspname,c.relname,a.attnum")).rows;
 const functions=(await db.query("select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args,p.proacl::text,pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','auth') and p.prokind='f' order by n.nspname,p.proname,args")).rows;
 const schemas=(await db.query("select nspname,nspacl::text from pg_namespace where nspname in ('public','private','auth') order by nspname")).rows;
 const writes=(await db.query("select * from pg_policies where schemaname='public' and tablename in ('worker_personnel_profiles','worker_family_members') and cmd<>'SELECT' order by tablename,policyname")).rows;
 return {rows,grants,functions,schemas,writes};
}
const invariantBefore=await migrationInvariant();
const policiesBefore=(await db.query("select schemaname,tablename,policyname,permissive,to_jsonb(roles) roles,cmd,qual,with_check from pg_policies where schemaname in ('public','private','auth') order by schemaname,tablename,policyname")).rows;
const originalSelectPolicies=policiesBefore.filter(p=>p.schemaname==='public'&&['worker_personnel_profiles','worker_family_members'].includes(p.tablename)&&p.cmd==='SELECT');
assert.equal(originalSelectPolicies.length,2,'Capture exactly the two original SELECT policies before applying the candidate');
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261016104441_personnel_direct_read_permission_guard.sql'),'utf8');
const allPolicies=async()=>(await db.query("select schemaname,tablename,policyname,permissive,to_jsonb(roles) roles,cmd,qual,with_check from pg_policies where schemaname in ('public','private','auth') order by schemaname,tablename,policyname")).rows;
async function driftRejected(change,undo,label){
 await db.exec(change);const state=await migrationInvariant(),policies=await allPolicies();
 await assert.rejects(db.exec(migration),x=>x.code==='55000',label+' must stop before overwriting any policy');await db.exec('rollback');
 assert.deepEqual(await migrationInvariant(),state,label+' leaves drifted data/source/ACL/identity state unchanged');assert.deepEqual(await allPolicies(),policies,label+' leaves all policies unchanged');
 await db.exec(undo);assert.deepEqual(await migrationInvariant(),invariantBefore);assert.deepEqual(await allPolicies(),policiesBefore);
}
const originalProfile=originalSelectPolicies.find(p=>p.tablename==='worker_personnel_profiles');
await driftRejected('alter policy "personnel profile read" on worker_personnel_profiles using(false)',`alter policy "personnel profile read" on worker_personnel_profiles using(${originalProfile.qual})`,'Policy predicate drift');
await driftRejected('alter policy "personnel profile read" on worker_personnel_profiles to authenticated','alter policy "personnel profile read" on worker_personnel_profiles to public','Policy role drift');
await driftRejected(`drop policy "personnel profile read" on worker_personnel_profiles;create policy "personnel profile read" on worker_personnel_profiles as restrictive for select to public using(${originalProfile.qual})`,`drop policy "personnel profile read" on worker_personnel_profiles;create policy "personnel profile read" on worker_personnel_profiles as permissive for select to public using(${originalProfile.qual})`,'Policy permissiveness drift');
await driftRejected(`drop policy "personnel profile read" on worker_personnel_profiles;create policy "personnel profile read" on worker_personnel_profiles for all to public using(${originalProfile.qual})`,`drop policy "personnel profile read" on worker_personnel_profiles;create policy "personnel profile read" on worker_personnel_profiles for select to public using(${originalProfile.qual})`,'Policy command drift');
const canonicalFunction=e.functions.find(x=>x.includes('FUNCTION private.personnel_view_allowed('));
await driftRejected("create or replace function private.personnel_view_allowed(p_company uuid) returns boolean language sql stable security invoker set search_path='' as $$select false$$",canonicalFunction,'Canonical helper source drift');
await driftRejected('grant execute on function private.personnel_view_allowed(uuid) to anon','revoke execute on function private.personnel_view_allowed(uuid) from anon','Canonical helper ACL drift');
await driftRejected('alter table worker_personnel_profiles disable row level security','alter table worker_personnel_profiles enable row level security','Table RLS drift');
await driftRejected('create policy fixture_new_policy on worker_personnel_profiles for select to authenticated using(false)','drop policy fixture_new_policy on worker_personnel_profiles','Concurrent additional policy drift');
console.log('PASS: predicate/roles/permissiveness/command/helper-source/helper-ACL/RLS/additional-policy drift aborts whole migration and preserves the changed snapshot');
await db.exec(migration);
assert.deepEqual(await migrationInvariant(),invariantBefore,'Migration preserves every synthetic business row, column/table grant and non-SELECT policy');
for(const [key,expected]of Object.entries({managerOff:0,managerOn:2,owner:2,admin:2,viewer:1,self:1,retiredSelf:1,employee:0,outsider:0,deleted:0})){
 await actor(actors[key]);assert.deepEqual(await ownCounts(),[expected,expected],key);
 const retiredAllowed=['managerOn','owner','admin','retiredSelf'].includes(key)?1:0;
 for(const table of ['worker_personnel_profiles','worker_family_members'])assert.equal((await db.query(`select count(*)::int n from ${table} where worker_id=$1`,[WR])).rows[0].n,retiredAllowed,key+' retired scope');
 const companyListAllowed=['managerOn','owner','admin','viewer'].includes(key);
 if(companyListAllowed){const payload=(await db.query('select public.employee_personnel_view($1) payload',[C])).rows[0].payload;assert.equal(payload.records.length,1,key+' actual company-list RPC');assert.equal(payload.records[0].address,'synthetic own-company address');assert.equal(payload.records[0].familyMembers.length,1);}
 else await assert.rejects(db.query('select public.employee_personnel_view($1)',[C]),x=>x.code==='42501',key+' cannot list coworkers via RPC');
 if(key!=='outsider')assert.equal((await db.query('select count(*)::int n from worker_personnel_profiles where company_id=$1',[F])).rows[0].n,0,`${key}: foreign tenant`);
}
await db.exec('reset role');await db.query('update member_feature_permissions set can_manage_people=true where user_id=$1',[actors.viewer]);await actor(actors.viewer);assert.deepEqual(await ownCounts(),[1,1],'Viewer stays active-only even if a feature flag is set');await db.exec('reset role');await db.query('update member_feature_permissions set can_manage_people=false where user_id=$1',[actors.viewer]);
await db.exec('reset role');await db.query('update member_feature_permissions set can_manage_people=false where user_id=$1',[actors.managerOn]);await actor(actors.managerOn);assert.deepEqual(await ownCounts(),[0,0],'Permission revocation applies without JWT refresh');
await assert.rejects(db.query('select public.employee_personnel_view($1)',[C]),x=>x.code==='42501','Actual RPC sees revoked permission immediately');
await db.exec('reset role');await db.query('update member_feature_permissions set can_manage_people=true where user_id=$1',[actors.managerOn]);
await db.query('insert into private.account_deletion_access_restrictions values($1)',[actors.self]);await actor(actors.self);assert.deepEqual(await ownCounts(),[0,0],'Deleted self denied');await db.exec('reset role');await db.query('delete from private.account_deletion_access_restrictions where user_id=$1',[actors.self]);
await actor(null);assert.deepEqual(await ownCounts(),[0,0],'Missing actor denied');
await db.exec('reset role;set role anon');await assert.rejects(db.query('select address from worker_personnel_profiles'),x=>x.code==='42501');await assert.rejects(db.query('select name from worker_family_members'),x=>x.code==='42501');
await db.exec('reset role');
// Actual PostgREST HTTP uses signed synthetic JWTs against disposable local PG17.
if(process.env.SKO_PERSONNEL_POSTGREST_URL){
 const base=new URL(process.env.SKO_PERSONNEL_POSTGREST_URL);if(!['127.0.0.1','localhost'].includes(base.hostname))throw Error('Loopback HTTP fixture only');
 await db.exec("notify pgrst,'reload schema'");
 const token=uid=>{const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');const input=`${enc({alg:'HS256',typ:'JWT'})}.${enc({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+300})}`;return input+'.'+crypto.createHmac('sha256','synthetic-personnel-fixture-secret-at-least-32-characters').update(input).digest('base64url');};
 for(let n=0;n<40;n++){try{const r=await fetch(new URL('/worker_personnel_profiles?select=address',base),{headers:{Authorization:`Bearer ${token(actors.owner)}`}});if(r.ok)break;}catch{}if(n===39)throw Error('PostgREST fixture not ready');await new Promise(r=>setTimeout(r,250));}
 for(const [key,expected]of Object.entries({managerOff:0,managerOn:2,owner:2,admin:2,viewer:1,self:1,retiredSelf:1,employee:0,outsider:0,deleted:0}))for(const table of ['worker_personnel_profiles','worker_family_members']){
  const r=await fetch(new URL(`/${table}?company_id=eq.${C}&select=company_id`,base),{headers:{Authorization:`Bearer ${token(actors[key])}`}});assert.equal(r.status,200,`${key}/${table}`);assert.equal((await r.json()).length,expected,`HTTP ${key}/${table}`);
  const retired=await fetch(new URL(`/${table}?worker_id=eq.${WR}&select=company_id`,base),{headers:{Authorization:`Bearer ${token(actors[key])}`}});assert.equal(retired.status,200);assert.equal((await retired.json()).length,['managerOn','owner','admin','retiredSelf'].includes(key)?1:0,`HTTP retired ${key}/${table}`);
 }
 for(const key of Object.keys(actors)){
  const allowed=['managerOn','owner','admin','viewer'].includes(key);
  const r=await fetch(new URL('/rpc/employee_personnel_view',base),{method:'POST',headers:{Authorization:`Bearer ${token(actors[key])}`,'Content-Type':'application/json'},body:JSON.stringify({p_company:C})});assert.equal(r.status,allowed?200:403,`Actual RPC HTTP ${key}`);if(allowed)assert.equal((await r.json()).records.length,1);
 }
 const r=await fetch(new URL('/worker_personnel_profiles?select=address',base));assert.equal(r.status,401,'Anonymous HTTP denied');
 console.log('PASS: real PostgreSQL17 + signed-JWT PostgREST actual canonical RPC and direct REST role matrix');
}
// Emergency restoration rehearsal only. Restoring the original policies also
// restores their known manager-permission bypass, so this is NOT a safe normal
// rollback or an authorization to execute any production restoration.
await db.exec('reset role;begin');
const ident=s=>'"'+s.replaceAll('"','""')+'"';
for(const p of originalSelectPolicies){
 await db.exec(`drop policy ${ident(p.policyname)} on ${ident(p.schemaname)}.${ident(p.tablename)}`);
 let sql=`create policy ${ident(p.policyname)} on ${ident(p.schemaname)}.${ident(p.tablename)} as ${p.permissive} for ${p.cmd} to ${p.roles.map(ident).join(',')}`;
 if(p.qual)sql+=` using (${p.qual})`;if(p.with_check)sql+=` with check (${p.with_check})`;await db.exec(sql);
}
await db.exec('commit');
assert.deepEqual((await db.query("select schemaname,tablename,policyname,permissive,to_jsonb(roles) roles,cmd,qual,with_check from pg_policies where schemaname in ('public','private','auth') order by schemaname,tablename,policyname")).rows,policiesBefore,'All original policies restored exactly');
assert.deepEqual(await migrationInvariant(),invariantBefore,'Restoration preserves source functions, ACLs, business rows, IDs, roles, membership, master registration and provider identity sentinels');
for(const [key,expected]of Object.entries({owner:2,admin:2,self:1,retiredSelf:1})){await actor(actors[key]);assert.deepEqual(await ownCounts(),[expected,expected],`Restored legitimate ${key} access`);}
await actor(actors.managerOff);assert.deepEqual(await ownCounts(),[2,2],'Emergency restoration explicitly reopens the ORIGINAL known vulnerability');
await assert.rejects(db.query('select public.employee_personnel_view($1)',[C]),x=>x.code==='42501','Original RPC remains protected after restoration');
await db.exec('reset role');await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261016104441_personnel_direct_read_permission_guard.sql'),'utf8'));
assert.deepEqual(await migrationInvariant(),invariantBefore,'Reapplying candidate still preserves identities and data');
await actor(actors.managerOff);assert.deepEqual(await ownCounts(),[0,0]);await actor(actors.viewer);assert.deepEqual(await ownCounts(),[1,1]);
console.log('PASS: isolated original-policy restoration and reapply; admin/self access and synthetic IDs/roles/membership/master/provider/source/ACL unchanged; old vulnerability reopening explicitly verified');
await db.close();console.log('PASS: original bypass reproduced, actual additive migration applied, permission OFF/ON/revoked, self/owner/admin/viewer, employee/other-company/anonymous/deleted matrix');
