// Restore-only SQL runtime proof. Owned synthetic database, no GoTrue or production.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
let db;
if(process.argv[3]==='postgres'){
 const url=new URL(process.env.SKO_PRIMARY_STATUS_RESTORE_FIXTURE_URL??'');
 if(url.protocol!=='postgresql:'||!['127.0.0.1','localhost'].includes(url.hostname)||
  url.pathname!=='/sko_primary_status_restore_fixture'||url.username!=='postgres'||
  url.password!=='fixture-only')throw Error('Owned loopback restore database required');
 const pg=(await import(process.argv[2])).default,client=new pg.Client({connectionString:url.href,connectionTimeoutMillis:5000});
 await client.connect();db={query:(...a)=>client.query(...a),exec:s=>client.query(s),close:()=>client.end()};
 assert.equal((await db.query('select current_database() v')).rows[0].v,'sko_primary_status_restore_fixture');
 await db.exec("set statement_timeout='15s';set lock_timeout='5s'");
}else{
 const {PGlite}=await import(process.argv[2]);db=new PGlite();
}
const actor='40000000-0000-0000-0000-000000000001',sid='40000000-0000-0000-0000-000000000002';
try{
 assert.equal((await db.query("select count(*)::int v from pg_tables where schemaname in('public','private','auth')")).rows[0].v,0);
 // Reuse the existing pinned account-helper scaffold verbatim, not a weaker guard.
 const fixture=await fs.readFile('tool/security/primary_password_self_status_pglite.mjs','utf8');
 const scaffold=fixture.match(/await db\.exec\(`([\s\S]*?)`\);/);
 assert.ok(scaffold&&scaffold[1].includes('create role authenticated;'));
 await db.exec(scaffold[1]);
 await db.query("insert into auth.users values($1,'',false,null)",[actor]);
 await db.query('insert into auth.sessions values($1,$2,null)',[sid,actor]);
 const install=await fs.readFile('docs/candidates/primary_password_self_status_20261025.sql.review-only','utf8');
 const restore=await fs.readFile('docs/candidates/primary_password_self_status_restore_20261025.sql.review-only','utf8');
 const privateStart=install.indexOf('create function private.primary_password_configured()');
 const publicStart=install.indexOf('create function public.primary_password_configured()');
 assert.ok(privateStart>0&&publicStart>privateStart);
 const privateUnit=install.slice(privateStart,publicStart).replace('create function private.','create or replace function private.');
 const publicUnit=install.slice(publicStart,install.lastIndexOf('commit;'));
 const state=async()=>(await db.query(`select jsonb_build_object(
  'schemas',(select jsonb_agg(jsonb_build_object('oid',oid,'name',nspname,'owner',nspowner,'acl',nspacl) order by oid) from pg_namespace where nspname in('public','private','auth')),
  'relations',(select jsonb_agg(jsonb_build_object('oid',c.oid,'name',c.relname,'namespace',c.relnamespace,'kind',c.relkind,'owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'forced',c.relforcerowsecurity) order by c.oid) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','private','auth')),
  'columns',(select jsonb_agg(jsonb_build_object('relation',a.attrelid,'position',a.attnum,'name',a.attname,'type',a.atttypid,'notnull',a.attnotnull,'dropped',a.attisdropped) order by a.attrelid,a.attnum) from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','private','auth') and a.attnum>0),
  'routines',(select jsonb_agg(jsonb_build_object('oid',p.oid,'owner',p.proowner,'acl',p.proacl,'config',p.proconfig,'definition',md5(pg_get_functiondef(p.oid))) order by p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','private','auth')),
  'users_fingerprint',(select md5(coalesce(jsonb_agg(to_jsonb(u) order by id)::text,'[]')) from auth.users u),
  'sessions_fingerprint',(select md5(coalesce(jsonb_agg(to_jsonb(s) order by id)::text,'[]')) from auth.sessions s),
  'restrictions_fingerprint',(select md5(coalesce(jsonb_agg(to_jsonb(r) order by user_id)::text,'[]')) from private.account_deletion_access_restrictions r)) v`)).rows[0].v;
 const before=await state();let roundtrips=0,denials=0;
 const exactRestored=async()=>{
  assert.deepEqual(await state(),before);
  assert.equal((await db.query("select count(*)::int v from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','private') and p.proname='primary_password_configured'")).rows[0].v,0);
  roundtrips++;
 };
 const denyRestore=async(code,message)=>{
  const stale=await state();
  try{await assert.rejects(db.exec(restore),error=>error.code===code&&(!message||message.test(error.message)));}
  finally{await db.exec('rollback');}
  assert.deepEqual(await state(),stale);denials++;
 };
 await db.exec(install);
 await db.exec('begin;set local role authenticated');
 await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:actor,session_id:sid,role:'authenticated'})]);
 assert.equal((await db.query('select public.primary_password_configured() v')).rows[0].v,false);
 await db.exec('rollback');
 await db.exec(restore);await exactRestored();

 await db.exec(install);
 await db.exec('alter function private.primary_password_configured() volatile');
 await denyRestore('P0001',/definition_mismatch/);
 await db.exec('alter function private.primary_password_configured() stable');
 await db.exec(restore);await exactRestored();

 await db.exec(install);
 await db.exec('grant execute on function public.primary_password_configured() to anon');
 await denyRestore('P0001',/acl_mismatch/);
 await db.exec('revoke execute on function public.primary_password_configured() from anon');
 await db.exec(restore);await exactRestored();

 await db.exec(install);
 // Deliberate disposable tamper, never an alternative product implementation.
 await db.exec("create or replace function private.primary_password_configured() returns boolean language plpgsql stable security definer set search_path='' as $$begin return false;end$$");
 await denyRestore('P0001',/definition_mismatch/);
 await db.exec(privateUnit);await db.exec(restore);await exactRestored();

 await db.exec(install);
 await db.exec('create view public.fixture_status_dependency as select public.primary_password_configured() configured');
 await denyRestore('2BP01');
 await db.exec('drop view public.fixture_status_dependency');
 await db.exec(restore);await exactRestored();

 await db.exec(install);await db.exec('drop function public.primary_password_configured()');
 await denyRestore('P0001',/definition_mismatch/);
 await db.exec(publicUnit);await db.exec(restore);await exactRestored();
 console.log(JSON.stringify({result:'PASS exact self password status restore',runtime:process.argv[3]==='postgres'?'native-postgres':'pglite',roundtrips,stale_or_dependency_denials:denials,
  protected_original_metadata_data_exact:true,raw_credentials_returned:false,production_connected:false}));
}finally{await db.close();}
