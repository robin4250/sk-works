import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite}=await import(process.env.PGLITE_PACKAGE||'@electric-sql/pglite');
const db=new PGlite();let assertions=0;
const eq=(a,b)=>{assert.deepEqual(a,b);assertions++;};
const scalar=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
const base=process.env.REFERRAL_SOURCE_ROOT||new URL('../',import.meta.url);
const old=await readFile(new URL('supabase/migrations/20261015012003_app_referral_invites.sql',String(base).endsWith('/')?base:String(base)+'/'),'utf8');
const install=await readFile(process.env.DISTRIBUTION_OFF_INSTALL||new URL('distribution_off_install.sql.review-only',import.meta.url),'utf8');
const undo=await readFile(process.env.DISTRIBUTION_OFF_UNDO||new URL('distribution_off_undo.sql.review-only',import.meta.url),'utf8');
const baseline=await readFile(process.env.DISTRIBUTION_BASE_SQL||new URL('../docs/candidates/app_distribution_channels_20261020.sql.review-only',import.meta.url),'utf8');
const bodies=sql=>[...sql.matchAll(/create (?:or replace )?function ([\w.]+)\([^)]*\)[\s\S]*?as \$\$([\s\S]*?)\$\$;/gi)].map(m=>[m[1],m[2]]);
eq(bodies(install),bodies(baseline));
try{
await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema private;
 create table auth.users(id uuid primary key);create table public.companies(id uuid primary key,name text);
 create table public.company_members(user_id uuid,company_id uuid,role text);create table public.user_profiles(user_id uuid,display_name text);
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql as $$select current_setting('test.allowed',true)='true'$$;
 create function public.is_current_user_master_admin() returns boolean language sql as $$select current_setting('test.master',true)='true'$$;
 grant usage on schema private,auth to authenticated;`);
await db.exec(old);
const beforeSettings=await scalar('select to_jsonb(s) from private.app_referral_settings s');
const beforeAcl=await scalar("select proacl::text from pg_proc where oid='private.app_referral_dispatch(text,jsonb)'::regprocedure");
for(const mutation of ["enabled=true","public_enabled=true","distribution_url='https://testflight.apple.com/join/FIXTURE1'"]){
 await db.exec('begin;update private.app_referral_settings set '+mutation+' where id');
 await assert.rejects(()=>db.exec(install),/OFF install requires/);assertions++;await db.exec('rollback');
 eq(await scalar('select to_jsonb(s) from private.app_referral_settings s'),beforeSettings);
}
await db.exec(install);eq(await scalar('select to_jsonb(s) from private.app_referral_settings s'),beforeSettings);
await db.exec(undo);eq(await scalar("select to_regclass('private.app_distribution_links') is null"),true);
eq(await scalar("select md5(prosrc) from pg_proc where oid='private.app_referral_dispatch(text,jsonb)'::regprocedure"),'3ccced6e2d9a82d715e07c6b3f25b490');
eq(await scalar("select proacl::text from pg_proc where oid='private.app_referral_dispatch(text,jsonb)'::regprocedure"),beforeAcl);
eq(await scalar('select to_jsonb(s) from private.app_referral_settings s'),beforeSettings);
await db.exec(install);
for(const mutation of ["update private.app_referral_settings set enabled=true where id","update private.app_distribution_links set testflight_url='https://testflight.apple.com/join/FIXTURE1' where singleton"]){
 await db.exec('begin;'+mutation);await assert.rejects(()=>db.exec(undo),/rollback refused/);assertions++;await db.exec('rollback');
 eq(await scalar("select to_regclass('private.app_distribution_links') is not null"),true);
}
await db.exec("begin;create or replace function public.app_distribution_snapshot(p_master boolean default false) returns jsonb language sql as $$select '{}'::jsonb$$");
await assert.rejects(()=>db.exec(undo),/function drift/);assertions++;await db.exec('rollback');
eq(await scalar("select to_regclass('private.app_distribution_links') is not null"),true);
await db.exec(undo);eq(await scalar('select count(*)::int from private.app_referral_invitations'),0);
console.log(JSON.stringify({pass:true,assertions,production_changed:false,messages_sent:0}));
}finally{await db.close();}
