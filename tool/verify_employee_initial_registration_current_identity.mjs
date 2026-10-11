// Isolated synthetic PGlite only; no production credentials or connection.
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const sql=name=>fs.readFileSync(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8');
const addition=sql('20261009010620_employee_initial_registration_current_identity.sql');
try {
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table public.companies(id uuid primary key);
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.workers(id uuid primary key,company_id uuid,affiliation text,user_id uuid);
 create table public.employee_registration_invites(id uuid primary key,company_id uuid,worker_id uuid,auth_user_id uuid unique,status text,approved_at timestamptz,password_changed_at timestamptz);
 create function private.source_notification_recipient_eligible(uuid,uuid) returns boolean language sql as $$select true$$;`);
 await db.exec(sql('20261009000406_employee_initial_registration_status_history.sql'));
 const old=await db.query("select pg_get_functiondef('public.employee_initial_registration_status_rows(uuid)'::regprocedure) def");
 await db.exec(addition);
 assert.deepEqual(await db.query("select pg_get_functiondef('public.employee_initial_registration_status_rows(uuid)'::regprocedure) def"),old);
 await db.exec(`insert into companies values('${id(1)}'),('${id(2)}');
 insert into company_members values('${id(1)}','${id(3)}','admin'),('${id(1)}','${id(4)}','viewer');
 insert into workers values('${id(5)}','${id(1)}','employee','${id(6)}'),('${id(15)}','${id(1)}','employee',null);
 insert into employee_registration_invites values
 ('${id(7)}','${id(1)}','${id(5)}','${id(6)}','approval_pending',null,now()),
 ('${id(8)}','${id(1)}','${id(5)}','${id(9)}','approved',now(),now()),
 ('${id(16)}','${id(1)}','${id(15)}',null,'approved',now(),now());
 select set_config('request.jwt.claim.sub','${id(3)}',false);`);
 const read=()=>db.query(`select * from employee_initial_registration_status_rows_v2('${id(1)}')`);
 await assert.rejects(read,/unavailable/);
 await db.exec(`insert into private.employee_initial_registration_rollout values('${id(1)}',true)`);
 let rows=(await read()).rows;
 assert.equal(rows.filter(r=>r.current_invitation).length,1);
 assert.equal(rows.find(r=>r.current_invitation).invitation_id,id(7));
 assert.equal(rows.find(r=>r.current_invitation).initial_registration_completed,false);
 assert.equal(rows.find(r=>r.invitation_id===id(8)).initial_registration_completed,true); // Historical completion retained separately.
 assert.equal(rows.find(r=>r.invitation_id===id(8)).current_invitation,false);
 assert.equal(rows.find(r=>r.invitation_id===id(16)).current_invitation,false); // NULL never equals NULL.
 assert.equal(rows.every(r=>!('auth_user_id' in r)&&!('user_id' in r)&&!('password' in r)),true);
 await db.exec(`update workers set user_id=null where id='${id(5)}'`);
 assert.equal((await read()).rows.some(r=>r.current_invitation),false);
 await db.exec(`update workers set user_id='${id(9)}' where id='${id(5)}'`);
 assert.equal((await read()).rows.find(r=>r.current_invitation).invitation_id,id(8));
 await db.exec(`update workers set user_id='${id(99)}' where id='${id(5)}'`);
 assert.equal((await read()).rows.some(r=>r.current_invitation),false);
 await db.exec(`select set_config('request.jwt.claim.sub','${id(4)}',false)`);
 await assert.rejects(read,/management permission/);
 await db.exec(`select set_config('request.jwt.claim.sub','${id(3)}',false)`);
 await assert.rejects(db.query(`select * from employee_initial_registration_status_rows_v2('${id(2)}')`),/management permission/);
 assert.equal((await db.query("select has_function_privilege('anon','public.employee_initial_registration_status_rows_v2(uuid)','EXECUTE') allowed")).rows[0].allowed,false);
 assert.equal((await db.query('select count(*)::int n from private.employee_initial_registration_delivery_history')).rows[0].n,0);
 await db.exec('alter table employee_registration_invites drop constraint employee_registration_invites_auth_user_id_key');
 await assert.rejects(db.exec(addition),/validated single auth_user_id uniqueness required/);
 console.log('PASS: current identity marker, historical completion retained, NULL/absent link unknown, OFF/admin/company ACL and unique guard');
} finally { await db.close(); }
