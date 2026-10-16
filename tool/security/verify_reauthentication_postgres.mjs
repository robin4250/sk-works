import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash,randomBytes} from 'node:crypto';
const pg=(await import(process.argv[2]??'pg')).default;
const url=new URL(process.env.SKO_REAUTH_FIXTURE_URL??'');
if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!='/sko_reauthentication_fixture')throw Error('Disposable loopback reauthentication fixture only');
const connections=[];
async function connection(){const c=new pg.Client({connectionString:url.href});await c.connect();connections.push(c);return c;}
const a='10000000-0000-0000-0000-000000000001',b='10000000-0000-0000-0000-000000000002';
const sa='20000000-0000-0000-0000-000000000001',sa2='20000000-0000-0000-0000-000000000002',sb='20000000-0000-0000-0000-000000000003';
const hash=s=>createHash('sha256').update(s).digest('hex');
const target={user_id:a};
async function actor(c,id=a,sid=sa){await c.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id,role:'authenticated',session_id:sid})]);await c.query('set role authenticated');}
const deny=async(p,code='42501')=>assert.rejects(p,e=>e.code===code);
try {
 const admin=await connection();
 assert.match((await admin.query('show server_version')).rows[0].server_version,/^17\./);
 await admin.query(`create role authenticated;create role anon;create role service_role;
 create schema auth;create schema private;create schema extensions;create extension pgcrypto with schema extensions;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
 create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
 create table auth.sessions(id uuid primary key,user_id uuid not null,not_after timestamptz);
 create table auth.users(id uuid primary key,provider text not null);
 create table public.companies(id uuid primary key,name text not null);
 create table public.company_members(company_id uuid not null,user_id uuid not null,role text not null,primary key(company_id,user_id));
 create table private.account_deletion_access_restrictions(user_id uuid primary key);
 create function private.account_deletion_barrier_key(p_actor uuid) returns bigint language sql immutable as $$select hashtextextended('deletion:'||p_actor::text,0)$$;
 create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())$$;
 create table private.master_admins(user_id uuid primary key,enabled boolean not null);
 create function public.is_current_user_master_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.master_admins where user_id=auth.uid() and enabled)$$;
 create table public.user_secondary_credentials(user_id uuid primary key,password_hash text not null,failed_attempts integer not null default 0,locked_until timestamptz,updated_at timestamptz);
 alter table public.user_secondary_credentials enable row level security;revoke all on public.user_secondary_credentials from public,authenticated,anon;
 create table private.master_feature_settings(feature_key text primary key,enabled boolean not null,updated_at timestamptz,updated_by uuid);
 create function public.current_master_feature_flags() returns jsonb language sql security definer set search_path='' as $$select coalesce(jsonb_object_agg(feature_key,enabled),'{}'::jsonb) from private.master_feature_settings$$;
 grant usage on schema public to authenticated,anon,service_role;
 revoke all on schema private,auth,extensions from public,authenticated,anon,service_role;
 grant usage on schema auth to authenticated,service_role;grant execute on all functions in schema auth to authenticated,service_role;
 `);
 await admin.query(await fs.readFile(new URL('../../supabase/tests/fixtures/secondary_reset_before.sql',import.meta.url),'utf8'));
 await admin.query(await fs.readFile(new URL('../../supabase/tests/fixtures/reauthentication_master_before.sql',import.meta.url),'utf8'));
 await admin.query('insert into auth.sessions values($1,$4,null),($2,$4,null),($3,$5,null)',[sa,sa2,sb,a,b]);
 await admin.query('insert into private.master_admins values($1,true)',[a]);
 await admin.query("insert into auth.users values($1,'phone'),($2,'phone'),('10000000-0000-0000-0000-000000000003','apple'),('10000000-0000-0000-0000-000000000004','google')",[a,b]);
 await admin.query("insert into public.companies values('30000000-0000-0000-0000-000000000001','synthetic company')");
 await admin.query(`insert into public.company_members values('30000000-0000-0000-0000-000000000001',$1,'owner'),('30000000-0000-0000-0000-000000000001',$2,'admin'),('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','manager'),('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000004','viewer')`,[a,b]);
 await admin.query('revoke all on function public.set_secondary_password(text),public.set_master_feature_enabled(text,boolean) from public,anon;grant execute on function public.set_secondary_password(text),public.set_master_feature_enabled(text,boolean) to authenticated,service_role');
 const identitySnapshot=async()=> (await admin.query(`select jsonb_build_object(
  'users',(select jsonb_agg(to_jsonb(u) order by id) from auth.users u),
  'companies',(select jsonb_agg(to_jsonb(c) order by id) from public.companies c),
  'members',(select jsonb_agg(to_jsonb(m) order by company_id,user_id) from public.company_members m),
  'masters',(select jsonb_agg(to_jsonb(m) order by user_id) from private.master_admins m)) snapshot`)).rows[0].snapshot;
 const originalIdentity=await identitySnapshot();
 const legacyDefinitions=(await admin.query(`select p.proname,pg_get_functiondef(p.oid) definition,p.proacl::text acl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('set_secondary_password','set_master_feature_enabled') order by p.proname`)).rows;
 await admin.query(await fs.readFile(new URL('../staged/reauthentication_proofs.sql',import.meta.url),'utf8'));
 assert.deepEqual(await identitySnapshot(),originalIdentity,'install cannot change auth IDs/providers/company/member/master records');
 const user=await connection(),other=await connection(),secondSession=await connection(),issuer=await connection();
 await actor(user);await actor(other,b,sb);await actor(secondSession,a,sa2);
 async function issue(operation='secondary_password.replace',t=target,id=a,sid=sa){
  const proof=randomBytes(32).toString('hex');
  await issuer.query("select set_config('request.jwt.claims','{\"role\":\"service_role\"}',false);set role service_role");
  try {await issuer.query('select public.issue_reauthentication_proof($1,$2,$3,$4,$5)',[id,sid,operation,JSON.stringify(t),hash(proof)]);return proof;}
  finally{await issuer.query('reset role');}
 }
 const replace=(c,proof,password='synthetic-new-password')=>c.query('select public.replace_secondary_password_with_proof($1,$2)',[password,proof]);
 const feature=(proof,enabled)=>user.query('select public.set_master_feature_enabled_with_proof($1,$2,$3)',['route_assignment',enabled,proof]);
 // OFF preserves current callers; new issue/consume cannot be used accidentally.
 await user.query("select public.set_secondary_password('synthetic-initial-password')");
 await user.query("select public.set_secondary_password('synthetic-off-compatible')");
 await deny(issue());
 await admin.query('update private.reauthentication_rollout set enabled=true');
 await deny(user.query("select public.set_secondary_password('synthetic-unproven')"));
 await user.query("select set_config('sko.reauthenticated','true',false)");
 await deny(user.query("select public.set_secondary_password('synthetic-guc-forgery')"));
 await other.query("select public.set_secondary_password('synthetic-first-setup')");
 await deny(other.query("select public.set_secondary_password('synthetic-replace-without-proof')"));
 const normalAdminProof=await issue('secondary_password.replace',{user_id:b},b,sb);
 await replace(other,normalAdminProof,'synthetic-normal-admin-recovery');
 await deny(user.query('select public.issue_reauthentication_proof($1,$2,$3,$4,$5)',[a,sa,'secondary_password.replace',JSON.stringify(target),hash('synthetic') ]));
 const proof=await issue();
 await deny(replace(other,proof));await deny(replace(secondSession,proof));
 await deny(feature(proof,true));
 await deny(replace(user,proof,'short'),'22023');
 await replace(user,proof);
 await deny(replace(user,proof));
 assert.equal((await admin.query("select password_hash=extensions.crypt('synthetic-new-password',password_hash) ok from public.user_secondary_credentials where user_id=$1",[a])).rows[0].ok,true);
 // A normal completed business transaction burns the proof exactly once. Failed
 // or rolled-back business changes leave the proof available for retry.
 const rollback=await issue();await user.query('begin');await replace(user,rollback,'synthetic-rolled-back');await user.query('rollback');await replace(user,rollback,'synthetic-after-rollback');
 const expiry=await issue();await admin.query("update private.reauthentication_proofs set issued_at=statement_timestamp()-interval '3 minutes',expires_at=statement_timestamp()-interval '1 minute' where proof_hash=$1",[hash(expiry)]);await deny(replace(user,expiry));
 const revoked=await issue();await admin.query('delete from auth.sessions where id=$1',[sa]);await deny(replace(user,revoked));
 await admin.query('insert into auth.sessions values($1,$2,null)',[sa,a]);
 const restricted=await issue();await admin.query('insert into private.account_deletion_access_restrictions values($1)',[a]);await deny(replace(user,restricted));await deny(issue());await admin.query('delete from private.account_deletion_access_restrictions');
 const expiredSession=await issue();await admin.query("update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=$1",[sa]);await deny(replace(user,expiredSession));await deny(issue());await admin.query('update auth.sessions set not_after=null where id=$1',[sa]);
 const master=await issue('master.feature.set',{feature_key:'route_assignment',enabled:false});
 await deny(feature(master,true));await feature(master,false);await deny(feature(master,false));
 await deny(user.query("select public.set_master_feature_enabled('route_assignment',true)"));
 const removedMaster=await issue('master.feature.set',{feature_key:'route_assignment',enabled:true});await admin.query('update private.master_admins set enabled=false');await deny(feature(removedMaster,true));await admin.query('update private.master_admins set enabled=true');
 await deny(issue('master.feature.set',{feature_key:'route_assignment',enabled:true},b,sb));
 await deny(issue('master.feature.set',{feature_key:'route_assignment',enabled:null}));
 await deny(issue('secondary_password.replace',{user_id:b}));
 const monitor=await issue('master.security_incidents.read',{scope:'platform'});assert.match(monitor,/^[0-9a-f]{64}$/);
 await deny(issue('master.security_incidents.read',{scope:'other'}));
 // Real concurrency: second consumer waits on the first proof update and must
 // fail after the first commits. No timeout/deadlock counts as passing.
 const concurrent=await issue(),race=await connection();await actor(race);
 await user.query('begin');await replace(user,concurrent,'synthetic-race-winner');
 const racePid=(await race.query('select pg_backend_pid() pid')).rows[0].pid;
 const waiting=replace(race,concurrent,'synthetic-race-loser');const rejected=deny(waiting);
 let blocked=false;
 for(let i=0;i<100;i++) {if((await admin.query('select cardinality(pg_blocking_pids($1))>0 blocked',[racePid])).rows[0].blocked){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}
 assert.equal(blocked,true,'second consumer must demonstrably wait');await user.query('commit');await rejected;
 // Rollout ON waits for in-flight legacy transactions holding the OFF gate.
 await admin.query("update private.reauthentication_rollout set enabled=false where scope='secondary_password'");
 await user.query('begin');await user.query("select public.set_secondary_password('synthetic-before-enable')");
 const gate=await connection(),gatePid=(await gate.query('select pg_backend_pid() pid')).rows[0].pid;
 const enable=gate.query("update private.reauthentication_rollout set enabled=true where scope='secondary_password'");
 blocked=false;
 for(let i=0;i<100;i++) {if((await admin.query('select cardinality(pg_blocking_pids($1))>0 blocked',[gatePid])).rows[0].blocked){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}
 assert.equal(blocked,true,'enable must wait for old transaction');await user.query('commit');await enable;
 await deny(user.query("select public.set_secondary_password('synthetic-after-enable')"));
 // Session termination serializes after a sensitive operation already holding
 // its session SHARE lock. After termination, the old JWT cannot obtain proof.
 const logoutProof=await issue();await user.query('begin');await replace(user,logoutProof,'synthetic-before-logout');
 const logout=await connection(),logoutPid=(await logout.query('select pg_backend_pid() pid')).rows[0].pid;
 const terminating=logout.query('delete from auth.sessions where id=$1',[sa]);
 blocked=false;
 for(let i=0;i<100;i++) {if((await admin.query('select cardinality(pg_blocking_pids($1))>0 blocked',[logoutPid])).rows[0].blocked){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}
 assert.equal(blocked,true,'session termination waits for the in-flight sensitive transaction');await user.query('commit');await terminating;
 await deny(issue());await admin.query('insert into auth.sessions values($1,$2,null)',[sa,a]);
 // Read-only catalog assertions for no public proof access and no anonymous API.
 assert.equal((await admin.query("select has_table_privilege('authenticated','private.reauthentication_proofs','SELECT') allowed")).rows[0].allowed,false);
 assert.equal((await admin.query("select has_function_privilege('anon','public.replace_secondary_password_with_proof(text,text)','EXECUTE') allowed")).rows[0].allowed,false);
 assert.deepEqual(await identitySnapshot(),originalIdentity,'operations preserve auth IDs/providers/company/member/master records');
 // Isolated restore rehearsal: restore captured original definitions and remove
 // only this lane's new objects. This is not a production rollback script.
 await admin.query('begin');
 for(const original of legacyDefinitions)await admin.query(original.definition);
 await admin.query(`drop function public.replace_secondary_password_with_proof(text,text),public.set_master_feature_enabled_with_proof(text,boolean,text),public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text),public.reauthentication_capabilities();
 drop function private.consume_reauthentication_proof(text,jsonb,text),private.reauthentication_required(text),private.reauthentication_scope(text);
 drop table private.reauthentication_proofs,private.reauthentication_rollout;`);
 await admin.query('commit');
 const restored=(await admin.query(`select p.proname,pg_get_functiondef(p.oid) definition,p.proacl::text acl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('set_secondary_password','set_master_feature_enabled') order by p.proname`)).rows;
 assert.deepEqual(restored,legacyDefinitions,'original function definitions and ACL must be restored exactly');
 assert.deepEqual(await identitySnapshot(),originalIdentity,'restore preserves IDs/roles/company/provider/membership');
 await user.query("select public.set_secondary_password('synthetic-restored-password')");
 assert.equal((await user.query("select public.verify_secondary_password('synthetic-restored-password') ok")).rows[0].ok,true);
 await user.query("select public.set_master_feature_enabled('route_assignment',true)");
 await assert.rejects(other.query("select public.set_master_feature_enabled('route_assignment',false)"),/master administrator access required/);
 console.log('PASS PostgreSQL 17: actor/session/operation/target/expiry/replay/revocation/restriction, first setup/replacement, rollback, proof/rollout/session-termination races, unchanged phone/Apple/Google IDs and company/member/master roles, exact original-definition/ACL restore and normal original RPC recovery. Synthetic fixture only.');
} finally {await Promise.all(connections.map(c=>c.end()));}
