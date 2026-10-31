import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import pg from 'pg';
const root = new URL('./', import.meta.url);
const helperContracts = JSON.parse(await readFile(new URL('helper-contracts.json',root),'utf8'));
const helpers = await readFile(new URL('actual-generic-helper-fixture.sql',root),'utf8');
const install = await readFile(new URL('install.sql.review-only',root),'utf8');
const legacy = await readFile(new URL('../required-document-attention-evidence/before.sql.review-only',root),'utf8');
const source = await readFile(new URL('scoped-function.sql.review-only',root),'utf8');
const preceding = await readFile(new URL('../required-document-attention-evidence/after.sql.review-only',root),'utf8');
const evidenceQuery=s=>s.slice(s.indexOf('  with evidence as'),s.indexOf('  from evidence;')+'  from evidence;'.length);
const finiteDateGuard = `        when nullif(statuses.item->>'expires_at','') is not null and (
          statuses.item->>'expires_at' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
          or left(statuses.item->>'expires_at',4)='0000') then 'unknown'
`;
assert.equal(evidenceQuery(source).replace(finiteDateGuard,''),evidenceQuery(preceding),
  'scoped endpoint reuses the reviewed evidence query plus the explicit finite-date guard');

let db;
const fixtureUrl=process.env.SKO_SCOPED_ATTENTION_FIXTURE_URL;
if(fixtureUrl){const u=new URL(fixtureUrl);assert.ok(['127.0.0.1','localhost'].includes(u.hostname)&&u.pathname==='/sko_scoped_attention_fixture');
 const client=new pg.Client({connectionString:fixtureUrl,ssl:false});await client.connect();
 assert.match((await client.query('show server_version')).rows[0].server_version,/^17\.6(?:\s|$)/);
 db={query:(...a)=>client.query(...a),exec:s=>client.query(s),close:()=>client.end()};
}else{db=new PGlite();}
const actor='10000000-0000-0000-0000-000000000001';
const sid='10000000-0000-0000-0000-000000000002';
const nextSid='10000000-0000-0000-0000-000000000003';
const company='10000000-0000-0000-0000-000000000004';
const other='10000000-0000-0000-0000-000000000005';
const worker='10000000-0000-0000-0000-000000000006';
const req='10000000-0000-0000-0000-000000000007';
await db.exec(`create role authenticated;create role anon;create role service_role;create role supabase_auth_admin;create role dashboard_user;
create schema auth;create schema private;
grant usage on schema auth,private to authenticated,anon,service_role,supabase_auth_admin,dashboard_user;
create table auth.users(id uuid primary key,is_anonymous bool,banned_until timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
create table private.account_deletion_access_restrictions(user_id uuid);
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.workers(id uuid primary key,user_id uuid,company_id uuid,status text);
create table public.document_requirements(id uuid primary key,company_id uuid,name text,sort_order int,is_active bool,is_required bool,expiry_required bool);
create table public.worker_document_statuses(id uuid primary key,requirement_id uuid,worker_id uuid,company_id uuid,status text,expires_at date,attachment_path text,attachment_paths text[]);
create table public.worker_private_bank_accounts(worker_id uuid,company_id uuid,updated_at timestamptz default now());
create table private.worker_document_exemptions(company_id uuid,worker_id uuid,requirement_id uuid,active bool);
insert into auth.users values('${actor}',false,null);
insert into auth.sessions values('${sid}','${actor}',now()+interval '1 hour'),('${nextSid}','${actor}',now()+interval '1 hour');
insert into company_members values('${company}','${actor}','owner');
insert into workers values('${worker}','${actor}','${company}','active');
insert into document_requirements values('${req}','${company}','synthetic insurance',1,true,true,false);
insert into worker_document_statuses values('${req}','${req}','${worker}','${company}','submitted',null,null,array['synthetic/a','synthetic/b']);`);
await db.exec(helpers);
const quote=s=>'"'+s.replaceAll('"','""')+'"';
for(const c of helperContracts){
 await db.exec(`alter function ${c.signature} owner to ${quote(c.owner)};
 revoke all on function ${c.signature} from public,postgres,authenticated,anon,service_role,supabase_auth_admin,dashboard_user;
 set role ${quote(c.owner)};`);
 for(const a of c.acl)await db.exec(`grant execute on function ${c.signature} to ${a.grantee==='PUBLIC'?'public':quote(a.grantee)}${a.grant_option?' with grant option':''}`);
 await db.exec('reset role');
}
await db.exec(legacy);
const before=await db.query("select pg_get_functiondef('public.current_user_required_document_attention()'::regprocedure) def");
await db.exec('grant execute on function private.require_reauthentication_session() to authenticated');
await assert.rejects(db.exec(install),/authentication dependency changed/);
await db.exec('rollback; revoke execute on function private.require_reauthentication_session() from authenticated');
await db.exec(install);
assert.deepEqual((await db.query("select pg_get_functiondef('public.current_user_required_document_attention()'::regprocedure) def")).rows,before.rows);
let checks=3;
async function claims(extra={}){await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:actor,role:'authenticated',session_id:sid,is_anonymous:false,...extra})]);}
async function read(cid=company){await db.exec('set role authenticated');try{return (await db.query('select public.current_user_required_document_attention_for_company($1::uuid) value',[cid])).rows[0].value;}finally{await db.exec('reset role');}}
async function denied(message,cid=company){await assert.rejects(read(cid),/reauthentication_required|not unique or authorized|Company required/);checks++;}
await claims();let data=await read();assert.equal(data.capability_version,1);assert.equal(data.company_id,company);assert.equal(data.worker_id,worker);assert.equal(data.actor_id,actor);assert.equal(data.session_id,sid);assert.equal(data.missing_count,0);assert.equal(data.unknown_count,0);checks++;
await denied('foreign company',other);
await denied('null company',null);
await db.exec(`insert into company_members values('${other}','${actor}','owner')`);
await denied('member without matching own worker',other);
await db.exec(`insert into workers values('10000000-0000-0000-0000-000000000099','${actor}','${company}','active')`);
await denied('duplicate active worker');
await db.exec("delete from workers where id='10000000-0000-0000-0000-000000000099'");
await db.exec(`insert into company_members values('${company}','${actor}','owner')`);await denied('duplicate membership');
await db.exec(`delete from company_members where ctid in (select ctid from company_members where company_id='${company}' limit 1)`);
await db.exec("update workers set status='inactive'");await denied('inactive worker');await db.exec("update workers set status='active'");
await claims({is_anonymous:true});await denied('anonymous');
await claims();await db.exec('update auth.users set is_anonymous=true');await denied('anonymous account');await db.exec('update auth.users set is_anonymous=false');
await claims({role:'service_role'});await denied('non-authenticated claim');
await claims({session_id:'invalid'});await denied('invalid SID');
await claims({session_id:'10000000-0000-0000-0000-000000000098'});await denied('missing SID');
await claims();await db.exec(`update auth.sessions set not_after=now()-interval '1 minute' where id='${sid}'`);await denied('expired SID');
await claims({session_id:nextSid});data=await read();assert.equal(data.session_id,nextSid);checks++;
await db.exec(`delete from auth.sessions where id='${sid}'`);data=await read();assert.equal(data.session_id,nextSid);checks++;
await db.exec(`update auth.users set banned_until=now()+interval '1 hour' where id='${actor}'`);await denied('banned account');await db.exec('update auth.users set banned_until=null');
await db.exec(`insert into private.account_deletion_access_restrictions values('${actor}')`);await denied('restricted account');await db.exec('delete from private.account_deletion_access_restrictions');
await db.exec("update worker_document_statuses set attachment_paths='{}',attachment_path=null");assert.equal((await read()).missing_count,1);checks++;
await db.exec("update worker_document_statuses set attachment_paths=array['synthetic/a'],expires_at='infinity'");
assert.equal((await read()).unknown_count,1,'non-finite SQL date cannot be saved evidence');checks++;
await db.exec("update worker_document_statuses set expires_at='0001-01-01 BC'");
assert.equal((await read()).unknown_count,1,'BC SQL date is outside the app date contract');checks++;
await db.exec("update worker_document_statuses set expires_at=null,attachment_paths='{}'");
await db.exec(`insert into private.worker_document_exemptions values('${other}','${worker}','${req}',true)`);assert.equal((await read()).missing_count,1);checks++;
await db.exec(`insert into private.worker_document_exemptions values('${company}','${worker}','${req}',true)`);assert.equal((await read()).missing_count,0);checks++;
await db.exec('update private.worker_document_exemptions set active=false');assert.equal((await read()).missing_count,1);checks++;
await db.exec("update worker_document_statuses set attachment_paths=array['synthetic/a','synthetic/a']");assert.equal((await read()).unknown_count,1);checks++;
for(const role of ['anon','service_role']){await db.exec(`set role ${role}`);await assert.rejects(db.query('select public.current_user_required_document_attention_for_company($1)',[company]),/permission denied/);await db.exec('reset role');checks++;}
await assert.rejects(db.exec(install),/already exists/);await db.exec('rollback');checks++;
console.log(JSON.stringify({engine:fixtureUrl?'native-postgres-17.6':'pglite-0.3.14',checks,actual_helper_bodies:5,synthetic_auth_rows:true,real_gotrue:false,production_writes:0,legacy_rpc_unchanged:true}));
await db.close();
