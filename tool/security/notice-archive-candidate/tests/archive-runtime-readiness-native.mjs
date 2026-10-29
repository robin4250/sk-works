// Dedicated disposable PG17 metadata proof. No GoTrue success, business rows,
// credentials, signatures or source-owner registration are fabricated.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';import path from 'node:path';
import {execFileSync,spawnSync} from 'node:child_process';
import pg from '../../fixture_dependencies/node_modules/pg/lib/index.js';
const root=process.cwd(),script=path.join(root,'tool/security/notice-archive-candidate/prepare-archive-runtime-readiness.py');
if(process.env.CI!=='true'||Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))throw Error('Disposable CI only, no hosted configuration');
const db=new pg.Client({host:'127.0.0.1',port:5432,user:'postgres',database:'postgres',password:'synthetic_only'});
const python=(args,input)=>execFileSync('python3',[script,...args],{encoding:'utf8',input,maxBuffer:1024*1024});
const sql=python(['--capture']);let checks=0;
await db.connect();
async function capture(){
 await db.query('begin read only');
 try{
  await assert.rejects(db.query('create table public.forbidden_readiness_probe(id integer)'),e=>e.code==='25006');
 }finally{await db.query('rollback');}
 await db.query('begin read only');
 try{const snap=(await db.query(sql)).rows[0].snapshot;assert.equal(snap.read_only,true);return snap;}finally{await db.query('rollback');}
}
function inspect(snapshot){const command=spawnSync('python3',[script,'--snapshot','-'],{encoding:'utf8',input:JSON.stringify(snapshot)});assert.equal(command.status,2);const result=JSON.parse(command.stdout);assert.equal(result.activation_allowed,false);assert.equal(result.source_owner_scope_verified,false);assert.equal(result.signature_authority_verified,false);assert.equal(result.capture_authenticity_verified,false);assert.equal(result.independent_custody_verified,false);return result;}
async function blocked(code){const snap=await capture(),r=inspect(snap);assert.equal(r.mechanical_catalogue_match,false);assert.ok(r.blockers.some(x=>x.startsWith(code)),JSON.stringify(r));checks++;console.log(JSON.stringify({fixture_catalogue_only:true,rejected:code,activation_allowed:false}));return snap;}
try{
 assert.equal((await db.query("select current_setting('server_version_num')::int/10000 version")).rows[0].version,17);
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname in('public','auth','private')")).rows[0].n,0);
 await db.query('create role anon;create role authenticated;create role service_role;create schema auth;create schema extensions;create extension pgcrypto with schema extensions');
 await db.query(`create function auth.jwt()returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid()returns uuid language sql stable as $$select(auth.jwt()->>'sub')::uuid$$;
 create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz,deleted_at timestamptz);
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);`);
 await db.query(await fs.readFile(new URL('./archive-readback-real-auth-fixture.sql',import.meta.url),'utf8'));
 for(const f of JSON.parse(await fs.readFile(new URL('../../free-worker-candidate/issuer/current-core-fixtures.json',import.meta.url),'utf8')))await db.query(f.definition);
 // Reproduce the root-reported missing prerequisites only. No production call.
 const absent=await blocked('required_function_missing:security_management_issuer_private.binding');
 assert.equal(absent.runtime_role_absent,true);assert.equal(absent.runtime_helper_absent,true);
 assert.equal(absent.registry.relation,null);assert.ok(!JSON.stringify(absent).includes('password_hash'));
 const protectedBefore=(await db.query("select jsonb_agg(jsonb_build_object('oid',oid,'owner',proowner,'source',md5(prosrc),'acl',proacl,'config',proconfig)order by oid) snapshot from pg_proc where oid in('private.require_reauthentication_session()'::regprocedure,'private.account_access_allowed()'::regprocedure)")).rows[0].snapshot;
 await capture();
 assert.deepEqual((await db.query("select jsonb_agg(jsonb_build_object('oid',oid,'owner',proowner,'source',md5(prosrc),'acl',proacl,'config',proconfig)order by oid) snapshot from pg_proc where oid in('private.require_reauthentication_session()'::regprocedure,'private.account_access_allowed()'::regprocedure)")).rows[0].snapshot,protectedBefore);checks++;
 // These are candidate-schema catalogue fixtures, never authentic populated
 // records or proof of a deployment. No archive runtime role SQL is applied.
 const management=await fs.readFile(new URL('../../free-worker-candidate/issuer/management-issuer.sql.review-only',import.meta.url),'utf8');
 await db.query(management);
 const bindingDefinition=management.match(/create function security_management_issuer_private\.binding[\s\S]*?end \$binding\$;/)[0].replace('create function','create or replace function');
 await db.query(await fs.readFile(new URL('../src/archive-readback-registry.sql.review-only',import.meta.url),'utf8'));
 const baseline=await capture(),matched=inspect(baseline);assert.equal(matched.mechanical_catalogue_match,true,JSON.stringify(matched));checks++;
 const raw=JSON.stringify(baseline);for(const forbidden of ['definition','prosrc','password_hash','manager_jwk'])assert.equal(raw.includes('"'+forbidden+'"'),false);
 await db.query('alter function security_management_issuer_private.binding(uuid,uuid,uuid,text,boolean)security invoker');await blocked('required_function_source_or_attributes_drift:');await db.query(bindingDefinition);
 await db.query('alter function security_management_issuer_private.binding(uuid,uuid,uuid,text,boolean)set search_path=public');await blocked('required_function_owner_or_config_drift:');await db.query(bindingDefinition);
 await db.query('grant execute on function security_management_issuer_private.binding(uuid,uuid,uuid,text,boolean)to anon');await blocked('private_function_acl_drift:');await db.query('revoke all on function security_management_issuer_private.binding(uuid,uuid,uuid,text,boolean)from anon');
 await db.query(bindingDefinition.replace(/as \$binding\$[\s\S]*\$binding\$;/, "as $binding$begin raise exception 'fixture_body_drift';end $binding$;"));await blocked('required_function_source_or_attributes_drift:');await db.query(bindingDefinition);
 await db.query('alter table archive_readback_private.authority_records alter column byte_length drop not null');await blocked('registry_column_contract_drift');await db.query('alter table archive_readback_private.authority_records alter column byte_length set not null');
 await db.query('create role readiness_untrusted_owner');
 await db.query('alter function security_management_issuer_private.binding(uuid,uuid,uuid,text,boolean)owner to readiness_untrusted_owner');await blocked('required_function_owner_or_config_drift:');await db.query('alter function security_management_issuer_private.binding(uuid,uuid,uuid,text,boolean)owner to postgres');
 await db.query('alter schema archive_readback_private owner to readiness_untrusted_owner');await blocked('protected_schema_owner_or_acl_drift:');await db.query('alter schema archive_readback_private owner to postgres');
 await db.query('alter table archive_readback_private.authority_records disable row level security');await blocked('registry_owner_or_protection_drift');await db.query('alter table archive_readback_private.authority_records enable row level security');
 await db.query('alter default privileges grant execute on functions to readiness_untrusted_owner');await blocked('unexpected_function_default_grants');await db.query('alter default privileges revoke execute on functions from readiness_untrusted_owner');
 await db.query('create role archive_readback_runtime');await blocked('runtime_installation_collision');await db.query('drop role archive_readback_runtime');
 await db.query("create function archive_readback_private.authorize_observation(text)returns void language plpgsql as $$begin raise exception 'collision_fixture';end$$");await blocked('runtime_installation_collision');await db.query('drop function archive_readback_private.authorize_observation(text)restrict');
 assert.deepEqual(await capture(),baseline);checks++;
 for(const table of ['auth.users','auth.sessions','public.user_secondary_credentials','private.master_admins','public.company_members','security_management_issuer_private.deployments','archive_readback_private.authority_records'])assert.equal((await db.query('select count(*)::int n from '+table)).rows[0].n,0);checks++;
 console.log(JSON.stringify({result:'PASS disposable Native PG17 read-only archive preapply catalogue',checks,
  production_queries:0,production_changed:false,runtime_role_sql_applied:false,rows_or_credentials_captured:false,
  fixture_catalogue_only:true,protected_catalogue_unchanged:true,capture_authenticity_verified:false,source_owner_scope_verified:false,signature_authority_verified:false,activation_allowed:false}));
}finally{await db.end();}
