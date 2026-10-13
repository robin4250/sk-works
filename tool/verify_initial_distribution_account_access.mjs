// Disposable in-memory database only; no network or production credentials.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const root=new URL('../',import.meta.url);
const read=p=>fs.readFileSync(new URL(p,root),'utf8');
const company='10000000-0000-0000-0000-000000000001';
const owner='20000000-0000-0000-0000-000000000001';
const admin='20000000-0000-0000-0000-000000000002';
const employee='20000000-0000-0000-0000-000000000003';
const outsider='20000000-0000-0000-0000-000000000004';
const as=async(role,id)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role '+role);};
const state=async()=> (await db.query('select public.initial_registration_distribution_settings() value')).rows[0].value;
const save=async url=>db.query('select public.save_initial_registration_distribution_settings($1)',[url]);
const unchanged=async()=>{await db.exec('reset role');return (await db.query('select employee_testflight_url,updated_at from companies')).rows;};
try {
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table public.companies(id uuid primary key,employee_testflight_url text,updated_at timestamptz);
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table private.account_deletion_access_restrictions(user_id uuid primary key);
 grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;
 revoke all on companies,company_members,private.account_deletion_access_restrictions from public,anon,authenticated;`);
 await db.query('insert into companies values($1,$2,now())',[company,'https://testflight.apple.com/join/Original']);
 for(const [id,role] of [[owner,'owner'],[admin,'admin'],[employee,'employee']]) await db.query('insert into company_members values($1,$2,$3)',[company,id,role]);
 await db.exec(read('tool/initial_distribution_before_fixture.sql'));
 await db.exec('revoke all on function public.initial_registration_distribution_settings(),public.save_initial_registration_distribution_settings(text) from public;grant execute on function public.initial_registration_distribution_settings(),public.save_initial_registration_distribution_settings(text) to anon,authenticated;');
 await as('authenticated',owner);assert.equal((await state()).testflight_url,'https://testflight.apple.com/join/Original');
 const before=await unchanged();
 const migration=read('supabase/migrations/20261013191956_guard_initial_distribution_account_access.sql');
 await db.exec(migration);assert.deepEqual(await unchanged(),before,'migration preserves saved distribution URL and update timestamp');
 for(const id of [owner,admin]) {await as('authenticated',id);await save('https://testflight.apple.com/join/Registered');assert.equal((await state()).testflight_url,'https://testflight.apple.com/join/Registered');}
 const registered=await unchanged();
 for(const id of [employee,outsider,'']) {await as('authenticated',id);await assert.rejects(state());await assert.rejects(save('https://testflight.apple.com/join/Denied'));}
 await db.exec('reset role');await db.query('insert into private.account_deletion_access_restrictions values($1)',[owner]);
 await as('authenticated',owner);await assert.rejects(state(),/アカウント/);await assert.rejects(save('https://testflight.apple.com/join/Restricted'),/アカウント/);
 await as('anon',owner);await assert.rejects(state(),/permission denied/);await assert.rejects(save('https://testflight.apple.com/join/Anonymous'),/permission denied/);
 assert.deepEqual(await unchanged(),registered,'denied and restricted callers do not modify saved data');
 await db.exec(migration);assert.deepEqual(await unchanged(),registered,'replay preserves saved data');
 const acl=(await db.query("select has_function_privilege('anon','public.initial_registration_distribution_settings()','execute') read_anon,has_function_privilege('anon','public.save_initial_registration_distribution_settings(text)','execute') save_anon,has_function_privilege('authenticated','public.initial_registration_distribution_settings()','execute') read_member")).rows[0];
 assert.deepEqual(acl,{read_anon:false,save_anon:false,read_member:true});
 await db.exec("create or replace function public.initial_registration_distribution_settings() returns jsonb language plpgsql stable security definer set search_path='' as $$begin return '{}'::jsonb;end$$");
 await assert.rejects(db.exec(migration),/distribution prerequisite differs/);await db.exec('rollback');
 console.log('PASS owner/admin compatibility, anonymous and restricted account denial, data preservation, replay and prerequisite guard');
} finally {await db.close();}
