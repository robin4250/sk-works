import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import{pathToFileURL}from'node:url';
process.on('uncaughtException',e=>{console.error(JSON.stringify({error:e.message,where:e.where,query:e.query}));process.exit(1)});
const here=import.meta.dirname,{PGlite}=await import(pathToFileURL(path.resolve(process.argv[2]))),db=new PGlite();
const native=process.argv.includes('--native');
await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema private;create schema extensions;
create function auth.jwt()returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create function auth.uid()returns uuid language sql stable as $$select(auth.jwt()->>'sub')::uuid$$;
create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz,deleted_at timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
create table private.account_deletion_access_restrictions(user_id uuid);
create table private.master_admins(user_id uuid primary key,enabled boolean);
create table public.company_members(company_id uuid,user_id uuid,role text,primary key(company_id,user_id));
create table public.user_secondary_credentials(user_id uuid primary key,password_hash text,failed_attempts integer default 0,locked_until timestamptz,updated_at timestamptz);
create function private.account_deletion_barrier_key(p uuid)returns bigint language sql immutable as $$select hashtextextended(p::text,781)$$;
`);
if(native)await db.exec('create extension pgcrypto with schema extensions');
else await db.exec(`create function extensions.digest(p bytea,alg text)returns bytea language sql immutable as $$select sha256(p)$$;
create function extensions.gen_random_bytes(n integer)returns bytea language sql volatile as $$select decode(replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''),'hex')$$;
create function extensions.crypt(p text,h text)returns text language sql immutable as $$select 'fixture:'||p$$;`);
for(const f of JSON.parse(fs.readFileSync(path.join(here,'current-core-fixtures.json'),'utf8')))await db.exec(f.definition);
await db.exec(fs.readFileSync(path.join(here,'management-issuer.sql.review-only'),'utf8'));
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const actor=id(1),sid=id(2),company=id(3),other=id(4),otherSid=id(5);
const jwt=(a=actor,s=sid,role='authenticated')=>JSON.stringify({sub:role==='service_role'?null:a,session_id:s,role,is_anonymous:false});
await db.query('select set_config($1,$2,false)',['request.jwt.claims',jwt()]);
await db.query('insert into auth.users(id)values($1),($2)',[actor,other]);await db.query('insert into auth.sessions values($1,$2,null),($3,$4,null)',[sid,actor,otherSid,other]);
await db.query('insert into private.master_admins values($1,true),($2,true)',[actor,other]);await db.query("insert into company_members values($1,$2,'owner'),($1,$3,'owner')",[company,actor,other]);
await db.query(native?"insert into user_secondary_credentials(user_id,password_hash)values($1,extensions.crypt('correct',extensions.gen_salt('bf',4)))":"insert into user_secondary_credentials(user_id,password_hash)values($1,'fixture:correct')",[actor]);
const jwk={kty:'OKP',crv:'Ed25519',x:'A'.repeat(43)};
await db.query('insert into security_management_issuer_private.deployments(deployment_id,company_id,owner_id,key_id,key_version,manager_jwk)values($1,$2,$3,$4,1,$5)',['deployment_1',company,actor,'manager_1',jwk]);
const command={deployment_id:'deployment_1',action:'quarantine',reason:'operator_review',expected_policy_revision:1,expected_trust_revision:1};
const prepare=async(password='correct',c=command)=>(await db.query('select public.prepare_decoy_management_proof($1,$2,$3)v',[company,c,password])).rows[0].v;
const claim=async proof=>(await db.query('select public.claim_decoy_management_command($1)v',[proof])).rows[0].v;
const owner=async()=>{await db.exec('reset role');await db.query('select set_config($1,$2,false)',['request.jwt.claims',jwt()])};
const service=async()=>{await db.query('select set_config($1,$2,false)',['request.jwt.claims',jwt(actor,sid,'service_role')]);await db.exec('set role service_role')};
const auth=async(a=actor,s=sid)=>{await db.exec('reset role');await db.query('select set_config($1,$2,false)',['request.jwt.claims',jwt(a,s)]);await db.exec('set role authenticated')};
const finish=async(c,signature='a'.repeat(128))=>(await db.query('select public.complete_decoy_management_command($1,$2,$3,$4)v',[c.command_id,c.lease_id,c.payload_hash,signature])).rows[0].v;
let checks=0;
await auth();await assert.rejects(prepare(),/disabled/);checks++;
await owner();await db.exec('update security_management_issuer_private.deployments set enabled=true');await auth();
for(let i=1;i<=5;i++){assert.deepEqual(await prepare('wrong'),{verified:false,reason:'secondary_password_rejected'});checks++;}
await owner();const failed=(await db.query('select failed_attempts,locked_until>clock_timestamp()locked from user_secondary_credentials')).rows[0];assert.equal(failed.failed_attempts,5);assert.equal(failed.locked,true);checks++;
await auth();await assert.rejects(prepare(),/temporarily locked/);checks++;
await owner();await db.exec('update user_secondary_credentials set failed_attempts=0,locked_until=null');await auth();
for(const c of [{...command,action:'recover_manager'},{...command,reason:'recovery_lost_key'},{...command,subject:other},{...command,action:null}]){await assert.rejects(prepare('correct',c),/rejected/);checks++;}
const p=await prepare();assert.equal(p.verified,true);assert.equal(p.operation,'master.security_decoy.manage');checks++;
await assert.rejects(claim('b'.repeat(64)),/proof_rejected/);checks++;
await auth(other,otherSid);await assert.rejects(claim(p.proof),/proof_rejected/);checks++;
await auth();const c=await claim(p.proof);assert.equal(c.state,'claimed');assert.equal(c.actor_id,actor);assert.equal(c.session_id,sid);checks++;
const payload=JSON.parse(c.payload_body);assert.deepEqual(payload,c.payload);assert.equal(payload.subject,actor);assert.equal(payload.company_id,company);assert.equal(payload.expires_at-payload.issued_at,60000);checks++;
assert.equal((await claim(p.proof)).state,'pending');checks++;
await assert.rejects(finish(c),/permission denied/);checks++;
await service();await assert.rejects(finish({...c,payload_hash:'f'.repeat(64)}),/rejected/);checks++;
const receipt=await finish(c);assert.deepEqual(receipt.payload,payload);assert.deepEqual(await finish(c),receipt);checks++;
await assert.rejects(finish(c,'b'.repeat(128)),/signature_conflict/);checks++;
await auth();assert.deepEqual((await claim(p.proof)).receipt,receipt);checks++;
await owner();assert.equal((await db.query('select count(*)::int n from security_management_issuer_private.commands')).rows[0].n,1);assert.equal((await db.query("select count(*)::int n from security_management_issuer_private.audit where kind='signed'")).rows[0].n,1);checks++;
await db.exec('update private.master_admins set enabled=false');await auth();await assert.rejects(claim(p.proof),/master_unavailable/);checks++;
await owner();await db.exec('update private.master_admins set enabled=true');await auth();const p2=await prepare(),c2=await claim(p2.proof);
await owner();await db.query('delete from auth.sessions where id=$1',[sid]);await service();await assert.rejects(finish(c2),/session_unavailable/);checks++;
await owner();await db.query('insert into auth.sessions values($1,$2,null)',[sid,actor]);await db.exec("update user_secondary_credentials set password_hash=password_hash||'changed'");await service();await assert.rejects(finish(c2),/binding_changed/);checks++;
await owner();await db.exec("update user_secondary_credentials set password_hash=replace(password_hash,'changed','')");await auth();
const p3=await prepare(),c3=await claim(p3.proof);await service();await db.query('select public.fail_decoy_management_command($1,$2,$3)',[c3.command_id,c3.lease_id,'key_unavailable']);await auth();const retry=await claim(p3.proof);assert.equal(retry.state,'claimed');assert.notEqual(retry.lease_id,c3.lease_id);assert.equal(retry.payload_body,c3.payload_body);checks++;
await service();await assert.rejects(finish(c3),/rejected/);checks++;
await owner();await db.exec('update security_management_issuer_private.deployments set revision=revision+1');await service();await assert.rejects(finish(retry),/binding_changed/);checks++;
await owner();await assert.rejects(db.exec('delete from security_management_issuer_private.audit'),/audit_immutable/);checks++;
for(const role of ['anon','authenticated','service_role']){await db.exec('reset role');await db.exec('set role '+role);await assert.rejects(db.exec('select * from security_management_issuer_private.proofs'),/permission denied/);checks++;}
await owner();await db.exec('update security_management_issuer_private.deployments set enabled=true');await auth();
const gateProof=await prepare();await owner();await db.exec('update security_management_issuer_private.deployments set enabled=false');await auth();await assert.rejects(claim(gateProof.proof),/disabled/);checks++;
await owner();await db.exec('update security_management_issuer_private.deployments set enabled=true');await auth();const roleProof=await prepare();await owner();await db.query("update company_members set role='employee'where user_id=$1",[actor]);await auth();await assert.rejects(claim(roleProof.proof),/company_unavailable/);checks++;
await owner();await db.query("update company_members set role='owner'where user_id=$1",[actor]);await db.query('insert into auth.sessions values($1,$2,null)',[id(6),actor]);await auth(actor,id(6));await assert.rejects(claim(roleProof.proof),/proof_rejected/);checks++;
await auth();const expired=await prepare();await owner();await db.exec('alter table security_management_issuer_private.proofs disable trigger management_proof_immutable');await db.query("update security_management_issuer_private.proofs set created_at=statement_timestamp()-interval '61 seconds',expires_at=statement_timestamp()-interval '1 second'where command_id=$1",[expired.command_id]);await db.exec('alter table security_management_issuer_private.proofs enable trigger management_proof_immutable');await auth();await assert.rejects(claim(expired.proof),/proof_rejected/);checks++;
await owner();await assert.rejects(db.exec("update security_management_issuer_private.proofs set payload_hash=repeat('f',64)"),/ledger_immutable/);checks++;await assert.rejects(db.exec('delete from security_management_issuer_private.commands'),/ledger_immutable/);checks++;
if(native){
 const runtime=await import(pathToFileURL(path.resolve(process.argv[2]))),left=await runtime.connectFixture(),right=await runtime.connectFixture();
 try{
  await auth();const parallel=await prepare();await owner();
  for(const c of [left,right]){await c.query('select set_config($1,$2,false)',['request.jwt.claims',jwt()]);await c.query('set role authenticated');}
  const claimSql='select public.claim_decoy_management_command($1)v';const rs=await Promise.all([left.query(claimSql,[parallel.proof]),right.query(claimSql,[parallel.proof])]);
  assert.deepEqual(rs.map(x=>x.rows[0].v.state).sort(),['claimed','pending']);checks++;
  assert.equal((await db.query('select count(*)::int n from security_management_issuer_private.commands where command_id=$1',[parallel.command_id])).rows[0].n,1);checks++;
  const cc=rs.map(x=>x.rows[0].v).find(x=>x.state==='claimed');
  // Two invalid passwords serialize in the real credential verifier, preserving
  // both counters rather than deadlocking on a pre-verification SHARE lock.
  const bad=await Promise.all([left.query('select public.prepare_decoy_management_proof($1,$2,$3)v',[company,command,'wrong']),right.query('select public.prepare_decoy_management_proof($1,$2,$3)v',[company,command,'wrong'])]);
  assert.ok(bad.every(x=>x.rows[0].v.verified===false));assert.equal((await db.query('select failed_attempts from user_secondary_credentials where user_id=$1',[actor])).rows[0].failed_attempts,2);checks++;
  await left.query('reset role');await left.query('select set_config($1,$2,false)',['request.jwt.claims',jwt(actor,sid,'service_role')]);await left.query('set role service_role');await left.query('begin');
  assert.ok((await left.query('select public.complete_decoy_management_command($1,$2,$3,$4)v',[cc.command_id,cc.lease_id,cc.payload_hash,'a'.repeat(128)])).rows[0].v.signature);checks++;
  await right.query('reset role');let deletionDone=false;const deletion=right.query('delete from auth.sessions where id=$1',[sid]).then(()=>deletionDone=true);
  const end=Date.now()+2000;let waiting=false;while(Date.now()<end){waiting=(await db.query("select exists(select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock')ok",[right.processID])).rows[0].ok;if(waiting)break;await new Promise(r=>setTimeout(r,10));}
  assert.equal(waiting,true);assert.equal(deletionDone,false);checks++;
  await left.query('commit');await deletion;checks++;
  await right.query('select set_config($1,$2,false)',['request.jwt.claims',jwt()]);await right.query('set role authenticated');await assert.rejects(right.query(claimSql,[parallel.proof]),/reauthentication_required/);checks++;
 }finally{await left.query('rollback');await left.end();await right.end();}
}
await owner();
console.log(JSON.stringify({checks,nativePgcrypto:native,actualPasswordVerifierControlFlow:true,localCryptoStub:!native,productionApplied:false}));await db.close();
