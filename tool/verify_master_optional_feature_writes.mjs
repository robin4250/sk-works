// Disposable SQL fixture only. Never point this at an application database.
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const runtime=await import(pathToFileURL(resolve(process.argv[2])).href);
const pgMode=process.argv.includes('--postgres');
const Client=runtime.Client??runtime.default?.Client;
const db=pgMode?new Client({connectionString:process.env.FIXTURE_DATABASE_URL}):new runtime.PGlite();
if(pgMode)await db.connect();
const exec=sql=>pgMode?db.query(sql):db.exec(sql);
const uid='10000000-0000-0000-0000-000000000001',company='10000000-0000-0000-0000-000000000002',worker='10000000-0000-0000-0000-000000000003',vehicle='10000000-0000-0000-0000-000000000004',route='10000000-0000-0000-0000-000000000005';
let counter=100;
const id=()=>`10000000-0000-0000-0000-${String(counter++).padStart(12,'0')}`;
try{
 await exec(`create role authenticated;create role anon;create role service_role;create schema private;create schema auth;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.uid',true),'')::uuid$$;
 create table private.master_feature_settings(feature_key text primary key,enabled boolean not null,updated_at timestamptz,updated_by uuid);
 insert into private.master_feature_settings (feature_key,enabled) values('vehicle_management',true),('route_assignment',true);
 create table workers(id uuid primary key,company_id uuid,user_id uuid,status text);
 insert into workers values('${worker}','${company}','${uid}','active');
 create table vehicles(id uuid primary key,company_id uuid,odometer_km numeric,name text,updated_by uuid,updated_at timestamptz);
 create table route_assignments(id uuid primary key,company_id uuid,vehicle_id uuid,name text);
 create table route_stops(id uuid primary key,company_id uuid,route_assignment_id uuid,name text);
 create table work_vehicle_route_selections(company_id uuid,worker_id uuid,work_date date,vehicle_id uuid,route_assignment_id uuid,primary key(company_id,worker_id,work_date));
 create table work_attendance_selections(like work_vehicle_route_selections including all);
 create table gps_auto_attendance_schedules(company_id uuid,worker_id uuid,route_assignment_id uuid,enabled boolean,primary key(company_id,worker_id));
 create table attendance_verifications(id uuid primary key,company_id uuid,worker_id uuid,vehicle_id uuid,route_assignment_id uuid,event_type text,source_clock_in_id uuid);
 create table vehicle_usage_claims(source_clock_in_id uuid primary key,company_id uuid,vehicle_id uuid,driver_worker_id uuid,work_date date,source_clock_out_id uuid,ended_at timestamptz);
 create table vehicle_meter_events(id uuid primary key,source_clock_in_id uuid,company_id uuid,vehicle_id uuid,driver_worker_id uuid,work_date date,previous_km numeric,current_km numeric,recorded_by uuid);
 grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;
 grant select,insert,update on vehicles,route_assignments,route_stops,work_vehicle_route_selections,work_attendance_selections,gps_auto_attendance_schedules,attendance_verifications to authenticated;
 alter table attendance_verifications enable row level security;
 create policy fixture_own on attendance_verifications to authenticated using(worker_id='${worker}'::uuid) with check(worker_id='${worker}'::uuid);
 set fixture.uid='${uid}';`);
 await exec(`create function public.is_current_user_master_admin() returns boolean language sql stable as $$select auth.uid()='${uid}'::uuid$$`);
 const masterBaseline=await readFile(resolve(root,'supabase/migrations/20260930065000_add_master_feature_controls.sql'),'utf8');
 await exec(masterBaseline.slice(masterBaseline.indexOf('create or replace function public.current_master_feature_flags')));
 const routineBefore=(await db.query("select oid,md5(pg_get_functiondef(oid)) hash,proacl::text from pg_proc where proname in ('current_master_feature_flags','set_master_feature_enabled') order by oid")).rows;
 const before=(await db.query("select oid,relacl::text,relrowsecurity from pg_class where relnamespace='public'::regnamespace order by oid")).rows;
 const migration=(await readdir(resolve(root,'supabase/migrations'))).find(f=>f.endsWith('_guard_master_optional_feature_writes.sql'));
 const migrationSql=await readFile(resolve(root,'supabase/migrations',migration),'utf8');
 // Inject a failure at the final CREATE TRIGGER; the preceding guards must roll back.
 const lateFailure=migrationSql.replace('before insert or update on public.attendance_verifications\nfor each row execute','before insert or update on public.vehicles\nfor each row execute');
 await assert.rejects(exec(lateFailure),e=>e.code==='42710');
 await exec('rollback');
 assert.equal((await db.query("select to_regprocedure('private.require_master_optional_feature(text)') missing")).rows[0].missing,null);
 assert.equal((await db.query("select count(*)::int n from pg_trigger where tgname='zz_master_optional_write_guard'")).rows[0].n,0);
 await exec(migrationSql);
 assert.deepEqual((await db.query("select oid,md5(pg_get_functiondef(oid)) hash,proacl::text from pg_proc where proname in ('current_master_feature_flags','set_master_feature_enabled') order by oid")).rows,routineBefore);
 assert.deepEqual((await db.query("select oid,relacl::text,relrowsecurity from pg_class where relnamespace='public'::regnamespace order by oid")).rows,before);
 await exec(`insert into vehicles values('${vehicle}','${company}',100,'Fixture',null,null);
 insert into route_assignments values('${route}','${company}',null,'Fixture');
 insert into work_vehicle_route_selections values('${company}','${worker}','2026-10-11','${vehicle}','${route}');
 insert into gps_auto_attendance_schedules values('${company}','${worker}','${route}',true);
 insert into attendance_verifications(id,company_id,worker_id,vehicle_id,route_assignment_id,event_type) values('${id()}','${company}','${worker}','${vehicle}','${route}','clock_in');
 update private.master_feature_settings set enabled=false;set role authenticated;`);
 const fail=sql=>assert.rejects(db.query(sql),e=>e.code==='P0001');
 await fail(`insert into vehicles values('${id()}','${company}',0,'New',null,null)`);
 await fail(`update vehicles set name='Changed' where id='${vehicle}'`);
 await fail(`update vehicles set odometer_km=101,updated_by='${uid}' where id='${vehicle}'`);
 await fail(`insert into route_assignments values('${id()}','${company}',null,'New')`);
 await fail(`insert into route_stops values('${id()}','${company}','${route}','New')`);
 // UPSERT preserves old selected source; clearing is allowed, reselecting is not.
 await exec(`insert into work_vehicle_route_selections values('${company}','${worker}','2026-10-11','${vehicle}','${route}') on conflict(company_id,worker_id,work_date) do update set vehicle_id=excluded.vehicle_id,route_assignment_id=excluded.route_assignment_id;`);
 await fail(`insert into work_vehicle_route_selections values('${company}','${worker}','2026-10-12',null,'${route}')`);
 await fail(`insert into work_attendance_selections values('${company}','${worker}','2026-10-11',null,'${route}')`);
 await fail(`insert into gps_auto_attendance_schedules values('${company}','${id()}','${route}',true)`);
 await exec(`update gps_auto_attendance_schedules set enabled=false;`);
 await fail(`update gps_auto_attendance_schedules set enabled=true`);
 const attendance=(event,v,r,w=worker)=>`insert into attendance_verifications(id,company_id,worker_id,vehicle_id,route_assignment_id,event_type) values('${id()}','${company}','${w}',${v?`'${v}'`:'null'},${r?`'${r}'`:'null'},'${event}')`;
 await exec(`reset role;create function private.fixture_normalize_destination() returns trigger language plpgsql as $$begin
 if current_setting('fixture.normalize_route',true)='on' then NEW.route_assignment_id:='${route}'; end if;
 return NEW;end$$;
 create trigger attendance_fixture_normalizer before insert on attendance_verifications for each row execute function private.fixture_normalize_destination();
 set fixture.normalize_route='on';set role authenticated;`);
 await fail(attendance('clock_in',null,null)); // Final gate sees an earlier trigger's normalized route.
 await exec("set fixture.normalize_route='off'");
 await fail(attendance('clock_in',null,route)); // manual OR previously scheduled GPS start
 await fail(attendance('clock_in',vehicle,null));
 await exec(attendance('clock_out',vehicle,route)); // active source continuation
 await exec(attendance('clock_in',null,null)); // ordinary manual attendance
 await assert.rejects(db.query(attendance('clock_in',null,null,id())),e=>e.code==='42501');
 await exec(`update work_vehicle_route_selections set vehicle_id=null,route_assignment_id=null;`);
 await fail(`update work_vehicle_route_selections set route_assignment_id='${route}'`);
 await exec(`reset role;update private.master_feature_settings set enabled=true where feature_key='route_assignment';set role authenticated;`);
 await exec(attendance('clock_in',null,route)); // vehicle OFF must not disable vehicleless route
 await fail(attendance('clock_in',vehicle,route));
 // Completed-driver meter finalization: exact same transaction signed snapshot only.
 const source=id(),checkout=id(),event=id();
 await exec(`reset role;update private.master_feature_settings set enabled=true where feature_key='vehicle_management';
 insert into attendance_verifications(id,company_id,worker_id,vehicle_id,route_assignment_id,event_type) values('${source}','${company}','${worker}','${vehicle}','${route}','clock_in');
 update private.master_feature_settings set enabled=false where feature_key='vehicle_management';`);
 await exec(`insert into attendance_verifications(id,company_id,worker_id,vehicle_id,route_assignment_id,event_type) values('${checkout}','${company}','${worker}','${vehicle}','${route}','clock_out');
 update attendance_verifications set source_clock_in_id='${source}' where id='${checkout}';
 insert into vehicle_usage_claims values('${source}','${company}','${vehicle}','${worker}','2026-10-11','${checkout}',now());
 begin;insert into vehicle_meter_events values('${event}','${source}','${company}','${vehicle}','${worker}','2026-10-11',100,105,'${uid}');
 set role authenticated;update vehicles set odometer_km=105,updated_by='${uid}',updated_at=now() where id='${vehicle}';commit;reset role;`);
 await exec('set role authenticated');
 await fail(`update vehicles set odometer_km=106,updated_by='${uid}' where id='${vehicle}'`);
 await assert.rejects(db.query("select private.require_master_optional_feature('route_assignment')"),e=>e.code==='42501');
 await exec('reset role');
 // An absent feature row keeps the legacy ON default; explicit OFF still rejects.
 await exec("delete from private.master_feature_settings where feature_key='vehicle_management';set role authenticated");
 await exec(attendance('clock_in',vehicle,route));
 await exec("reset role;insert into private.master_feature_settings (feature_key,enabled) values('vehicle_management',false)");
 for(const role of ['anon','authenticated','service_role']) assert.equal((await db.query(`select has_function_privilege('${role}','private.guard_master_optional_feature_write()','execute') allowed`)).rows[0].allowed,false);
 if(pgMode){
  const a=new Client({connectionString:process.env.FIXTURE_DATABASE_URL}),b=new Client({connectionString:process.env.FIXTURE_DATABASE_URL});
  await a.connect();await b.connect();
  try{
   await db.query("update private.master_feature_settings set enabled=true where feature_key='route_assignment'");
   await a.query(`set fixture.uid='${uid}'`);await a.query('begin');await a.query("select public.set_master_feature_enabled('route_assignment',false)");
   let settled=false;
   const blocked=b.query(attendance('clock_in',null,route)).then(()=>{settled=true;throw Error('OFF race allowed new start');},e=>{settled=true;assert.equal(e.code,'P0001');});
   await new Promise(resolve=>setTimeout(resolve,100));assert.equal(settled,false,'new start must wait for OFF setter');
   await a.query('commit');await blocked;
  }finally{await a.end();await b.end();}
 }
 console.log(`PASS master optional write gates (${pgMode?'PostgreSQL 17 + concurrent OFF race':'PGlite'}): preserved ACL/RLS, OFF/new writes, existing continuation, signed meter, vehicleless route`);
}finally{if(pgMode)await db.end();else await db.close();}
