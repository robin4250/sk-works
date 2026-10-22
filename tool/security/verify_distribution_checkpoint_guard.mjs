// Public synthetic fixture. Never load a production checkpoint or pinned SQL.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(process.env.PGLITE_PACKAGE||'@electric-sql/pglite');
const root=process.env.REFERRAL_SOURCE_ROOT
 ? pathToFileURL(resolve(process.env.REFERRAL_SOURCE_ROOT)+'/')
 : new URL('../../',import.meta.url);
const read=relative=>readFile(new URL(relative,root),'utf8');
const template=await readFile(new URL('distribution_checkpoint_guard.sql.fixture-template',import.meta.url),'utf8');
const snapshotSql=await readFile(new URL('distribution_checkpoint_snapshot.sql.fixture-only',import.meta.url),'utf8');
const install=await read('docs/candidates/app_distribution_off_install_20261020.sql.review-only');
const undo=await read('docs/candidates/app_distribution_off_undo_20261020.sql.review-only');
const baseline=await read('supabase/migrations/20261015012003_app_referral_invites.sql');
const hash=(value,algorithm='sha256')=>createHash(algorithm).update(value).digest('hex');
const blob=value=>hash(Buffer.concat([Buffer.from('blob '+Buffer.byteLength(value)+'\0'),Buffer.from(value)]),'sha1');
assert.equal(blob(install),'2d14a9e0377780b440444d8021fcff9d2ceed6e9','reviewed public OFF source changed');
for(const marker of ['__FIXTURE_BEFORE_SNAPSHOT_JSON__','__FIXTURE_AFTER_SNAPSHOT_JSON__','__REVIEWED_OFF_INSTALL_PAYLOAD__']) {
 assert.equal(template.split(marker).length,2,'fixture token must appear once');
}
assert(template.includes("(expected->'dependencies') <@ (actual->'dependencies')"));
const payload=install.replace(/(^|\n)begin;\n/,'$1').replace(/\ncommit;\s*$/,'\n');
const prefixTemplate=template.split('__REVIEWED_OFF_INSTALL_PAYLOAD__')[0];
export function buildFixtureCandidate(before) {
 const after=structuredClone(before);
 const dispatcher=after.functions.find(f=>f.schema==='private'&&f.name==='app_referral_dispatch');
 assert.equal(dispatcher.body_md5,'3ccced6e2d9a82d715e07c6b3f25b490');
 dispatcher.body_md5='7488617879c2b7b4e95d01870a4d84dc';
 return template.replace('__FIXTURE_BEFORE_SNAPSHOT_JSON__',()=>JSON.stringify(before))
 .replace('__FIXTURE_AFTER_SNAPSHOT_JSON__',()=>JSON.stringify(after))
 .replace('__REVIEWED_OFF_INSTALL_PAYLOAD__',()=>payload);
}
const prefix=before=>prefixTemplate.replace('__FIXTURE_BEFORE_SNAPSHOT_JSON__',()=>JSON.stringify(before));
const db=new PGlite();let assertions=0,stage='bootstrap';
const cases=[];
const eq=(a,b)=>{assert.deepEqual(a,b);assertions++;};
const scalar=async sql=>Object.values((await db.query(sql)).rows[0])[0];
const snapshot=async()=>(await db.query(snapshotSql)).rows[0].snapshot;
const unchanged=async()=>{
 eq(await scalar("select to_regclass('private.guard_ddl_must_not_run') is null"),true);
 eq(await scalar("select to_regclass('private.app_distribution_links') is null"),true);
 eq(await scalar("select to_regprocedure('public.app_distribution_snapshot(boolean)') is null"),true);
 eq(await scalar("select md5(prosrc) from pg_proc where oid='private.app_referral_dispatch(text,jsonb)'::regprocedure"),'3ccced6e2d9a82d715e07c6b3f25b490');
 eq(await scalar('select count(*)::int from private.app_referral_invitations'),0);
 eq(await scalar("select enabled=false and public_enabled=false and distribution_url='' from private.app_referral_settings where id"),true);
};
try {
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema private;
 create table auth.users(id uuid primary key);create table public.companies(id uuid primary key,name text);
 create table public.company_members(user_id uuid,company_id uuid,role text);create table public.user_profiles(user_id uuid,display_name text);
 create table private.account_deletion_access_restrictions(user_id uuid);
 create table private.master_admins(user_id uuid);
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql as $$select current_setting('test.allowed',true)='true'$$;
 create function public.is_current_user_master_admin() returns boolean language sql as $$select current_setting('test.master',true)='true'$$;
 grant usage on schema private,auth to authenticated;`);
 await db.exec(baseline);
 const before=await snapshot();
 stage='synthetic OID mismatch refusal';
 const wrongOid=structuredClone(before);
 wrongOid.functions[0].oid=Number(wrongOid.functions[0].oid)+1;
 await assert.rejects(()=>db.exec(prefix(wrongOid)+'CREATE TABLE private.guard_ddl_must_not_run(id integer);'),/invitation OFF checkpoint drift/);assertions++;
 await db.exec('rollback');await unchanged();
 cases.push('synthetic-oid-mismatch-refused-before-ddl');
 stage='valid fixture prefix';
 await db.exec(prefix(before)+'CREATE TABLE private.guard_ddl_must_not_run(id integer);');
 eq(await scalar("select to_regclass('private.guard_ddl_must_not_run') is not null"),true);
 await db.exec('rollback');await unchanged();cases.push('synthetic-valid-prefix');
 const mutations=[
 ['function-body',"create or replace function private.account_access_allowed() returns boolean language sql as $$select false$$"],
 ['function-acl',"revoke execute on function public.app_referral_snapshot() from authenticated"],
 ['table-acl',"grant select on public.company_members to authenticated"],
 ['policy',"create policy fixture_guard_drift on public.company_members using (true)"],
 ['constraint',"alter table public.company_members add constraint fixture_guard_check check (company_id is not null)"],
 ['feature-on',"update private.app_referral_settings set enabled=true where id"],
 ['public-on',"update private.app_referral_settings set public_enabled=true where id"],
 ['url',"update private.app_referral_settings set distribution_url='https://testflight.apple.com/join/FIXTURE1' where id"],
 ['new-function',"create function public.app_distribution_snapshot(p_master boolean) returns jsonb language sql as $$select '{}'::jsonb$$"],
 ['new-table',"create table private.app_distribution_links(singleton boolean)"],
 ];
 for(const [name,sql] of mutations) {
  stage='before-drift-'+name;await db.exec('begin;'+sql);
  await assert.rejects(()=>db.exec(prefix(before)+'CREATE TABLE private.guard_ddl_must_not_run(id integer);'),/invitation OFF checkpoint drift/);assertions++;
  await db.exec('rollback');await unchanged();cases.push(stage);
 }
 for(const [name,sql] of mutations.slice(5)) {
  stage='explicit-invariant-'+name;await db.exec('begin;'+sql);
  const invalidExpected=await snapshot();
  await assert.rejects(()=>db.exec(prefix(invalidExpected)+'CREATE TABLE private.guard_ddl_must_not_run(id integer);'),/OFF\/empty\/singleton\/new-object absence required/);assertions++;
  await db.exec('rollback');await unchanged();cases.push(stage);
 }
 stage='full synthetic before-guard/install/postguard';
 await db.exec(buildFixtureCandidate(await snapshot()));
 eq(await scalar("select enabled=false and public_enabled=false and distribution_url='' from private.app_referral_settings where id"),true);
 eq(await scalar("select testflight_url='' and web_url='' and public_url='' from private.app_distribution_links where singleton"),true);
 eq(await scalar('select count(*)::int from private.app_distribution_invitation_channels'),0);
 eq(await scalar('select count(*)::int from private.app_referral_invitations'),0);
 eq(await scalar("select md5(prosrc) from pg_proc where oid='private.app_referral_dispatch(text,jsonb)'::regprocedure"),'7488617879c2b7b4e95d01870a4d84dc');
 stage='synthetic unused OFF undo';
 await db.exec(undo);await unchanged();
 eq(hash(await read('docs/candidates/app_distribution_off_install_20261020.sql.review-only')),hash(install));
 eq(hash(await readFile(new URL('distribution_checkpoint_guard.sql.fixture-template',import.meta.url),'utf8')),hash(template));
 const result={schema:1,pass:true,assertions,prefix_cases:cases.length,full_roundtrip:true,fixture_only:true,
  template_sha256:hash(template),reviewed_public_install_blob:blob(install),
  production_checkpoints_loaded:0,production_database_operations:0,production_values_published:false,
  engine:(process.env.PGLITE_PACKAGE||'').includes('distribution_pg_adapter.mjs')?'native-pg17-adapter':'pglite',
  limits:['Expected snapshots are generated from the synthetic runtime catalog only.',
   'No production-shaped successful installation, real-user authentication or DDL concurrency claim.']};
 const output=process.env.DISTRIBUTION_CHECKPOINT_RESULT;
 if(output) await writeFile(output,JSON.stringify(result,null,2)+'\n');
 console.log(JSON.stringify(result));
} catch(error) {
 try{await db.exec('rollback');}catch{}
 console.error(JSON.stringify({pass:false,stage,error:String(error.message).slice(0,220),fixture_only:true,production_changed:false}));
 process.exitCode=1;
} finally {await db.close();}

