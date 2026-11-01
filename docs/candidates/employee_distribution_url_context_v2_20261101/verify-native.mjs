import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createRequire} from 'node:module';
const require=createRequire(process.env.SKO_URL_PG_PACKAGE+'/package.json');
const {Client,types}=require('pg');
types.setTypeParser(1184,v=>v);
assert.equal(process.env.PGHOST,'127.0.0.1');
assert.equal(process.env.PGDATABASE,'sko_distribution_url_fixture');
const db=new Client(); await db.connect();
const dir=new URL('./',import.meta.url);
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const actor=id(1), company=id(2), sid=id(3), nextSid=id(4), other=id(5);
const url='https://testflight.apple.com/join/AbC123xy';
let checks=0;
const pass=label=>{checks++;console.log('PASS '+label);};
async function invoke(command,payload={},operation=null,session=sid,selected=company){
 await db.query('begin');
 try {
  await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:actor,role:'authenticated',session_id:session})]);
  await db.query('set local role authenticated');
  const r=await db.query('select public.employee_distribution_url_context_v2($1,$2,$3,$4,$5) v',[selected,session,command,operation,payload]);
  await db.query('commit'); return r.rows[0].v;
 }catch(e){await db.query('rollback');throw e;}
}
async function rejects(fn,label){await assert.rejects(fn);pass(label);}
try {
 assert.equal(Math.floor(Number((await db.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 assert.equal(Number((await db.query("select count(*) n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'")).rows[0].n),0);
 await db.query(`create schema auth;create schema private;create schema extensions;create extension pgcrypto with schema extensions;
 create role anon;create role authenticated;create role service_role;
 create function auth.jwt() returns jsonb language sql stable as $$select current_setting('request.jwt.claims',true)::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
 create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz);
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create table private.account_deletion_access_restrictions(user_id uuid primary key);
 create function private.account_deletion_barrier_key(p_actor uuid) returns bigint language sql immutable as $$select hashtextextended('deletion:'||p_actor::text,0)$$;
 create table public.companies(id uuid primary key,employee_testflight_url text,updated_at timestamptz,untouched text);
 create table public.company_members(company_id uuid,user_id uuid,role text);
 grant usage on schema auth,private to authenticated;
 insert into auth.users(id) values('${actor}');
 insert into auth.sessions values('${sid}','${actor}',null),('${nextSid}','${actor}',null);
 insert into public.companies values('${company}',null,'2026-11-01T00:00:00Z','retain'),('${other}',null,'2026-11-01T00:00:00Z','other');
 insert into public.company_members values('${company}','${actor}','owner');`);
 await db.query(await fs.readFile(new URL('session-baseline.fixture.sql',dir),'utf8'));
 const legacy=await db.query("select pg_get_functiondef('private.require_reauthentication_session()'::regprocedure) a,pg_get_functiondef('private.account_access_allowed()'::regprocedure) b");
 const install=await fs.readFile(new URL('context.sql.review-only',dir),'utf8');
 await db.query('create role unknown_fixture;alter default privileges in schema private grant execute on functions to unknown_fixture');
 await rejects(()=>db.query(install),'unexpected inherited role ACL aborts entire installation');
 await db.query('rollback');
 assert.equal((await db.query("select to_regclass('private.employee_distribution_url_v2_control') v")).rows[0].v,null);
 await db.query('alter default privileges in schema private revoke execute on functions from unknown_fixture');
 await db.query(install);
 const before=await invoke('read');assert.equal(before.url,null);assert.equal(before.can_save,false);pass('initial OFF retains nullable read');
 const payload={before_url:before.url,before_updated_at:before.updated_at,url};
 await rejects(()=>invoke('save',payload,id(10)),'OFF rejects new save');
 await db.query('update private.employee_distribution_url_v2_control set enabled=true');
 const saved=await invoke('save',payload,id(10));assert.equal(saved.result.status,'saved');pass('CAS writes exact URL');
 const duplicate=await invoke('save',payload,id(10));assert.deepEqual(duplicate.result,saved.result);pass('same operation returns receipt without duplicate write');
 assert.equal(Number((await db.query('select count(*) n from private.employee_distribution_url_v2_operations')).rows[0].n),1);
 await rejects(()=>invoke('save',{...payload,url:url+'Z'},id(10)),'same operation different payload rejected');
 await rejects(()=>invoke('save',payload,id(10),sid,other),'other company rejected');
 const conflict=await invoke('save',payload,id(11));assert.equal(conflict.result.status,'conflict');pass('stale CAS recorded as conflict');
 await db.query('update private.employee_distribution_url_v2_control set enabled=false');
 await rejects(()=>invoke('save',payload,id(10)),'OFF does not revive committed save path');
 const query={original_session_id:sid,fingerprint:saved.fingerprint};
 await db.query('delete from auth.sessions where id=$1',[sid]);
 const recovered=await invoke('result',query,id(10),nextSid);
 assert.equal(recovered.session_id,nextSid);assert.equal(recovered.original_session_id,sid);assert.deepEqual(recovered.result,saved.result);pass('new live SID recovers original receipt after old SID removed and feature OFF');
 await rejects(()=>invoke('result',query,id(10),sid),'expired old SID cannot query');
 await rejects(()=>invoke('result',{...query,fingerprint:'0'.repeat(64)},id(10),nextSid),'wrong fingerprint denied');
 const missing=await invoke('result',query,id(99),nextSid);assert.equal(missing.state,'unobserved');pass('missing receipt remains unobserved');
 await db.query("update public.company_members set role=null");
 await rejects(()=>invoke('read',{},null,nextSid),'NULL role denied');
 await db.query("update public.company_members set role='owner';update private.employee_distribution_url_v2_control set enabled=true");
 await db.query("update public.companies set employee_testflight_url='' where id=$1",[company]);
 const blank=await invoke('read',{},null,nextSid);
 assert.equal(blank.url,'');
 const nullConflict=await invoke('save',{before_url:null,before_updated_at:blank.updated_at,url},id(12),nextSid);
 assert.equal(nullConflict.result.status,'conflict');pass('NULL and empty before values are distinct');
 for (const bad of ['https://testflight.apple.com/join/...','https://user@testflight.apple.com/join/AbC','https://testflight.apple.com/join/AbC?q=1','https://testflight.apple.com:443/join/AbC','']) {
  await rejects(()=>invoke('save',{before_url:'',before_updated_at:blank.updated_at,url:bad},id(20+checks),nextSid),'invalid or clear URL rejected');
 }
 await rejects(()=>db.query('delete from private.employee_distribution_url_v2_operations'),'receipts immutable');
 assert.equal((await db.query('select untouched from public.companies where id=$1',[company])).rows[0].untouched,'retain');pass('other company fields preserved');
 const after=await db.query("select pg_get_functiondef('private.require_reauthentication_session()'::regprocedure) a,pg_get_functiondef('private.account_access_allowed()'::regprocedure) b");
 assert.deepEqual(after.rows,legacy.rows);pass('existing helper bodies unchanged');
 assert.equal(Number((await db.query("select count(*) n from pg_constraint where conrelid='private.employee_distribution_url_v2_operations'::regclass and contype='f'")).rows[0].n),0);pass('no new existing-table FK triggers');
 // Verify an actual row-lock wait on a separate connection before CAS resumes.
 const contender=new Client({application_name:'sko-url-v2-contender'});await contender.connect();
 try {
  const fresh=await invoke('read',{},null,nextSid);
  await db.query('begin');
  await db.query('update public.companies set employee_testflight_url=$1,updated_at=clock_timestamp() where id=$2',[url+'Q',company]);
  const pid=(await contender.query('select pg_backend_pid() pid')).rows[0].pid;
  await contender.query('begin');
  await contender.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:actor,role:'authenticated',session_id:nextSid})]);
  await contender.query('set local role authenticated');
  const pending=contender.query('select public.employee_distribution_url_context_v2($1,$2,$3,$4,$5) v',[company,nextSid,'save',id(90),{before_url:fresh.url,before_updated_at:fresh.updated_at,url}]);
  let waiting=false;
  for(let attempt=0;attempt<100;attempt++) {
   await db.query('select pg_stat_clear_snapshot()');
   const row=(await db.query('select wait_event_type from pg_stat_activity where pid=$1',[pid])).rows[0];
   if(row?.wait_event_type==='Lock'){waiting=true;break;}
   await new Promise(resolve=>setTimeout(resolve,20));
  }
  assert.equal(waiting,true,'second connection must actually wait');
  await db.query('commit');
  const raced=(await pending).rows[0].v;
  assert.equal(raced.result.status,'conflict');
  await contender.query('commit');pass('two real connections wait then reject stale CAS without overwrite');
  assert.equal((await db.query('select employee_testflight_url v from public.companies where id=$1',[company])).rows[0].v,url+'Q');
 } finally {await db.query('rollback');await contender.query('rollback');await contender.end();}
 console.log(`Native PostgreSQL17 isolated synthetic Auth: ${checks} PASS; production 0`);
} finally {await db.end();}
