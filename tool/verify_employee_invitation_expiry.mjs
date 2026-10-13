import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const {PGlite}=await import(process.env.PGLITE_MODULE??'@electric-sql/pglite');
const db=new PGlite();
const actor='30000000-0000-0000-0000-000000000001',other='30000000-0000-0000-0000-000000000002';
try {
 await db.exec(`create schema auth; create role anon; create role authenticated; create table public.companies(id uuid primary key); create table public.workers(id uuid primary key); create table auth.users(id uuid primary key); create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;`);
 await db.exec(await fs.readFile(new URL('../supabase/tests/fixtures/employee_invitation_expiry_before.sql',import.meta.url),'utf8'));
 const migration=await fs.readFile(new URL('../supabase/migrations/20261013210756_guard_employee_invitation_initial_password_expiry.sql',import.meta.url),'utf8');
 await db.exec(`insert into public.companies values('10000000-0000-0000-0000-000000000001'); insert into public.workers values('20000000-0000-0000-0000-000000000001'); insert into auth.users values('${actor}'),('${other}'); insert into public.employee_registration_invites(company_id,worker_id,auth_user_id,name,phone_e164,created_by,expires_at) values('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','${actor}','Synthetic Employee','synthetic-phone','${other}',now()-interval '1 day');`);
 const invoke=async(user=actor,role='authenticated')=>{await db.exec(`select set_config('request.jwt.claim.sub','${user}',false);set role ${role};`);try{await db.exec('select public.mark_employee_initial_password_changed()');}finally{await db.exec('reset role');}};
 const row=async()=>(await db.query('select status,password_changed_at,expires_at from public.employee_registration_invites')).rows[0];
 // Prove the former, latest production function permitted bypassing state-read expiry.
 await invoke();assert.equal((await row()).status,'profile_pending');
 await db.exec("update public.employee_registration_invites set status='invited',password_changed_at=null");
 await db.exec(migration);await db.exec(migration);
 let before=await row();await assert.rejects(invoke(),/pending employee invitation not found/);assert.deepEqual(await row(),before);
 await assert.rejects(invoke(other),/pending employee invitation not found/);assert.deepEqual(await row(),before);
 await assert.rejects(invoke('', 'anon'),/permission denied/);assert.deepEqual(await row(),before);
 await db.exec("update public.employee_registration_invites set expires_at=now()+interval '1 day'");
 await invoke();assert.equal((await row()).status,'profile_pending');assert.ok((await row()).password_changed_at);
 before=await row();await invoke();assert.deepEqual(await row(),before,'repeat preserves original change timestamp');
 await db.exec("update public.employee_registration_invites set expires_at=now()-interval '1 day'");
 before=await row();await invoke();assert.deepEqual(await row(),before,'already started onboarding remains usable');
 for(const status of ['cancelled','approved','approval_pending']){await db.exec(`update public.employee_registration_invites set status='${status}'`);before=await row();await assert.rejects(invoke(),/pending employee invitation not found/);assert.deepEqual(await row(),before);}
 const acl=(await db.query("select has_function_privilege('anon','public.mark_employee_initial_password_changed()','execute') as anon,has_function_privilege('authenticated','public.mark_employee_initial_password_changed()','execute') as authenticated")).rows[0];assert.deepEqual(acl,{anon:false,authenticated:true});
 await db.exec("create or replace function public.mark_employee_initial_password_changed() returns void language plpgsql as $$begin null;end $$");
 await assert.rejects(db.exec(migration),/function changed; review required/);
 console.log('PASS: old bypass reproduced; expired/other/anon/cancelled denied; valid/repeat/in-progress preserved; ACL unchanged; replay and definition guard checked.');
} finally {await db.close();}
