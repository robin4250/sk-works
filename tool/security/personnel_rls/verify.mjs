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
const C=id(1),F=id(2),W=id(3),WF=id(4);
const actors={managerOff:id(11),managerOn:id(12),owner:id(13),admin:id(14),viewer:id(15),self:id(16),employee:id(17),outsider:id(18),deleted:id(19)};
await db.exec(`create role authenticated;create role anon;create schema auth;create schema private;
create function auth.uid() returns uuid language sql stable as $$select coalesce(nullif(current_setting('fixture.actor',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
create table private.account_deletion_access_restrictions(user_id uuid);
create table company_members(company_id uuid,user_id uuid,role text);
create table member_feature_permissions(company_id uuid,user_id uuid,can_view_invoices boolean default false,can_manage_invoices boolean default false,can_manage_payroll boolean default false,can_manage_people boolean default false,can_manage_attendance boolean default false,can_approve_daily_report_edits boolean default false,can_manage_partner_chat boolean default false);
create table workers(id uuid,company_id uuid,user_id uuid);
create table worker_personnel_profiles(worker_id uuid,company_id uuid,address text);
create table worker_family_members(id uuid,worker_id uuid,company_id uuid,name text);
create function private.has_company_role(uuid,text[]) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.company_members where company_id=$1 and user_id=auth.uid() and role=any($2))$$;
grant usage on schema public,private,auth to authenticated,anon;
grant select on company_members,member_feature_permissions,worker_personnel_profiles,worker_family_members to authenticated;
grant select(id,company_id,user_id) on workers to authenticated;`);
for(const f of e.functions)await db.exec(f);
for(const t of ['company_members','member_feature_permissions','workers','worker_personnel_profiles','worker_family_members'])await db.exec(`alter table ${t} enable row level security`);
for(const p of e.policies){let q=`create policy "${p.policyname}" on ${p.tablename} as ${p.permissive} for ${p.cmd} to authenticated`;if(p.qual)q+=` using (${p.qual.replaceAll('app_role','text')})`;if(p.with_check)q+=` with check (${p.with_check.replaceAll('app_role','text')})`;await db.exec(q);}
for(const [key,actor]of Object.entries(actors)){const role=key.startsWith('manager')?'manager':key==='deleted'?'owner':['owner','admin','viewer'].includes(key)?key:'employee';await db.query('insert into company_members values($1,$2,$3)',[key==='outsider'?F:C,actor,role]);await db.query('insert into member_feature_permissions(company_id,user_id,can_manage_people)values($1,$2,$3)',[C,actor,key==='managerOn']);}
await db.query('insert into private.account_deletion_access_restrictions values($1)',[actors.deleted]);
await db.query('insert into workers values($1,$2,$3),($4,$5,$6)',[W,C,actors.self,WF,F,actors.outsider]);
await db.query('insert into worker_personnel_profiles values($1,$2,$3),($4,$5,$6)',[W,C,'synthetic own-company address',WF,F,'synthetic foreign address']);
await db.query('insert into worker_family_members values($1,$2,$3,$4),($5,$6,$7,$8)',[id(30),W,C,'synthetic family',id(31),WF,F,'foreign family']);
async function actor(uid){await db.exec('reset role');await db.query("select set_config('fixture.actor',$1,false)",[uid??'']);await db.exec('set role authenticated');}
async function ownCounts(){return [(await db.query('select address from worker_personnel_profiles where company_id=$1',[C])).rows.length,(await db.query('select name from worker_family_members where company_id=$1',[C])).rows.length];}
await actor(actors.managerOff);
assert.equal((await db.query('select private.personnel_view_allowed($1) allowed',[C])).rows[0].allowed,false);
assert.deepEqual(await ownCounts(),[1,1],'Original live policies MUST reproduce the permission bypass');
await db.exec('reset role');
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261016104441_personnel_direct_read_permission_guard.sql'),'utf8'));
for(const [key,expected]of Object.entries({managerOff:0,managerOn:1,owner:1,admin:1,viewer:1,self:1,employee:0,outsider:0,deleted:0})){
 await actor(actors[key]);assert.deepEqual(await ownCounts(),[expected,expected],key);
 if(key!=='outsider')assert.equal((await db.query('select count(*)::int n from worker_personnel_profiles where company_id=$1',[F])).rows[0].n,0,`${key}: foreign tenant`);
}
await db.exec('reset role');await db.query('update member_feature_permissions set can_manage_people=false where user_id=$1',[actors.managerOn]);await actor(actors.managerOn);assert.deepEqual(await ownCounts(),[0,0],'Permission revocation applies without JWT refresh');
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
 for(const [key,expected]of Object.entries({managerOff:0,managerOn:1,owner:1,admin:1,viewer:1,self:1,employee:0,outsider:0,deleted:0}))for(const table of ['worker_personnel_profiles','worker_family_members']){
  const r=await fetch(new URL(`/${table}?company_id=eq.${C}&select=company_id`,base),{headers:{Authorization:`Bearer ${token(actors[key])}`}});assert.equal(r.status,200,`${key}/${table}`);assert.equal((await r.json()).length,expected,`HTTP ${key}/${table}`);
 }
 const r=await fetch(new URL('/worker_personnel_profiles?select=address',base));assert.equal(r.status,401,'Anonymous HTTP denied');
 console.log('PASS: real PostgreSQL17 + signed-JWT PostgREST direct REST role matrix');
}
await db.close();console.log('PASS: original bypass reproduced, actual additive migration applied, permission OFF/ON/revoked, self/owner/admin/viewer, employee/other-company/anonymous/deleted matrix');
