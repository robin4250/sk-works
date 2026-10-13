// Synthetic local PostgreSQL only: no production database or person data.
import {readFile,readdir} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(resolve(process.argv[2])).href);
const db=new PGlite();
const read=p=>readFile(resolve(root,p),'utf8');
try {
 await db.exec(`create role authenticated;create role anon;create schema private;create schema auth;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create table companies(id uuid primary key);
 create table workers(id uuid primary key,company_id uuid,name text,user_id uuid);
 create table sites(id uuid primary key,company_id uuid,name text);
 create table route_assignments(id uuid primary key,company_id uuid,route_name text);
 create table company_members(company_id uuid,user_id uuid,role text);
 create table attendance_verifications(id uuid primary key,company_id uuid not null,worker_id uuid not null,site_id uuid,route_assignment_id uuid,event_type text not null,confirmed_at timestamptz not null,latitude numeric,longitude numeric);
 alter table attendance_verifications enable row level security;
 create policy own_insert on attendance_verifications for insert to authenticated with check(exists(select 1 from workers w where w.id=worker_id and w.company_id=attendance_verifications.company_id and w.user_id=auth.uid()));
 grant insert on attendance_verifications to authenticated;grant select on workers to authenticated;grant usage on schema auth to authenticated;`);
 const baseline=await read('supabase/migrations/20260919213000_add_app_notifications.sql');
 // Baseline table FK references auth.users.
 await db.exec('create table auth.users(id uuid primary key)');
 await db.exec(baseline);
 await db.exec('grant select on app_notifications to authenticated');
 await db.exec(await read('supabase/migrations/20261002095202_notify_management_of_attendance_location.sql'));
 const migration=(await readdir(resolve(root,'supabase/migrations'))).find(p=>p.endsWith('_notify_management_of_manual_clock_in.sql'));
 const policyBefore=(await db.query("select pg_get_expr(polqual,polrelid) qual,pg_get_expr(polwithcheck,polrelid) checks from pg_policy order by oid")).rows;
 const aclBefore=(await db.query("select proacl::text from pg_proc where oid='private.notify_management_of_attendance_location()'::regprocedure")).rows;
 await db.exec(await read('supabase/migrations/'+migration));
 assert.deepEqual((await db.query("select pg_get_expr(polqual,polrelid) qual,pg_get_expr(polwithcheck,polrelid) checks from pg_policy order by oid")).rows,policyBefore);
 assert.deepEqual((await db.query("select proacl::text from pg_proc where oid='private.notify_management_of_attendance_location()'::regprocedure")).rows,aclBefore);
 const uuid=i=>`10000000-0000-0000-0000-${String(i).padStart(12,'0')}`;
 const company=uuid(1),foreign=uuid(2),actor=uuid(3),worker=uuid(4),owner=uuid(5),admin=uuid(6),manager=uuid(7),member=uuid(8),foreignAdmin=uuid(9),site=uuid(10),route=uuid(11);
 await db.exec(`insert into companies values('${company}'),('${foreign}');
 insert into auth.users values('${actor}'),('${owner}'),('${admin}'),('${manager}'),('${member}'),('${foreignAdmin}');
 insert into workers values('${worker}','${company}','Fixture Worker','${actor}');
 insert into sites values('${site}','${company}','Fixture Site');insert into route_assignments values('${route}','${company}','Fixture Route');
 insert into company_members values('${company}','${owner}','owner'),('${company}','${admin}','admin'),('${company}','${manager}','manager'),('${company}','${member}','member'),('${foreign}','${foreignAdmin}','admin');
 set test.uid='${actor}';set role authenticated;`);
 const insert=async(id,{gps=false,event='clock_in',companyId=company}={})=>db.query('insert into attendance_verifications values($1,$2,$3,$4,$5,$6,$7,$8,$9)',[id,companyId,worker,null,route,event,'2026-10-11T01:25:00Z',gps?35:null,gps?139:null]);
 await insert(uuid(20));await insert(uuid(21),{gps:true});
 await assert.rejects(insert(uuid(20)),e=>e.code==='23505');
 await assert.rejects(insert(uuid(22),{companyId:foreign}),e=>e.code==='42501');
 await db.exec('begin');await insert(uuid(23));await db.exec('rollback');
 await insert(uuid(24),{event:'clock_out'});await insert(uuid(25),{event:'clock_out',gps:true});
 await db.exec('reset role');
 const notices=(await db.query('select * from app_notifications order by action_id,recipient_user_id')).rows;
 for(const id of [uuid(20),uuid(21)]) {
  const rows=notices.filter(n=>n.action_id===id);assert.equal(rows.length,3);
  assert.deepEqual(rows.map(n=>n.recipient_user_id).sort(),[owner,admin,manager].sort());
  for(const n of rows){assert.equal(n.action_key,'attendance_today');assert.equal(n.title,'出勤しました');assert.match(n.body,/Fixture Route/);assert.match(n.body,/2026-10-11 10:25/);}
 }
 assert.equal(notices.filter(n=>[uuid(22),uuid(23),uuid(24)].includes(n.action_id)).length,0);
 assert.equal(notices.filter(n=>n.action_id===uuid(25)&&n.action_key==='site_map').length,3);
 assert.equal((await db.query('select count(*)::int n from private.attendance_clock_in_notification_receipts')).rows[0].n,6);
 // Re-executing an identical committed source through a disposable replica
 // table tests receipt deduplication without rewriting production evidence.
 await db.exec('create table fixture_replay (like attendance_verifications including defaults);create trigger fixture_replay_notify after insert on fixture_replay for each row execute function private.notify_management_of_attendance_location();insert into fixture_replay select * from attendance_verifications where event_type=\'clock_in\'');
 assert.equal((await db.query('select count(*)::int n from app_notifications')).rows[0].n,9);
 await db.exec(`set test.uid='${owner}';set role authenticated`);
 assert.equal((await db.query('select * from app_notifications')).rows.length,3);
 await assert.rejects(db.query('select * from private.attendance_clock_in_notification_receipts'),e=>e.code==='42501');
 await db.exec(`reset role;set test.uid='${member}';set role authenticated`);
 assert.equal((await db.query('select * from app_notifications')).rows.length,0);
 console.log('PASS clock-in inbox: manual/GPS one notice per existing manager, route/time evidence, unchanged GPS clock-out, failed/rollback zero, retry receipts, recipient RLS and RPC ACL preserved');
} finally {await db.close();}
