import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash,randomBytes} from 'node:crypto';
const pg=(await import(process.argv[2]??'pg')).default;
const url=new URL(process.env.SKO_REAUTH_FIXTURE_URL??'');
if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!='/sko_master_device_lock_fixture')throw Error('Disposable loopback reauthentication fixture only');
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
 await admin.query(`create table private.master_devices(id uuid primary key,master_user_id uuid not null,device_name text not null,is_locked boolean not null default false,revoked_at timestamptz);
 create table private.master_admin_audit_log(id bigserial primary key,actor_user_id uuid,action text,target_user_id uuid,details jsonb);`);
 const d='40000000-0000-0000-0000-000000000001',d2='40000000-0000-0000-0000-000000000002',foreign='40000000-0000-0000-0000-000000000003',revoked='40000000-0000-0000-0000-000000000004';
 await admin.query('insert into private.master_devices values($1,$5,$6,false,null),($2,$5,$7,false,null),($3,$8,$9,false,null),($4,$5,$10,true,now())',[d,d2,foreign,revoked,a,'synthetic device one','synthetic device two',b,'synthetic other device','synthetic revoked']);
 await admin.query(await fs.readFile(new URL('../../supabase/tests/fixtures/master_device_lock_before.sql',import.meta.url),'utf8'));
 await admin.query(`create function public.revoke_master_device(p_device_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin
 if not public.is_current_user_master_admin() then raise sqlstate '42501'; end if;
 update private.master_devices set is_locked=true,revoked_at=now() where id=p_device_id and master_user_id=auth.uid();
 if not found then raise sqlstate '42501'; end if; end $$;
 revoke all on function public.revoke_master_device(uuid) from public,anon;grant execute on function public.revoke_master_device(uuid) to authenticated;`);
 await admin.query('revoke all on function public.set_master_device_locked(uuid,boolean) from public,anon;grant execute on function public.set_master_device_locked(uuid,boolean) to authenticated,service_role');
 const functions=async()=> (await admin.query(`select n.nspname,p.proname,pg_get_functiondef(p.oid) definition,p.proacl::text acl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='private' and p.proname in ('reauthentication_scope','reauthentication_required')) or (n.nspname='public' and p.proname in ('issue_reauthentication_proof','set_master_device_locked')) order by n.nspname,p.proname`)).rows;
 const originalFunctions=await functions(),beforeIdentity=await identitySnapshot();
 const devices=async()=> (await admin.query('select * from private.master_devices order by id')).rows;
 const originalDevices=await devices();
 await admin.query(await fs.readFile(new URL('../staged/master_device_lock_reauthentication.sql',import.meta.url),'utf8'));
 assert.deepEqual(await identitySnapshot(),beforeIdentity);assert.deepEqual(await devices(),originalDevices);
 const user=await connection(),other=await connection(),differentSession=await connection(),issuer=await connection();
 await actor(user);await actor(other,b,sb);await actor(differentSession,a,sa2);
 async function issue(deviceId=d,locked=true,id=a,sid=sa) {
  const proof=randomBytes(32).toString('hex');
  await issuer.query("select set_config('request.jwt.claims','{\"role\":\"service_role\"}',false);set role service_role");
  try {await issuer.query('select public.issue_reauthentication_proof($1,$2,$3,$4,$5)',[id,sid,'master.device.lock',JSON.stringify({device_id:deviceId,locked}),hash(proof)]);return proof;}
  finally {await issuer.query('reset role');}
 }
 const lock=(c,proof,locked=true,deviceId=d)=>c.query('select public.set_master_device_locked_with_proof($1,$2,$3)',[deviceId,locked,proof]);
 const auditCount=async()=> (await admin.query('select count(*)::int n from private.master_admin_audit_log')).rows[0].n;
 // OFF preserves exactly the existing lock and unlock operations/audit actions.
 assert.equal((await user.query('select public.master_device_lock_capability() c')).rows[0].c.enabled,false);
 await user.query('select public.set_master_device_locked($1,true)',[d]);await user.query('select public.set_master_device_locked($1,false)',[d]);
 assert.equal(await auditCount(),2);await deny(issue());
 await admin.query('update private.master_device_lock_rollout set enabled=true');
 await deny(user.query('select public.set_master_device_locked($1,true)',[d]));
 await deny(other.query('select public.master_device_lock_capability()'));await deny(issue(d,true,b,sb));
 await deny(issue(foreign));await deny(issue(revoked));
 const proof=await issue();await deny(lock(other,proof));await deny(lock(differentSession,proof));
 await deny(lock(user,proof,false));await deny(lock(user,proof,true,d2));
 await lock(user,proof);assert.equal(await auditCount(),3);await deny(lock(user,proof));assert.equal(await auditCount(),3);
 await lock(user,await issue(d,false),false);assert.equal(await auditCount(),4);
 const expiry=await issue();await admin.query("update private.reauthentication_proofs set issued_at=statement_timestamp()-interval '3 minutes',expires_at=statement_timestamp()-interval '1 minute' where proof_hash=$1",[hash(expiry)]);await deny(lock(user,expiry));
 // Failed business preconditions roll back consumption; IDs/roles are never
 // changed to force an authorization success. This toggles fixture revocation.
 const becameRevoked=await issue();await admin.query('update private.master_devices set revoked_at=now() where id=$1',[d]);await deny(lock(user,becameRevoked));
 await admin.query('update private.master_devices set revoked_at=null where id=$1',[d]);await lock(user,becameRevoked);
 const rollback=await issue(d,false);await user.query('begin');await lock(user,rollback,false);await user.query('rollback');await lock(user,rollback,false);
 const banned=await issue();await admin.query('insert into private.account_deletion_access_restrictions values($1)',[a]);await deny(lock(user,banned));await deny(issue());await admin.query('delete from private.account_deletion_access_restrictions');
 const revokedSession=await issue();await admin.query('delete from auth.sessions where id=$1',[sa]);await deny(lock(user,revokedSession));await admin.query('insert into auth.sessions values($1,$2,null)',[sa,a]);
 const noLongerMaster=await issue();await admin.query('update private.master_admins set enabled=false where user_id=$1',[a]);await deny(lock(user,noLongerMaster));await admin.query('update private.master_admins set enabled=true where user_id=$1',[a]);
 // Proof consumer races: loser must wait for winner and then be denied, not
 // accidentally pass on a timeout/deadlock.
 const concurrent=await issue(),race=await connection();await actor(race);
 await user.query('begin');await lock(user,concurrent);
 const pid=(await race.query('select pg_backend_pid() pid')).rows[0].pid;
 const waiting=deny(lock(race,concurrent));let blocked=false;
 for(let i=0;i<100;i++){if((await admin.query('select cardinality(pg_blocking_pids($1))>0 b',[pid])).rows[0].b){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}
 assert.equal(blocked,true);await user.query('commit');await waiting;
 // Enabling the new scope waits for an old OFF transaction; no old write may
 // sneak in across the enforcement transition.
 await admin.query('update private.master_device_lock_rollout set enabled=false');
 await user.query('begin');await user.query('select public.set_master_device_locked($1,false)',[d]);
 const gate=await connection(),gatePid=(await gate.query('select pg_backend_pid() pid')).rows[0].pid;
 const enabling=gate.query('update private.master_device_lock_rollout set enabled=true');blocked=false;
 for(let i=0;i<100;i++){if((await admin.query('select cardinality(pg_blocking_pids($1))>0 b',[gatePid])).rows[0].b){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}
 assert.equal(blocked,true);await user.query('commit');await enabling;
 await deny(user.query('select public.set_master_device_locked($1,true)',[d]));
 assert.deepEqual(await identitySnapshot(),beforeIdentity,'IDs/providers/company/member/master roles unchanged');
 assert.equal((await admin.query("select has_function_privilege('anon','public.set_master_device_locked_with_proof(uuid,boolean,text)','EXECUTE') allowed")).rows[0].allowed,false);
 // Install candidate without changing an existing device or identity.
 const beforeGuard=await devices();
 await admin.query(await fs.readFile(new URL('../staged/master_last_usable_device_guard.sql.review-only',import.meta.url),'utf8'));
 assert.deepEqual(await devices(),beforeGuard);assert.deepEqual(await identitySnapshot(),beforeIdentity);
 await admin.query('update private.master_device_lock_rollout set enabled=false');
 await admin.query('update private.master_devices set is_locked=false where id=any($1::uuid[])',[[d,d2]]);
 await user.query('select public.set_master_device_locked($1,true)',[d]);
 await deny(user.query('select public.set_master_device_locked($1,true)',[d2]));
 await deny(user.query('select public.revoke_master_device($1)',[d2]));
 // Existing legitimate unlock still works. Existing proof checks are retained.
 await user.query('select public.set_master_device_locked($1,false)',[d]);
 await admin.query('update private.master_device_lock_rollout set enabled=true');
 const proofD=await issue(d,true),proofD2=await issue(d2,true);
 await lock(user,proofD,true,d);await deny(lock(user,proofD2,true,d2));
 await deny(lock(other,proofD2,true,d2));
 await lock(user,await issue(d,false),false,d);
 // Simultaneous distinct target lock/revoke must serialize on the owner row.
 for(const pair of [['lock','lock'],['lock','revoke'],['revoke','revoke']]) {
  await admin.query('update private.master_device_lock_rollout set enabled=false');
  await admin.query('update private.master_devices set is_locked=false,revoked_at=null where id=any($1::uuid[])',[[d,d2]]);
  const run=(c,op,id)=>c.query(op==='lock'?'select public.set_master_device_locked($1,true)':'select public.revoke_master_device($1)',[id]);
  const competitor=await connection();await actor(competitor);
  await user.query('begin');await run(user,pair[0],d);
  const competitorPid=(await competitor.query('select pg_backend_pid() pid')).rows[0].pid;
  const pending=deny(run(competitor,pair[1],d2));let blocks=false;
  for(let i=0;i<100;i++){if((await admin.query('select cardinality(pg_blocking_pids($1))>0 b',[competitorPid])).rows[0].b){blocks=true;break;}await new Promise(r=>setTimeout(r,10));}
  assert.equal(blocks,true);await user.query('commit');await pending;
  assert.equal((await admin.query('select count(*)::int n from private.master_devices where master_user_id=$1 and revoked_at is null and not is_locked',[a])).rows[0].n,1);
 }
 await deny(other.query('select public.set_master_device_locked($1,false)',[d2]));
 const anonymous=await connection();await anonymous.query('set role anon');await deny(anonymous.query('select public.revoke_master_device($1)',[d2]));
 await deny(user.query('select private.master_lock_before_last_device_guard($1,false)',[d2]));
 await deny(user.query('select private.master_revoke_before_last_device_guard($1)',[d2]));
 assert.deepEqual(await identitySnapshot(),beforeIdentity);
 // Isolated restore: remove wrappers, return original function OIDs to public,
 // restore original execution ACL. No production rollback is performed here.
 await admin.query(`begin;
 drop function public.set_master_device_locked(uuid,boolean),public.revoke_master_device(uuid),public.set_master_device_locked_with_proof(uuid,boolean,text);
 alter function private.master_lock_before_last_device_guard(uuid,boolean) rename to set_master_device_locked;
 alter function private.set_master_device_locked(uuid,boolean) set schema public;
 alter function private.master_revoke_before_last_device_guard(uuid) rename to revoke_master_device;
 alter function private.revoke_master_device(uuid) set schema public;
 alter function private.master_proof_lock_before_last_device_guard(uuid,boolean,text) rename to set_master_device_locked_with_proof;
 alter function private.set_master_device_locked_with_proof(uuid,boolean,text) set schema public;
 grant execute on function public.set_master_device_locked(uuid,boolean),public.revoke_master_device(uuid),public.set_master_device_locked_with_proof(uuid,boolean,text) to authenticated;
 drop function private.guard_master_device_loss(uuid,boolean);commit;`);
 assert.deepEqual(await identitySnapshot(),beforeIdentity);
 console.log('PASS PostgreSQL 17: last usable lock/revoke/proof rejection; existing unlock/proof semantics; cross-target lock/lock, lock/revoke and revoke/revoke concurrent connections; role/private bypass denial; unchanged identity/provider/company/roles; isolated definition restoration. Synthetic fixture only.');
} finally {await Promise.all(connections.map(c=>c.end()));}
