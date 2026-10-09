// Synthetic isolated runtime only. No production credentials or connection.
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table public.companies(id uuid primary key);
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.workers(id uuid primary key,company_id uuid,affiliation text,user_id uuid);
 create table public.employee_registration_invites(id uuid primary key,company_id uuid,worker_id uuid,status text,approved_at timestamptz,password_changed_at timestamptz);
 create function private.source_notification_recipient_eligible(uuid,uuid) returns boolean language sql as $$select true$$;`);
 await db.exec(fs.readFileSync(new URL('../supabase/migrations/20261009000406_employee_initial_registration_status_history.sql',import.meta.url),'utf8'));
 await db.exec(`insert into companies values('${id(1)}'),('${id(2)}');insert into company_members values('${id(1)}','${id(3)}','admin'),('${id(1)}','${id(4)}','viewer');
 insert into workers values('${id(5)}','${id(1)}','employee','${id(6)}');
 insert into employee_registration_invites values('${id(7)}','${id(1)}','${id(5)}','invited',null,null);
 select set_config('request.jwt.claim.sub','${id(3)}',false);`);
 const read=()=>db.query(`select * from employee_initial_registration_status_rows('${id(1)}')`);
 await assert.rejects(read,/unavailable/);
 await db.exec(`insert into private.employee_initial_registration_rollout values('${id(1)}',true)`);
 assert.equal((await read()).rows[0].initial_registration_completed,false); // user_id exists already.
 await db.exec(`update employee_registration_invites set status='approval_pending',password_changed_at=now()`);
 assert.equal((await read()).rows[0].initial_registration_completed,false);
 await db.exec(`update employee_registration_invites set status='approved'`);
 assert.equal((await read()).rows[0].initial_registration_completed,false);
 await db.exec(`update employee_registration_invites set approved_at=now()`);
 assert.equal((await read()).rows[0].initial_registration_completed,true);
 const record=(company,worker,invite,event,state,confirm)=>db.query('select record_employee_initial_registration_delivery($1,$2,$3,$4,$5,$6)',[id(company),id(worker),id(invite),id(event),state,confirm]);
 await assert.rejects(record(1,5,7,8,'manual_sent',false),/explicit/);
 await assert.rejects(record(1,5,9,8,'unknown',false),/invitation not found/);
 await record(1,5,7,8,'manual_sent',true);await record(1,5,7,8,'manual_sent',true);
 assert.equal((await db.query('select count(*)::int n from private.employee_initial_registration_delivery_history')).rows[0].n,1);
 await assert.rejects(record(1,5,7,8,'unknown',false),/identity differs/);
 await record(1,5,7,9,'unknown',false);
 assert.equal((await read()).rows[0].delivery_state,'unknown');
 await db.exec(`select set_config('request.jwt.claim.sub','${id(4)}',false)`);
 await assert.rejects(read,/management permission/);
 await db.exec(`select set_config('request.jwt.claim.sub','${id(3)}',false)`);
 await assert.rejects(db.query(`select * from employee_initial_registration_status_rows('${id(2)}')`),/management permission/);
 await db.exec(`create or replace function private.source_notification_recipient_eligible(uuid,uuid) returns boolean language sql as $$select false$$;`);
 await assert.rejects(read,/management permission/);
 assert.equal((await db.query("select has_function_privilege('anon','public.employee_initial_registration_status_rows(uuid)','EXECUTE') allowed")).rows[0].allowed,false);
 assert.equal((await db.query("select has_function_privilege('authenticated','private.require_employee_initial_registration_access(uuid)','EXECUTE') allowed")).rows[0].allowed,false);
 assert.equal((await db.query("select status from employee_registration_invites")).rows[0].status,'approved');
 for(const role of ['anon','authenticated']){
  assert.equal((await db.query(`select has_table_privilege('${role}','private.employee_initial_registration_delivery_history','SELECT') allowed`)).rows[0].allowed,false);
 }
 console.log('PASS: OFF gate, exact company, admin restriction, explicit completion, manual confirmation, unknown history and idempotent identity');
}finally{await db.close();}
