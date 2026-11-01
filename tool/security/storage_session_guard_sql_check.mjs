import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const here=path.dirname(fileURLToPath(import.meta.url));
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);const db=new PGlite();
const actor='00000000-0000-4000-8000-000000000001',other='00000000-0000-4000-8000-000000000002',session='00000000-0000-4000-8000-000000000003';
let checks=0;
async function read(claims,expected,bucket='worker-documents',role='authenticated'){
 await db.exec('begin');try{await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify(claims)]);await db.exec(`set local role ${role}`);
 assert.equal((await db.query('select count(*)::int n from storage.objects where bucket_id=$1',[bucket])).rows[0].n,expected);checks++;
 }finally{await db.exec('rollback');}
}
try{
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema private;create schema storage;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
 create table auth.users(id uuid,banned_until timestamptz);
 create table auth.sessions(id uuid,user_id uuid,not_after timestamptz);
 create table private.account_deletion_access_restrictions(user_id uuid);
 create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())$$;
 create table storage.objects(bucket_id text,name text,payload text);
 alter table storage.objects enable row level security;
 grant usage on schema auth,private,storage to anon,authenticated;grant select on storage.objects to anon,authenticated;
 create policy fixture_existing_read on storage.objects for select to authenticated using(true);
 insert into storage.objects values('worker-documents','fixture','unchanged'),('unrelated-fixture','other','unchanged');
 insert into auth.users values('${actor}',null);
 insert into auth.sessions values('${session}','${actor}',null);`);
 const valid={sub:actor,role:'authenticated',session_id:session};const before=(await db.query('select * from storage.objects order by bucket_id')).rows;
 const authAcl=(await db.query("select relacl::text a from pg_class where oid='auth.sessions'::regclass")).rows;
 await db.exec(fs.readFileSync(path.join(here,'storage_session_guard.sql.review-only'),'utf8'));
 await read({sub:actor,role:'authenticated'},1);
 await db.exec('update private.storage_session_guard_rollout set enabled=true');
 await db.exec("update auth.users set banned_until=now()+interval '1 hour'");await read(valid,0);
 await db.exec("update auth.users set banned_until=now()-interval '1 second'");await read(valid,1);
 await db.exec('update auth.users set banned_until=null');
 await read(valid,1);await read({sub:actor,role:'authenticated'},0);await read({...valid,session_id:'malformed'},0);
 await read({...valid,session_id:other},0);await read({...valid,sub:other},0);await read({...valid,role:'anon'},0);
 await read({},0,'worker-documents','anon');await read({sub:actor,role:'authenticated'},1,'unrelated-fixture');
 await db.exec("update auth.sessions set not_after=now()-interval '1 second'");await read(valid,0);
 await db.exec('update auth.sessions set not_after=null');await read(valid,1);
 await db.exec(`insert into private.account_deletion_access_restrictions values('${actor}')`);await read(valid,0);
 await db.exec('delete from private.account_deletion_access_restrictions;delete from auth.sessions');await read(valid,0);
 await db.exec('delete from private.storage_session_guard_rollout');await read(valid,0);
 await db.exec('insert into private.storage_session_guard_rollout values(true,false)');await read(valid,1);
 assert.deepEqual((await db.query("select relacl::text a from pg_class where oid='auth.sessions'::regclass")).rows,authAcl);
 assert.equal((await db.query("select has_table_privilege('authenticated','private.storage_session_guard_rollout','select') a")).rows[0].a,false);
 assert.equal((await db.query("select has_function_privilege('anon','private.worker_storage_session_allowed()','execute') a")).rows[0].a,false);
 await db.exec('drop policy worker_document_live_session_guard on storage.objects;drop function private.worker_storage_session_allowed();drop table private.storage_session_guard_rollout');
 await read(valid,1);assert.deepEqual((await db.query('select * from storage.objects order by bucket_id')).rows,before);
 console.log(`PASS ${checks} session guard SQL checks; unrelated bucket unchanged; OFF and original policy restore preserved rows; no session-table client grants. Synthetic SQL claims are not GoTrue HTTP proof.`);
}catch(e){console.error(e.code??'',e.message);process.exitCode=1;}finally{await db.close();}
