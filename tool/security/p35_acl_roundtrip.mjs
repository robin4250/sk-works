// P35: disposable synthetic ACL representation round-trip only.
import assert from 'node:assert/strict';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const pgMode=process.argv[2]==='--pg';
let db;
if(pgMode){
 if(process.env.P35_SYNTHETIC!=='1')throw Error('Explicit disposable fixture flag required');
 const u=new URL(process.env.P35_FIXTURE_URL);
 if(!['postgres:','postgresql:'].includes(u.protocol)||!['127.0.0.1','localhost','[::1]'].includes(u.hostname)||u.port!=='5432'||u.pathname!=='/p35_fixture'||u.search||u.hash||u.username!=='postgres'||u.password!=='fixture-only')throw Error('Fixed disposable loopback database only');
 const {default:pg}=await import('./fixture_dependencies/node_modules/pg/lib/index.js');
 db=new pg.Client({connectionString:u.href});await db.connect();
 const n=Number((await db.query("select current_setting('server_version_num') n")).rows[0].n);
 if(n<170000||n>=180000)throw Error('PostgreSQL17 required');
}else{
 const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new PGlite();
}
const exec=sql=>pgMode?db.query(sql):db.exec(sql);
const query=(sql,args=[])=>db.query(sql,args);
const names=['p35_owner_a','p35_owner_b','p35_plain','p35_delegate','p35_leaf'];
const signatures=['p35.f01()','p35.f02()'];
const qi=s=>'"'+s.replaceAll('"','""')+'"';
if(Number((await query("select count(*) n from pg_tables where schemaname not in ('pg_catalog','information_schema')")).rows[0].n)!==0)throw Error('Empty synthetic database required');
if(Number((await query("select count(*) n from pg_roles where rolname like 'p35_%'")).rows[0].n)!==0)throw Error('Synthetic roles must not pre-exist');
if(Number((await query("select count(*) n from pg_namespace where nspname='p35'")).rows[0].n)!==0)throw Error('Synthetic schema must not pre-exist');
for(const name of names)await exec('create role '+qi(name));
await exec('create schema p35;grant usage on schema p35 to '+names.map(qi).join(',')+';grant create on schema p35 to p35_owner_a,p35_owner_b');
async function asRole(name,sql){
 await exec('set role '+qi(name));
 try{return await exec(sql);}finally{await exec('reset role');}
}
await asRole('p35_owner_a',"create function p35.f01() returns integer language sql stable set search_path='' as $$SELECT 41$$");
await asRole('p35_owner_b',"create function p35.f02() returns integer language sql stable security definer set search_path='' as $$SELECT 42$$;revoke all on function p35.f02() from public;grant execute on function p35.f02() to p35_plain;grant execute on function p35.f02() to p35_delegate with grant option");
await asRole('p35_delegate','grant execute on function p35.f02() to p35_leaf');
async function snapshot(){
 const out=[];
 for(const sig of signatures){
  const m=(await query("select p.oid::text oid,pg_get_userbyid(p.proowner) owner,p.proacl::text acl,p.proconfig::text config,p.prosecdef definer,p.provolatile volatility,p.prosrc body,pg_get_functiondef(p.oid) definition from pg_proc p where p.oid=$1::regprocedure",[sig])).rows[0];
  const grants=(await query("select a.ord::int ord,pg_get_userbyid(e.grantor) grantor,case when e.grantee=0 then 'PUBLIC' else pg_get_userbyid(e.grantee) end grantee,e.privilege_type privilege,e.is_grantable grantable from pg_proc p cross join lateral unnest(coalesce(p.proacl,acldefault('f',p.proowner))) with ordinality a(acl,ord) cross join lateral aclexplode(array[a.acl]) e where p.oid=$1::regprocedure order by a.ord",[sig])).rows;
  out.push({sig,...m,grants});
 }return out;
}
const semantic=s=>s.map(({oid,...r})=>r);
const metadata=s=>s.map(({body,definition,...r})=>r);
const before=await snapshot();let checks=0;
function ok(value,label){assert.ok(value,label);checks++;}
ok(before[0].acl===null,'SQL NULL ACL stays distinct from expanded default');
ok(before[0].grants.some(g=>g.grantee==='PUBLIC'&&!g.grantable),'NULL expands to PUBLIC execute');
ok(before[0].owner!==before[1].owner,'two original owners differ');
ok(before[1].grants.some(g=>g.grantee==='p35_delegate'&&g.grantable&&g.grantor==='p35_owner_b'),'explicit grant option retained');
ok(before[1].grants.some(g=>g.grantee==='p35_leaf'&&!g.grantable&&g.grantor==='p35_delegate'),'delegated grantor retained');
for(const row of before){
 const literal=row.sig==='p35.f01()'?'SELECT 41':'SELECT 42';
 assert.equal(row.definition.split(literal).length,2);
 await exec(row.definition.replace(literal,literal.replace('SELECT ','SELECT 10')));
}
assert.deepEqual(metadata(await snapshot()),metadata(before));checks++;
ok((await snapshot())[0].body!==before[0].body,'replace changes source while preserving existing owner/OID/ACL');
async function restoreSelected(){
 await exec('begin');
 try{
  for(const row of before){
   await exec('drop function '+row.sig);
   await asRole(row.owner,row.definition);
   if(row.acl!==null){
    await asRole(row.owner,'revoke all on function '+row.sig+' from public');
    // Captured ordinal order includes the owner's delegating grant before its recipient grant.
    for(const grant of row.grants){
     if(grant.privilege!=='EXECUTE'||!names.includes(grant.grantor)||!(grant.grantee==='PUBLIC'||names.includes(grant.grantee)))throw Error('Unexpected synthetic ACL element');
     const to=grant.grantee==='PUBLIC'?'PUBLIC':qi(grant.grantee);
     await asRole(grant.grantor,'grant execute on function '+row.sig+' to '+to+(grant.grantable?' with grant option':''));
    }
   }
  }
  assert.deepEqual(semantic(await snapshot()),semantic(before),'exact source/owner/raw NULL-or-explicit ACL/config and grantor/option round-trip');
  await exec('commit');
 }catch(error){await exec('rollback');throw error;}
}
await restoreSelected();checks++;
const restored=await snapshot();
ok(restored[0].oid!==before[0].oid&&restored[1].oid!==before[1].oid,'DROP/restore changes OID: identity preservation requires CREATE OR REPLACE');
for(const name of ['p35_plain','p35_delegate','p35_leaf']){
 await exec('set role '+qi(name));
 try{assert.equal((await query('select p35.f02() n')).rows[0].n,42);checks++;}
 finally{await exec('reset role');}
}
await asRole('p35_owner_a','revoke all on function p35.f01() from public;grant execute on function p35.f01() to public');
const explicitDefault=await snapshot();
ok(explicitDefault[0].acl!==null,'explicit default-equivalent ACL is not NULL');
const effective=gs=>gs.map(({ord,...g})=>g).sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)));
assert.deepEqual(effective(explicitDefault[0].grants),effective(before[0].grants));checks++;
await restoreSelected();checks++;
await asRole('p35_owner_b','revoke grant option for execute on function p35.f02() from p35_delegate cascade');
const revoked=await snapshot();
ok(!revoked[1].grants.some(g=>g.grantee==='p35_leaf'),'revocation cascades to delegated leaf');
ok(revoked[1].grants.some(g=>g.grantee==='p35_delegate'&&!g.grantable),'execute remains when grant option revoked');
await restoreSelected();checks++;
// CREATE OR REPLACE does not repair a wrong owner or default ACL.
await exec('drop function p35.f01()');await exec(before[0].definition);await exec(before[0].definition);
ok((await snapshot())[0].owner!==before[0].owner,'wrong-owner replace preserves wrong owner');
await restoreSelected();checks++;
// Changed default privileges must be detected rather than normalized away.
await exec('alter default privileges for role p35_owner_a in schema p35 grant execute on functions to p35_plain');
const priorDefaultTest=await snapshot();
await assert.rejects(restoreSelected(),/round-trip/);checks++;
assert.deepEqual(await snapshot(),priorDefaultTest,'failed ACL validation rolls back selected drop/recreate including old OIDs');checks++;
await exec('alter default privileges for role p35_owner_a in schema p35 revoke execute on functions from p35_plain');
await restoreSelected();checks++;
assert.deepEqual(semantic(await snapshot()),semantic(before));checks++;
console.log(JSON.stringify({result:'PASS',checks,engine:pgMode?'PostgreSQL17':'PGlite',scope:'two synthetic function ACL representations',nullAclAndPublicDefault:true,grantOptionAndDelegatedGrantor:true,ownerAndReplaceConditions:true,defaultPrivilegeDriftRollback:true,productionConnections:0,productionWrites:0,actualArchiveRestoration:false}));
if(pgMode)await db.end();else await db.close();
