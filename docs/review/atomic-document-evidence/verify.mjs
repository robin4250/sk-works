import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import pg from 'pg';
const root = new URL('./', import.meta.url);
const helperContracts = JSON.parse(await readFile(new URL('helper-contracts.json',root),'utf8'));
const helpers = await readFile(new URL('actual-generic-helper-fixture.sql',root),'utf8');
const install = await readFile(new URL('install.sql.review-only',root),'utf8');
const legacy = await readFile(new URL('legacy-original.sql.review-only',root),'utf8');

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
await db.exec("alter table public.document_requirements add column scope text not null default 'internal'");
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

await db.exec('alter default privileges in schema public grant execute on functions to anon,authenticated,service_role; create role unexpected_role');
const query=await readFile(new URL('catalog-fingerprint.sql',root),'utf8');
const manifest=JSON.parse(await readFile(new URL('manifest.json',root),'utf8'));
// Only this isolated test string substitutes synthetic catalog fingerprints/version.
// The checked-in production candidate remains pinned to the actual read-only capture.
const fixtureHashes=(await db.query(query)).rows[0];
const version=(await db.query('show server_version_num')).rows[0].server_version_num;
let fixtureInstall=install.replaceAll(manifest.server_version_num,version);
for(const [key,value] of Object.entries(manifest.catalog_hashes)) fixtureInstall=fixtureInstall.replaceAll(value,fixtureHashes[key]);
let checks=0;
async function rejects(sql,undo,pattern){await db.exec(sql);await assert.rejects(db.exec(fixtureInstall),pattern);await db.exec('rollback');await db.exec(undo);checks++;}
await rejects('grant execute on function private.require_reauthentication_session() to authenticated','revoke execute on function private.require_reauthentication_session() from authenticated',/functions_hash changed/);
await rejects('grant create on schema private to authenticated','revoke create on schema private from authenticated',/schemas_hash changed/);
await rejects('alter default privileges in schema public grant execute on functions to unexpected_role','alter default privileges in schema public revoke execute on functions from unexpected_role',/defaults_hash changed/);
await rejects('alter default privileges in schema private grant execute on functions to service_role','alter default privileges in schema private revoke execute on functions from service_role',/defaults_hash changed/);
// Revoking a new default creates/removes catalog rows differently: derive only a new
// fixture baseline after the deliberately repaired test DDL; production pins are unchanged.
const repaired=(await db.query(query)).rows[0];
for(const [key,value] of Object.entries(fixtureHashes))fixtureInstall=fixtureInstall.replaceAll(value,repaired[key]);
await rejects('alter table public.document_requirements add column unexpected boolean','alter table public.document_requirements drop column unexpected',/relations_hash changed/);
// Dropped column catalog metadata persists, so rebaseline the isolated fixture only.
const finalHashes=(await db.query(query)).rows[0];
for(const [key,value] of Object.entries(repaired))fixtureInstall=fixtureInstall.replaceAll(value,finalHashes[key]);
await db.exec(`insert into private.worker_document_exemptions values('${company}','${worker}','${req}',true);
create table private.synthetic_exemption_history(id int, note text); insert into private.synthetic_exemption_history values(1,'retained history');`);
const rowsBefore=(await db.query('select to_jsonb(x) value from private.worker_document_exemptions x')).rows;
const historyBefore=(await db.query('select to_jsonb(x) value from private.synthetic_exemption_history x')).rows;
for(const mutation of [
 'grant execute on function public.current_user_required_document_attention_for_company(uuid) to unexpected_role;',
 'grant execute on function private.current_user_required_document_attention_for_company(uuid) to authenticated with grant option;',
 'alter function public.current_user_required_document_attention_for_company(uuid) cost 999;'
]){await assert.rejects(db.exec(fixtureInstall.replace('do $post$',mutation+'\ndo $post$')),/ACL changed|complete catalog seal mismatch/);await db.exec('rollback');checks++;}
await db.exec(fixtureInstall);checks++;
assert.deepEqual((await db.query('select to_jsonb(x) value from private.worker_document_exemptions x')).rows,rowsBefore);
assert.deepEqual((await db.query('select to_jsonb(x) value from private.synthetic_exemption_history x')).rows,historyBefore);checks++;
assert.deepEqual((await db.query(query)).rows[0],finalHashes);checks++;
assert.deepEqual((await db.query("select pg_get_functiondef('public.current_user_required_document_attention()'::regprocedure) def")).rows,before.rows);checks++;
await assert.rejects(db.exec(fixtureInstall),/already exists/);await db.exec('rollback');checks++;
await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:actor,role:'authenticated',session_id:sid,is_anonymous:false})]);
await db.exec('set role authenticated');
const receipt=(await db.query('select public.current_user_required_document_attention_for_company($1::uuid) value',[company])).rows[0].value;
assert.equal(receipt.exempt_count,1);assert.equal(receipt.required_count,0);assert.equal(receipt.missing_count,0);checks++;
await db.exec('reset role');
await writeFile(new URL('new-catalog-seal.generated.json',root), JSON.stringify((await db.query("select n.nspname, (to_jsonb(p)-array['oid','pronamespace','proowner','prolang','prosrc'])||jsonb_build_object('body_md5',md5(p.prosrc)) as catalog from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.proname='current_user_required_document_attention_for_company' order by n.nspname")).rows,null,2));
await db.close();
console.log(JSON.stringify({checks,productionCandidateApplied:false,syntheticFingerprintSubstitution:true,existingWaiverAndHistoryPreserved:true}));
