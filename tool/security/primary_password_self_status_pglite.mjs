// Synthetic SQL runtime only, never a GoTrue/JWT/production proof.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const actor='40000000-0000-0000-0000-000000000001',sid='40000000-0000-0000-0000-000000000002';
try{
 await db.exec(`create role authenticated;create role anon;create role service_role;
  create schema auth;create schema private;grant usage on schema auth,private to authenticated;
  create function auth.jwt() returns jsonb language sql stable as $$select nullif(current_setting('request.jwt.claims',true),'')::jsonb$$;
  create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
  create table auth.users(id uuid primary key,encrypted_password text,is_anonymous boolean,banned_until timestamptz);
  create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
  create table private.account_deletion_access_restrictions(user_id uuid primary key);
  create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $function$
 select auth.uid() is not null and not exists(
  select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())
$function$;
  revoke all on function private.account_access_allowed() from public;
  grant execute on function private.account_access_allowed() to anon,authenticated,service_role;`);
 await db.query('insert into auth.users values($1,\'\',false,null)',[actor]);
 await db.query('insert into auth.sessions values($1,$2,null)',[sid,actor]);
 await db.exec(await fs.readFile('docs/candidates/primary_password_self_status_20261025.sql.review-only','utf8'));
 const claims={sub:actor,session_id:sid,role:'authenticated'};
 const call=async(jwt=claims,role='authenticated')=>{
  await db.exec('begin');
  try{
   assert.ok(['authenticated','anon','service_role'].includes(role));
   await db.exec(`set local role ${role}`);
   await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify(jwt)]);
   return (await db.query('select public.primary_password_configured() v')).rows[0].v;
  }finally{await db.exec('rollback');}
 };
 assert.equal(await call(),false);
 await db.query("update auth.users set encrypted_password='synthetic-nonempty-fixture' where id=$1",[actor]);
 assert.equal(await call(),true);
 for(const jwt of [{...claims,session_id:undefined},{...claims,session_id:'malformed'},
  {...claims,session_id:actor},{...claims,sub:sid},{...claims,role:'service_role'},
  {...claims,is_anonymous:true},{...claims,is_anonymous:'false'}]){
  await assert.rejects(call(jwt),e=>e.code==='42501');
 }
 for(const role of ['anon','service_role'])await assert.rejects(call(claims,role),e=>e.code==='42501');
 await db.query('insert into private.account_deletion_access_restrictions values($1)',[actor]);
 await assert.rejects(call(),e=>e.code==='42501');
 await db.exec('delete from private.account_deletion_access_restrictions');
 await db.query("update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=$1",[sid]);
 await assert.rejects(call(),e=>e.code==='42501');
 console.log('PASS synthetic PGlite self-password boolean SQL runtime and role/session/account denials; not real JWT/provider/production evidence');
}finally{await db.close();}
