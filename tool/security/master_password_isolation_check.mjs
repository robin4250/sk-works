import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash, createHmac, randomUUID} from 'node:crypto';

// Disposable PostgreSQL/pgcrypto and signed PostgREST JWT exercise. Auth helpers
// below are explicit fixture prerequisites, not real hosted GoTrue/OAuth proof.
const pg=(await import(process.argv[2]??'pg')).default;
const url=new URL(process.env.SKO_MASTER_PASSWORD_FIXTURE_URL??'');
const http=new URL(process.env.SKO_MASTER_PASSWORD_POSTGREST_URL??'');
if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname) ||
   url.pathname!='/sko_master_password_fixture' || url.protocol!=='postgres:' ||
   http.hostname!=='127.0.0.1' || http.protocol!=='http:') {
  throw Error('Disposable loopback Master password fixture only');
}
const ids=Array.from({length:8},(_,i)=>'10000000-0000-4000-8000-'+String(i+1).padStart(12,'0'));
const sessions=ids.map((_,i)=>'20000000-0000-4000-8000-'+String(i+1).padStart(12,'0'));
const device='30000000-0000-4000-8000-000000000001';
const otherDevice='30000000-0000-4000-8000-000000000002';
const key='fixture-master-device-key-'.padEnd(64,'a');
const otherKey='fixture-other-device-key-'.padEnd(64,'b');
const secondary='fixture-common-secondary-password';
const masterSecret='fixture-independent-master-password';
const nextSecret='fixture-independent-master-next-password';
const conns=[];
async function connection(id=ids[0],sid=sessions[0],role='authenticated') {
  const c=new pg.Client({connectionString:url.href}); await c.connect(); conns.push(c);
  await c.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id,session_id:sid,role,is_anonymous:false})]);
  if(role!=='postgres')await c.query('set role '+role);
  return c;
}
const protocol='sko-master-password-v1';
async function rpc(c,name,values=[],types=[]) {
  const args=values.map((_,i)=>'$'+(i+1)+(types[i]?'::'+types[i]:'')).join(',');
  const r=(await c.query('select public.'+name+'('+args+') result',values)).rows[0].result;
  assert.equal(r.protocol,protocol); return r;
}
const status=(c,k=key)=>rpc(c,'current_master_password_status',[k]);
const begin=(c,op='setup',version=0,request=randomUUID(),k=key)=>
  rpc(c,'begin_master_password_operation',[k,op,version,request],['text','text','bigint','uuid']);
const finish=(c,ch,old=secondary,pw=masterSecret,k=key,nonce=ch.nonce,request=ch.request_id)=>
  rpc(c,'complete_master_password_operation',[k,ch.challenge_id,nonce,old,pw,request],['text','uuid','text','text','text','uuid']);
const read=(c,request,k=key)=>rpc(c,'read_master_password_request',[k,request],['text','uuid']);
const denied=r=>assert.notEqual(r.status,'applied');
const jwtSecret='master-password-fixture-only-key-at-least-32-characters';
function jwt(id=ids[0],sid=sessions[0],override={},secret=jwtSecret) {
  const e=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
  const body=e({alg:'HS256',typ:'JWT'})+'.'+e({role:'authenticated',sub:id,session_id:sid,is_anonymous:false,exp:Math.floor(Date.now()/1000)+300,...override});
  return body+'.'+createHmac('sha256',secret).update(body).digest('base64url');
}
async function call(name,body,token) {
  return fetch(new URL('/rpc/'+name,http),{method:'POST',headers:{'content-type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body),redirect:'error',signal:AbortSignal.timeout(5000)});
}
let checks=0;
async function check(label,fn){await fn();checks++;console.log('PASS '+label);}
try {
  const admin=await connection(ids[0],sessions[0],'postgres');
  assert.match((await admin.query('show server_version')).rows[0].server_version,/^17\./);
  await admin.query(`
    create role authenticated; create role anon; create role service_role;
    create schema auth; create schema private; create schema extensions;
    create extension pgcrypto with schema extensions;
    create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
    create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
    create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
    create table auth.users(id uuid primary key,provider text not null,deleted_at timestamptz,banned_until timestamptz,is_anonymous boolean not null default false);
    create table auth.sessions(id uuid primary key,user_id uuid not null,not_after timestamptz);
    create table public.companies(id uuid primary key,name text not null);
    create table public.company_members(company_id uuid,user_id uuid,role text,primary key(company_id,user_id));
    create table private.master_admins(user_id uuid primary key,enabled boolean not null);
    create table private.master_devices(id uuid primary key,master_user_id uuid not null,device_key text not null,device_name text not null default 'fixture',device_type text not null default 'iphone',platform text,registered_at timestamptz not null default now(),last_used_at timestamptz,is_locked boolean not null default false,revoked_at timestamptz,revoked_by uuid,unique(master_user_id,device_key));
    create table public.user_secondary_credentials(user_id uuid primary key,password_hash text not null,failed_attempts integer not null default 0,locked_until timestamptz,updated_at timestamptz);
    alter table public.user_secondary_credentials enable row level security;
    create function public.is_current_user_master_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.master_admins where user_id=auth.uid() and enabled)$$;
    create table private.account_deletion_access_restrictions(user_id uuid primary key);
    create function private.account_deletion_barrier_key(p_actor uuid) returns bigint language sql immutable set search_path='' as $$select hashtextextended('fixture-deletion:'||p_actor::text,0)$$;
    create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())$$;
    revoke all on schema private,extensions,auth from public,anon,authenticated,service_role;
    grant usage on schema auth,public to authenticated,anon,service_role;
    revoke all on public.user_secondary_credentials,private.master_admins,private.master_devices from public,anon,authenticated,service_role;
  `);
  await admin.query(await fs.readFile(new URL('../../supabase/tests/fixtures/secondary_reset_before.sql',import.meta.url),'utf8'));
  for(let i=0;i<ids.length;i++){
    await admin.query('insert into auth.users(id,provider) values($1,$2)',[ids[i],i===0?'google':i===1?'apple':'phone']);
    await admin.query('insert into auth.sessions values($1,$2,null)',[sessions[i],ids[i]]);
    await admin.query("insert into public.user_secondary_credentials(user_id,password_hash) values($1,extensions.crypt($2,extensions.gen_salt('bf',12)))",[ids[i],secondary]);
  }
  await admin.query("insert into public.companies values('40000000-0000-4000-8000-000000000001','fixture-company')");
  for(let i=0;i<ids.length;i++)await admin.query("insert into public.company_members values('40000000-0000-4000-8000-000000000001',$1,$2)",[ids[i],['owner','admin','manager','viewer','worker','owner','admin','worker'][i]]);
  await admin.query('insert into private.master_admins values($1,true),($2,true),($3,false)',[ids[0],ids[5],ids[6]]);
  await admin.query('insert into private.master_devices(id,master_user_id,device_key) values($1,$2,$3),($4,$5,$6)',[device,ids[0],key,otherDevice,ids[5],otherKey]);
  const snapshot=async()=>(await admin.query(`select jsonb_build_object(
    'users',(select jsonb_agg(to_jsonb(x) order by id) from auth.users x),
    'companies',(select jsonb_agg(to_jsonb(x) order by id) from public.companies x),
    'members',(select jsonb_agg(to_jsonb(x) order by company_id,user_id) from public.company_members x),
    'masters',(select jsonb_agg(to_jsonb(x) order by user_id) from private.master_admins x),
    'secondary_hashes',(select jsonb_agg(jsonb_build_object('user_id',user_id,'password_hash',password_hash) order by user_id) from public.user_secondary_credentials)
  ) value`)).rows[0].value;
  const before=await snapshot();
  const secondaryDefinitions=(await admin.query("select oid::regprocedure::text signature,pg_get_functiondef(oid) def,proacl::text acl from pg_proc where oid in ('public.set_secondary_password(text)'::regprocedure,'public.verify_secondary_password(text)'::regprocedure) order by oid::regprocedure::text")).rows;
  await admin.query(await fs.readFile(new URL('../staged/master_password_credentials.sql.review-only',import.meta.url),'utf8'));
  const user=await connection();
  await check('installation preserves original identity/company/roles/secondary hashes',async()=>assert.deepEqual(await snapshot(),before));
  await check('rollout defaults OFF and cannot be enabled by ordinary API users',async()=>{
    assert.equal((await rpc(user,'master_password_capability')).enabled,false);
    assert.equal((await status(user)).status,'disabled');
    await assert.rejects(user.query('update private.master_password_settings set enabled=true'));
    await admin.query('update private.master_password_settings set enabled=true');
    assert.equal((await rpc(user,'master_password_capability')).enabled,true);
  });
  await check('ordinary roles, disabled master, anonymous and unknown device cannot start setup',async()=>{
    for(const i of [1,2,3,4,6,7]){const c=await connection(ids[i],sessions[i]);assert.notEqual((await begin(c)).status,'challenge');}
    const anon=await connection(ids[0],sessions[0],'anon');await assert.rejects(begin(anon));
    assert.notEqual((await begin(user,'setup',0,randomUUID(),otherKey)).status,'challenge');
  });
  await check('challenge is 120-second, operation/request/version bound, nonce is not stored raw',async()=>{
    const ch=await begin(user);assert.equal(ch.status,'challenge');assert.equal(ch.operation,'setup');assert.equal(ch.expected_version,0);
    assert.match(ch.nonce,/^[0-9a-f]{64}$/);assert.ok(Date.parse(ch.expires_at)>Date.now());assert.ok(Date.parse(ch.expires_at)<=Date.now()+121000);
    const stored=(await admin.query('select to_jsonb(c)::text value from private.master_password_challenges c where id=$1',[ch.challenge_id])).rows[0].value;
    assert.ok(!stored.includes(ch.nonce));assert.ok(stored.includes(createHash('sha256').update(ch.nonce).digest('hex')));
    denied(await finish(user,ch,secondary,masterSecret,key,'0'.repeat(64)));
  });
  await check('setup wrong secret consumes nonce and persists secondary failure without a credential',async()=>{
    const ch=await begin(user);const out=await finish(user,ch,'fixture-wrong-secondary');assert.equal(out.status,'not_verified');
    const count=(await admin.query('select failed_attempts from public.user_secondary_credentials where user_id=$1',[ids[0]])).rows[0].failed_attempts;assert.ok(count>=1);
    denied(await finish(user,ch));assert.equal((await status(user)).configured,false);
  });
  await check('concurrent first setup for another legitimate master inserts exactly one dedicated credential',async()=>{
    const owner=await connection(ids[5],sessions[5]),racer=await connection(ids[5],sessions[5]);
    const a=await begin(owner,'setup',0,randomUUID(),otherKey),b=await begin(owner,'setup',0,randomUUID(),otherKey);
    assert.equal(a.status,'challenge');assert.equal(b.status,'challenge');
    await owner.query('begin');assert.equal((await finish(owner,a,secondary,masterSecret,otherKey)).status,'applied');
    const pid=(await racer.query('select pg_backend_pid() pid')).rows[0].pid;
    const pending=finish(racer,b,secondary,nextSecret,otherKey);let blocked=false;
    for(let n=0;n<100;n++){if((await admin.query('select cardinality(pg_blocking_pids($1))>0 blocked',[pid])).rows[0].blocked){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}
    assert.equal(blocked,true);await owner.query('commit');denied(await pending);
    assert.equal((await admin.query('select count(*)::int n from private.master_password_credentials where master_user_id=$1',[ids[5]])).rows[0].n,1);
  });
  let currentVersion;
  await check('actual bcrypt setup creates a separate hash and idempotent receipt only once',async()=>{
    const ch=await begin(user);const out=await finish(user,ch);assert.equal(out.status,'applied');currentVersion=out.credential_version;assert.ok(currentVersion>=1);
    assert.deepEqual((await read(user,ch.request_id)).result,out);
    const stored=(await admin.query('select password_hash,version from private.master_password_credentials where master_user_id=$1',[ids[0]])).rows[0];
    assert.notEqual(stored.password_hash,before.secondary_hashes.find(x=>x.user_id===ids[0]).password_hash);
    assert.equal((await admin.query('select $1=extensions.crypt($2,$1) ok',[stored.password_hash,masterSecret])).rows[0].ok,true);
    assert.equal((await admin.query('select $1=extensions.crypt($2,$1) ok',[stored.password_hash,secondary])).rows[0].ok,false);
    denied(await finish(user,ch));assert.notEqual((await begin(user,'setup',0)).status,'challenge');
    assert.deepEqual(await snapshot(),before);
  });
  await check('shared secondary cannot replace an existing dedicated Master password',async()=>{
    const ch=await begin(user,'change',currentVersion);assert.equal(ch.status,'challenge');
    assert.equal((await finish(user,ch,secondary,nextSecret)).status,'not_verified');
    assert.equal((await status(user)).credential_version,currentVersion);
  });
  await check('other actor/session/request cannot consume a challenge',async()=>{
    const ch=await begin(user,'change',currentVersion);
    const other=await connection(ids[5],sessions[5]);denied(await finish(other,ch,masterSecret,nextSecret,otherKey));
    const sid=randomUUID();await admin.query('insert into auth.sessions values($1,$2,null)',[sid,ids[0]]);
    const second=await connection(ids[0],sid);denied(await finish(second,ch,masterSecret,nextSecret));
    denied(await finish(user,ch,masterSecret,nextSecret,key,ch.nonce,randomUUID()));
  });
  await check('expiry, session deletion, role removal and device lock reject completion',async()=>{
    for(const mode of ['expiry','session','master','device','account','ban','deleted','anonymous','revoked']){
      const ch=await begin(user,'change',currentVersion);
      if(mode==='expiry')await admin.query("with t as (select clock_timestamp() stamp) update private.master_password_challenges set issued_at=t.stamp-interval '3 minutes',expires_at=t.stamp-interval '1 minute' from t where id=$1",[ch.challenge_id]);
      if(mode==='session')await admin.query('delete from auth.sessions where id=$1',[sessions[0]]);
      if(mode==='master')await admin.query('update private.master_admins set enabled=false where user_id=$1',[ids[0]]);
      if(mode==='device')await admin.query('update private.master_devices set is_locked=true where id=$1',[device]);
      if(mode==='account')await admin.query('insert into private.account_deletion_access_restrictions values($1)',[ids[0]]);
      if(mode==='ban')await admin.query("update auth.users set banned_until=clock_timestamp()+interval '1 minute' where id=$1",[ids[0]]);
      if(mode==='deleted')await admin.query('update auth.users set deleted_at=clock_timestamp() where id=$1',[ids[0]]);
      if(mode==='anonymous')await admin.query('update auth.users set is_anonymous=true where id=$1',[ids[0]]);
      if(mode==='revoked')await admin.query('update private.master_devices set revoked_at=clock_timestamp(),revoked_by=$2 where id=$1',[device,ids[0]]);
      denied(await finish(user,ch,masterSecret,nextSecret));
      if(mode==='session')await admin.query('insert into auth.sessions values($1,$2,null)',[sessions[0],ids[0]]);
      if(mode==='master')await admin.query('update private.master_admins set enabled=true where user_id=$1',[ids[0]]);
      if(mode==='device')await admin.query('update private.master_devices set is_locked=false where id=$1',[device]);
      if(mode==='account')await admin.query('delete from private.account_deletion_access_restrictions where user_id=$1',[ids[0]]);
      if(mode==='ban')await admin.query('update auth.users set banned_until=null where id=$1',[ids[0]]);
      if(mode==='deleted')await admin.query('update auth.users set deleted_at=null where id=$1',[ids[0]]);
      if(mode==='anonymous')await admin.query('update auth.users set is_anonymous=false where id=$1',[ids[0]]);
      if(mode==='revoked')await admin.query('update private.master_devices set revoked_at=null,revoked_by=null where id=$1',[device]);
      // Isolate authorization cases without filling the intentional 5-challenge
      // quota; these are privileged disposable-fixture housekeeping writes.
      await admin.query('update private.master_password_challenges set consumed_at=clock_timestamp() where id=$1 and consumed_at is null',[ch.challenge_id]);
    }
  });
  await check('valid change uses old dedicated password and increments version, invalidating older challenges',async()=>{
    const stale=await begin(user,'change',currentVersion),ch=await begin(user,'change',currentVersion);
    const out=await finish(user,ch,masterSecret,nextSecret);assert.equal(out.status,'applied');assert.equal(out.credential_version,currentVersion+1);currentVersion=out.credential_version;
    denied(await finish(user,stale,masterSecret,'fixture-never-applied'));
    const stored=(await admin.query('select password_hash from private.master_password_credentials where master_user_id=$1',[ids[0]])).rows[0].password_hash;
    assert.equal((await admin.query('select $1=extensions.crypt($2,$1) ok',[stored,nextSecret])).rows[0].ok,true);
  });
  await check('independent connections serialize a version race with one committed winner',async()=>{
    const first=await begin(user,'change',currentVersion),second=await begin(user,'change',currentVersion),racer=await connection();
    await user.query('begin');const applied=await finish(user,first,nextSecret,masterSecret);assert.equal(applied.status,'applied');
    const pid=(await racer.query('select pg_backend_pid() pid')).rows[0].pid;const pending=finish(racer,second,nextSecret,'fixture-race-loser');let blocked=false;
    for(let n=0;n<100;n++){if((await admin.query('select cardinality(pg_blocking_pids($1))>0 blocked',[pid])).rows[0].blocked){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}
    assert.equal(blocked,true);await user.query('commit');denied(await pending);currentVersion=applied.credential_version;
  });
  await check('rolled-back operation leaves no applied receipt or credential change',async()=>{
    const ch=await begin(user,'change',currentVersion);await user.query('begin');assert.equal((await finish(user,ch,masterSecret,nextSecret)).status,'applied');await user.query('rollback');
    assert.equal((await status(user)).credential_version,currentVersion);assert.equal((await read(user,ch.request_id)).status,'not_found');
    assert.equal((await finish(user,ch,masterSecret,nextSecret)).status,'applied');currentVersion++;
  });
  await check('unlock accepts dedicated password only, is one-use and returns no secrets',async()=>{
    const verify=(ch,password)=>rpc(user,'verify_master_password_operation',[key,ch.challenge_id,ch.nonce,password,ch.request_id],['text','uuid','text','text','uuid']);
    const wrong=await begin(user,'unlock',currentVersion);assert.equal(wrong.status,'challenge');
    assert.equal((await verify(wrong,secondary)).status,'not_verified');
    const ch=await begin(user,'unlock',currentVersion),out=await verify(ch,nextSecret);
    assert.equal(out.status,'verified');assert.equal(out.operation,'unlock');assert.equal(out.credential_version,currentVersion);
    assert.doesNotMatch(JSON.stringify(out),/password_hash|nonce|fixture-independent|fixture-common/);
    assert.deepEqual((await read(user,ch.request_id)).result,out);
    assert.notEqual((await verify(ch,nextSecret)).status,'verified');
    const change=await begin(user,'change',currentVersion);assert.notEqual((await verify(change,nextSecret)).status,'verified');
  });
  await check('dedicated incorrect password attempts persist and lock without changing credentials',async()=>{
    for(let n=0;n<5;n++){const ch=await begin(user,'change',currentVersion);if(ch.status!=='challenge'){assert.equal(ch.status,'locked');break;}const out=await finish(user,ch,'fixture-wrong-master');assert.ok(['not_verified','locked'].includes(out.status));}
    const attempts=(await admin.query('select failed_attempts,locked_until from private.master_password_attempts where actor=$1',[ids[0]])).rows[0];assert.ok(attempts.failed_attempts>=5);assert.ok(+new Date(attempts.locked_until)>Date.now());
    assert.equal((await status(user)).credential_version,currentVersion);
  });
  await check('direct private access and anonymous RPC execution stay denied',async()=>{
    for(const table of ['master_password_credentials','master_password_challenges','master_password_attempts','master_password_requests','master_password_settings']){
      assert.equal((await admin.query("select has_table_privilege('authenticated',$1,'SELECT') ok",['private.'+table])).rows[0].ok,false);
      assert.equal((await admin.query("select has_table_privilege('anon',$1,'SELECT') ok",['private.'+table])).rows[0].ok,false);
    }
  });
  await check('real signed HTTP rejects absent/bad/expired tokens and normal roles',async()=>{
    await admin.query("notify pgrst,'reload schema'");let ready=false;
    for(let n=0;n<50;n++){try{const r=await fetch(http,{signal:AbortSignal.timeout(1000)});if(r.ok&&(await r.text()).includes('current_master_password_status')){ready=true;break;}}catch{}await new Promise(r=>setTimeout(r,200));}
    assert.equal(ready,true);
    for(const token of [undefined,jwt(ids[0],sessions[0],{},'fixture-wrong-signature'),jwt(ids[0],sessions[0],{exp:1})]){
      assert.ok([401,403].includes((await call('current_master_password_status',{p_device_key:key},token)).status));
    }
    for(const i of [1,2,3,4,6,7]){
      const r=await call('begin_master_password_operation',{p_device_key:key,p_operation:'setup',p_expected_version:0,p_request_id:randomUUID()},jwt(ids[i],sessions[i]));
      assert.ok(r.status===403||(r.ok&&(await r.json()).status==='denied'));
    }
    const r=await call('current_master_password_status',{p_device_key:key},jwt());assert.equal(r.status,200);assert.equal((await r.json()).configured,true);
  });
  await check('all original identities/roles/company/secondary hashes and original RPC definitions survive',async()=>{
    // Additional synthetic session belongs only to the fixture.
    assert.deepEqual(await snapshot(),before);
    const after=(await admin.query("select oid::regprocedure::text signature,pg_get_functiondef(oid) def,proacl::text acl from pg_proc where oid in ('public.set_secondary_password(text)'::regprocedure,'public.verify_secondary_password(text)'::regprocedure) order by oid::regprocedure::text")).rows;
    assert.deepEqual(after,secondaryDefinitions);
  });
  console.log('PASS '+checks+' PostgreSQL 17/pgcrypto and signed HTTP checks; no production connection or data used.');
  console.log('LIMIT: Auth session/user rows are synthetic prerequisites, JWTs fixture-signed, not real GoTrue/OAuth/device/Face ID or complete production schema validation.');
} finally { await Promise.all(conns.map(c=>c.end())); }
