// Disposable real-GoTrue fixture extension. Account guard helper below reuses the pinned production routine body; surrounding rows
// are synthetic. No production user or credential is read by this fixture.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {randomUUID} from 'node:crypto';

export async function preparePrimaryPasswordStatus(db,c){
 const {request,json,claims,original,seed}=c;
 await db.query(`create table private.account_deletion_access_restrictions(user_id uuid primary key);
  alter table private.account_deletion_access_restrictions enable row level security;
  revoke all on private.account_deletion_access_restrictions from public,anon,authenticated,service_role;
  create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $function$
 select auth.uid() is not null and not exists(
  select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())
$function$;
  revoke all on function private.account_access_allowed() from public;
  grant execute on function private.account_access_allowed() to anon,authenticated,service_role;
  grant usage on schema private to authenticated;`);
 const metadata=async()=>(await db.query(`select jsonb_build_object(
  'schemas',(select jsonb_agg(jsonb_build_object('n',nspname,'acl',nspacl,'owner',nspowner) order by nspname) from pg_namespace where nspname in('public','private','auth')),
  'tables',(select jsonb_agg(jsonb_build_object('oid',c.oid,'acl',c.relacl,'owner',c.relowner) order by c.oid) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','private','auth') and c.relkind in('r','p')),
  'routines',(select jsonb_agg(jsonb_build_object('oid',p.oid,'acl',p.proacl,'owner',p.proowner,'source',md5(pg_get_functiondef(p.oid))) order by p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','private') and p.proname<>'primary_password_configured')) v`)).rows[0].v;
 const before=await metadata();
 await db.query(await fs.readFile('docs/candidates/primary_password_self_status_20261025.sql.review-only','utf8'));
 assert.deepEqual(await metadata(),before);
 const routines=(await db.query(`select n.nspname,p.pronargs,p.prorettype::regtype::text result,p.prosecdef,p.proconfig,
  has_function_privilege('anon',p.oid,'EXECUTE') anon,
  has_function_privilege('service_role',p.oid,'EXECUTE') service,
  has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated,
  pg_get_userbyid(p.proowner) owner,p.provolatile
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname='primary_password_configured' order by n.nspname`)).rows;
 assert.equal(routines.length,2);
 for(const row of routines){assert.equal(row.pronargs,0);assert.equal(row.result,'boolean');assert.equal(row.anon,false);assert.equal(row.service,false);assert.equal(row.authenticated,true);assert.equal(row.owner,'postgres');assert.equal(row.provolatile,'s');assert.deepEqual(row.proconfig,['search_path=""']);}
 assert.equal(routines.find(x=>x.nspname==='public').prosecdef,false);
 assert.equal(routines.find(x=>x.nspname==='private').prosecdef,true);
 await db.query("notify pgrst,'reload schema'");
 const rpc=token=>request('/rest/v1/rpc/primary_password_configured',{method:'POST',token,body:{}});
 let ready;
 for(let i=0;i<40;i++){
  ready=await rpc(original.access_token);
  if(ready.status===200)break;
  assert.ok([404,503].includes(ready.status));await new Promise(r=>setTimeout(r,250));
 }
 assert.equal(ready.status,200);assert.equal(await ready.json(),false);
 const originalClaims=claims(original.access_token);
 const snapshot=async()=>(await db.query(`select jsonb_build_object(
  'session_exists',exists(select 1 from auth.sessions where id=$1 and user_id=$2),
  'users',(select count(*) from auth.users),
  'identities',(select md5(coalesce(jsonb_agg(to_jsonb(i) order by id)::text,'[]')) from auth.identities i),
  'members',(select md5(coalesce(jsonb_agg(to_jsonb(m) order by user_id,company_id)::text,'[]')) from public.company_members m),
  'secondary',(select md5(coalesce(jsonb_agg(to_jsonb(p) order by user_id)::text,'[]')) from private.fixture_secondary_password p)) v`,[originalClaims.session_id,seed.id])).rows[0].v;
 const preserved=await snapshot();assert.equal(preserved.session_exists,true);
 const denySql=async(jwt,role='authenticated',sql='select public.primary_password_configured()',setup)=>{
  await db.query('begin');
  try{
   if(setup)await setup();
   assert.ok(['authenticated','anon','service_role'].includes(role));
   await db.query(`set local role ${role}`);
   await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify(jwt)]);
   await assert.rejects(db.query(sql),error=>error.code==='42501');
  }finally{await db.query('rollback');}
 };
 await denySql(originalClaims,'anon');await denySql({...originalClaims,role:'service_role'},'service_role');
 await denySql({...originalClaims,session_id:undefined});
 await denySql({...originalClaims,session_id:'invalid-session'});
 await denySql({...originalClaims,session_id:randomUUID()});
 await denySql({...originalClaims,sub:randomUUID()});
 await denySql({...originalClaims,is_anonymous:true});
 await denySql(originalClaims,'authenticated','select encrypted_password from auth.users');
 await denySql(originalClaims,'authenticated','select public.primary_password_configured()',()=>db.query("update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=$1",[originalClaims.session_id]));
 await denySql(originalClaims,'authenticated','select public.primary_password_configured()',()=>db.query("update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id=$1",[seed.id]));
 await db.query('insert into private.account_deletion_access_restrictions values($1)',[seed.id]);
 await denySql(originalClaims);await db.query('delete from private.account_deletion_access_restrictions');
 const deniedAnon=await request('/rest/v1/rpc/primary_password_configured',{method:'POST',body:{}});
 assert.ok([401,403,404].includes(deniedAnon.status));
 const deniedService=await request('/rest/v1/rpc/primary_password_configured',{method:'POST',admin:true,body:{}});
 assert.ok([401,403,404].includes(deniedService.status));
 assert.deepEqual(await snapshot(),preserved);assert.deepEqual(await metadata(),before);
 return {
  async afterPassword(){
   assert.equal(await json(await rpc(original.access_token)),true);
   assert.deepEqual(await snapshot(),preserved);assert.deepEqual(await metadata(),before);
  },
  async afterLogin(signed){
   assert.equal(await json(await rpc(original.access_token)),true);
   assert.equal(await json(await rpc(signed.access_token)),true);
   assert.deepEqual(await snapshot(),preserved);assert.deepEqual(await metadata(),before);
   console.log('PASS primary password self boolean: real GoTrue original JWT false -> same-user password update true; same-UID login; anon/service/invalid-session/other-actor/blocked/anonymous refusals; original session/identity/company/secondary and existing ACL/metadata retained. Pinned existing account helper source with synthetic restriction rows; no production or actual provider claim.');
  },
 };
}
