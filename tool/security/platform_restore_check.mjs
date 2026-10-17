import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
// Disposable-only fixture data: no exported production identity, credential or log.
export async function createProtectedFixture(db){
 await db.exec(`create table public.platform_restore_fixture_companies(id uuid primary key,name text not null);
 create table public.platform_restore_fixture_members(company_id uuid,user_id uuid,role text not null,primary key(company_id,user_id));
 create table private.platform_restore_fixture_master(user_id uuid primary key,enabled boolean not null);
 create table private.platform_restore_fixture_auth_settings(name text primary key,enabled boolean not null);
 create table private.platform_restore_fixture_synthetic(id integer primary key,record jsonb not null);
 insert into public.platform_restore_fixture_companies values('11111111-1111-4111-8111-111111111111','isolated-company');
 insert into public.platform_restore_fixture_members values('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','admin');
 insert into private.platform_restore_fixture_master values('22222222-2222-4222-8222-222222222222',true);
 insert into private.platform_restore_fixture_auth_settings values('apple_provider',true),('google_provider',true),('oauth_without_password',true);
 insert into private.platform_restore_fixture_synthetic values(1,'{"source_provenance":"synthetic_fixture","status":"detected"}');
 alter table public.platform_restore_fixture_members enable row level security;
 grant select on public.platform_restore_fixture_members to authenticated;
 create policy fixture_member_self on public.platform_restore_fixture_members to authenticated using(user_id=auth.uid());`);
}
export async function snapshotProtected(db){
 const tables=await db.query(`select n.nspname,c.relname,pg_get_userbyid(c.relowner) owner,c.relacl::text acl,c.relrowsecurity,c.relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and n.nspname in ('public','private','auth') order by 1,2`);
 const funcs=await db.query(`select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) arguments,p.proacl::text acl,pg_get_userbyid(p.proowner) owner,pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','auth') and p.prokind='f' order by 1,2,3`);
 const policies=await db.query(`select schemaname,tablename,policyname,roles::text,cmd,qual,with_check from pg_policies where schemaname in ('public','private','auth') order by 1,2,3`);
 const roles=await db.query(`select rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls from pg_roles order by rolname`);
 const indexes=await db.query(`select schemaname,tablename,indexname,indexdef from pg_indexes where schemaname in ('public','private','auth') order by 1,2,3`);
 const constraints=await db.query(`select n.nspname,c.relname,k.conname,pg_get_constraintdef(k.oid) definition from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth') order by 1,2,3`);
 const memberships=await db.query(`select pg_get_userbyid(roleid) role_name,pg_get_userbyid(member) member_name,admin_option,inherit_option,set_option from pg_auth_members order by 1,2`);
 const data={};
 for(const table of ['public.platform_restore_fixture_companies','public.platform_restore_fixture_members','private.platform_restore_fixture_master','private.platform_restore_fixture_auth_settings','private.platform_restore_fixture_synthetic'])data[table]=(await db.query(`select to_jsonb(x) row from ${table} x order by to_jsonb(x)::text`)).rows;
 return {tables:tables.rows,funcs:funcs.rows,policies:policies.rows,roles:roles.rows,indexes:indexes.rows,constraints:constraints.rows,memberships:memberships.rows,data};
}
export async function verifyProtectedRestore(db,before){
 await db.exec('reset role');
 const rollback=await readFile(new URL('./platform_monitor_rollback.sql.review-only',import.meta.url),'utf8');
 const rejectRollback=async(re)=>{await assert.rejects(db.exec(rollback),re);await db.exec('rollback');};
 await rejectRollback(/verified isolated restore/);
 await db.exec("select set_config('sko.platform_monitor_snapshot_restore_verified','isolated-restore-verified-v1',false)");
 // Still refuses populated evidence; no rows/settings disappear on refusal.
 const evidence=(await db.query('select count(*)::int n from private.platform_monitor_events')).rows[0].n;assert.ok(evidence>0);
 await db.exec('update private.platform_monitor_control set enabled=false');
 await rejectRollback(/evidence must be preserved/);
 assert.equal((await db.query('select count(*)::int n from private.platform_monitor_events')).rows[0].n,evidence);
 // This deletion is restricted to these newly created disposable fixture tables,
 // never part of the operator rollback and never executed against production.
 await db.exec('delete from private.platform_monitor_events;delete from private.platform_monitor_windows');
 await db.exec('update private.platform_monitor_control set enabled=true');await rejectRollback(/must be disabled/);
 await db.exec('update private.platform_monitor_control set enabled=false');
 await db.exec(rollback);
 const after=await snapshotProtected(db);assert.deepEqual(after,before,'original role/member/master/synthetic/OAuth settings/data/RLS/ACL/functions must remain exact');
 console.log('PASS isolated foundation rollback: missing restore ack / enabled control / nonempty evidence refuse atomically; removing only empty new objects preserves protected fixture values, roles, ACL, RLS and functions exactly.');
 console.log('LIMIT: fake fixture restore only, not a production snapshot or live Apple/Google verification.');
}
