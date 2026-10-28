// Invoked only by the disposable GoTrue harness. Business authority and the DB
// pool are explicit fixtures, while Auth user/session rows and candidate SQL/
// password/proof/Ed25519 operations are real. No public endpoint is deployed.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {generateKeyPairSync,randomUUID,sign} from 'node:crypto';
import {verifyScannerRegistrationBearer} from './qr-scanner-verified-session.mjs';
import {createScannerRegistrationChallengeAdapter} from './qr-scanner-challenge-adapter.mjs';
import {createScannerRegistrationProofIssuer} from './qr-scanner-proof-issuer.mjs';
import {scannerRegistrationSigningBytes} from './qr-scanner-possession.mjs';
import {createRecoverableScannerRegistrationAdapter} from './qr-scanner-registration-recovery.mjs';

export async function exerciseScannerRealAuth({db,database,api,anon,makeUser,request}) {
 if(process.env.CI!=='true'||api.hostname!=='127.0.0.1'||api.port!=='53781'||database.hostname!=='127.0.0.1'||database.port!=='53782')throw Error('disposable scanner fixture required');
 const root=process.cwd(),base=path.join(root,'tool/qr-attendance');
 const manager=await makeUser(),stranger=await makeUser(),company=randomUUID(),device=randomUUID();
 const pg=(await import(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 const pool=new pg.Pool({connectionString:database.href,max:1});let acquisitions=0;
 const counted={connect:async()=>{acquisitions++;return pool.connect();}};
 const keys=generateKeyPairSync('ed25519'),keyHex=keys.publicKey.export({type:'spki',format:'der'}).toString('hex');
 const target={companyId:company,deviceId:device,keyHex};
 const tokenClaims=t=>JSON.parse(Buffer.from(t.split('.')[1],'base64url').toString('utf8'));
 const project='https://scanner-real-auth-fixture.invalid';
 // Only this test maps the fixed HTTPS project origin to the owned loopback
 // stack. The production verifier retains HTTPS/origin and redirect checks.
 const bridge=async(url,options)=>{
  assert.equal(String(url),project+'/auth/v1/user');assert.equal(options.redirect,'error');
  const actual=new URL('/auth/v1/user',api);assert.equal(actual.origin,api.origin);
  return fetch(actual,options);
 };
 const verified=token=>verifyScannerRegistrationBearer({enabled:true,projectOrigin:project,
  expectedIssuer:tokenClaims(manager.access_token).iss,publicKey:anon,bearer:token,fetchImpl:bridge});
 const challenge=async(token,targetValue=target)=>createScannerRegistrationChallengeAdapter({pool:counted,
  initializeVerifiedSession:await verified(token)}).issue(targetValue);
 const proof=async(token,id,password)=>createScannerRegistrationProofIssuer({pool:counted,
  initializeVerifiedSession:await verified(token)}).issue({challengeId:id,password});
 const complete=async(token,value,requestPool=counted)=>createRecoverableScannerRegistrationAdapter({enabled:true,pool:requestPool,
  initializeVerifiedSession:await verified(token)}).complete(value);
 const recover=async(token,value)=>createRecoverableScannerRegistrationAdapter({enabled:true,pool:counted,
  initializeVerifiedSession:await verified(token)}).read(value);
 const clean=async()=>{
  const c=await pool.connect();try{const row=(await c.query("select auth.uid() actor,nullif(current_setting('request.jwt.claims',true),'') claims,current_user role")).rows[0];
   assert.equal(row.actor,null);assert.equal(row.claims,null);assert.equal(row.role,'postgres');
  }finally{c.release();}
 };
 try {
  await db.query(`create table public.companies(id uuid primary key);
   create table public.company_members(company_id uuid,user_id uuid);
   create table public.workers(id uuid primary key,company_id uuid,user_id uuid,status text);
   create table private.scanner_fixture_permissions(company_id uuid,user_id uuid);
   create function private.has_company_feature(p_company uuid,p_feature text) returns boolean language sql as $$
    select p_feature='can_manage_attendance' and exists(select from private.scanner_fixture_permissions where company_id=p_company and user_id=auth.uid()) $$;`);
  await db.query('insert into public.companies values($1)',[company]);
  await db.query('insert into public.company_members values($1,$2)',[company,manager.user.id]);
  await db.query('insert into private.scanner_fixture_permissions values($1,$2)',[company,manager.user.id]);
  await db.query(await fs.readFile(path.join(base,'qr-scanner-context.sql.review-only'),'utf8'));
  await db.query(await fs.readFile(path.join(base,'qr-scanner-registration.sql.review-only'),'utf8'));
  await db.query(await fs.readFile(path.join(base,'qr-scanner-possession.sql.review-only'),'utf8'));
  await db.query(await fs.readFile(path.join(base,'qr-scanner-challenge-read.sql.review-only'),'utf8'));
  await db.query("create schema if not exists extensions;create extension if not exists pgcrypto with schema extensions;");
  await db.query('create table public.user_secondary_credentials(user_id uuid primary key,password_hash text not null,failed_attempts int not null default 0,locked_until timestamptz,updated_at timestamptz)');
  await db.query('revoke all on public.user_secondary_credentials from public,anon,authenticated,service_role');
  const staged=await fs.readFile(path.join(root,'tool/staged/reauthentication_proofs.sql'),'utf8');
  const start=staged.indexOf('create table private.reauthentication_proofs ('),end=staged.indexOf('create function private.reauthentication_scope');assert.ok(start>0&&end>start);
  await db.query(staged.slice(start,end));
  await db.query("create or replace function private.reauthentication_required(p_scope text) returns boolean language sql as $$select p_scope='secondary_password'$$");
  const migration=await fs.readFile(path.join(root,'supabase/migrations/20260919193000_add_secure_admin_onboarding.sql'),'utf8');
  const passwordStart=migration.indexOf('create or replace function public.verify_secondary_password(p_password text)'),passwordEnd=migration.indexOf('revoke execute on function public.secondary_password_configured()',passwordStart);
  assert.ok(passwordStart>0&&passwordEnd>passwordStart);await db.query(migration.slice(passwordStart,passwordEnd));
  await db.query("insert into public.user_secondary_credentials values($1,extensions.crypt('synthetic-scanner-password',extensions.gen_salt('bf',4)),0,null,clock_timestamp())",[manager.user.id]);
  await db.query(await fs.readFile(path.join(base,'qr-scanner-registration-proof.sql.review-only'),'utf8'));
  await db.query(await fs.readFile(path.join(base,'qr-scanner-registration-receipt.sql.review-only'),'utf8'));
  await assert.rejects(challenge(manager.access_token));await clean(); // real QR gate remains OFF
  await db.query("update private.master_feature_settings set enabled=true where feature_key='qr_attendance'");
  const c=await challenge(manager.access_token);assert.equal(c.actor,manager.user.id);assert.equal(c.session,tokenClaims(manager.access_token).session_id);await clean();
  assert.deepEqual(await proof(manager.access_token,c.id,'synthetic-wrong'),{accepted:false});
  assert.equal((await db.query('select failed_attempts from public.user_secondary_credentials')).rows[0].failed_attempts,1);await clean();
  const accepted=await proof(manager.access_token,c.id,'synthetic-scanner-password');assert.equal(accepted.accepted,true);
  const payload={challengeId:c.id,signature:sign(null,scannerRegistrationSigningBytes(c),keys.privateKey),reauthenticationProof:accepted.proof};
  assert.deepEqual(await complete(manager.access_token,payload),{deviceId:device});await clean();
  await assert.rejects(complete(manager.access_token,payload));await clean();
  assert.equal((await db.query('select count(*)::int n from qr_attendance_private.scanner_registration_events')).rows[0].n,1);
  const firstReceipt=await recover(manager.access_token,{...target,challengeId:c.id});
  assert.equal(firstReceipt.challengeId,c.id);assert.equal(firstReceipt.deviceId,device);await clean();
  // An independently authenticated new SID for the same UID cannot recover the
  // old operation. No new session is manufactured as a production workaround.
  const linkResponse=await request('/auth/v1/admin/generate_link',{admin:true,body:{type:'magiclink',email:manager.user.email}});
  assert.equal(linkResponse.status,200);const link=await linkResponse.json();
  const signedResponse=await request('/auth/v1/verify',{body:{type:'magiclink',token_hash:link.hashed_token}});
  assert.equal(signedResponse.status,200);const otherSid=await signedResponse.json();
  assert.equal(otherSid.user.id,manager.user.id);assert.notEqual(tokenClaims(otherSid.access_token).session_id,tokenClaims(manager.access_token).session_id);
  assert.equal(await recover(otherSid.access_token,{...target,challengeId:c.id}),null);await clean();
  const lostTarget={...target,deviceId:randomUUID()},lost=await challenge(manager.access_token,lostTarget);
  const lostProof=await proof(manager.access_token,lost.id,'synthetic-scanner-password');assert.equal(lostProof.accepted,true);
  const lostCommand={challengeId:lost.id,signature:sign(null,scannerRegistrationSigningBytes(lost),keys.privateKey),reauthenticationProof:lostProof.proof};
  const uncertainPool={connect:async()=>{const connection=await counted.connect();return {
   query:async(sql,args)=>{const result=await connection.query(sql,args);if(sql==='commit')throw Error('synthetic lost COMMIT response');return result;},
   release:discard=>connection.release(discard)};}};
  await assert.rejects(complete(manager.access_token,lostCommand,uncertainPool));await clean();
  const recovered=await recover(manager.access_token,{...lostTarget,challengeId:lost.id});
  assert.equal(recovered.deviceId,lostTarget.deviceId);assert.equal(recovered.challengeId,lost.id);
  assert.deepEqual(await recover(manager.access_token,{...lostTarget,challengeId:lost.id}),recovered);await clean();
  assert.equal((await db.query('select count(*)::int n from qr_attendance_private.scanner_registration_events')).rows[0].n,2);
  assert.equal((await db.query('select count(*)::int n from qr_attendance_private.scanner_registration_receipts')).rows[0].n,2);
  await assert.rejects(complete(manager.access_token,lostCommand));await clean();
  await db.query("update private.master_feature_settings set enabled=false where feature_key='qr_attendance'");
  await assert.rejects(recover(manager.access_token,{...lostTarget,challengeId:lost.id}));await clean();
  await db.query("update private.master_feature_settings set enabled=true where feature_key='qr_attendance'");
  const attackerMetadata=await request('/auth/v1/user',{method:'PUT',token:stranger.access_token,body:{data:{can_manage_attendance:true,company_id:company}}});assert.equal(attackerMetadata.status,200);
  await assert.rejects(challenge(stranger.access_token,{...target,deviceId:randomUUID()}));await clean();
  const parts=manager.access_token.split('.'),forged=[parts[0],Buffer.from(JSON.stringify({...tokenClaims(manager.access_token),sub:stranger.user.id})).toString('base64url'),parts[2]].join('.');
  const before=acquisitions;await assert.rejects(challenge(forged));assert.equal(acquisitions,before);await clean();
  const next={...target,deviceId:randomUUID()};
  await db.query("update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=$1",[tokenClaims(manager.access_token).session_id]);
  await assert.rejects(challenge(manager.access_token,next));await clean();
  await db.query('update auth.sessions set not_after=null where id=$1',[tokenClaims(manager.access_token).session_id]);
  // A request verified before revocation must still fail when SQL binds it.
  const delayed=await verified(manager.access_token);
  await db.query('delete from auth.sessions where id=$1',[tokenClaims(manager.access_token).session_id]);
  await assert.rejects(createScannerRegistrationChallengeAdapter({pool:counted,initializeVerifiedSession:delayed}).issue(next));await clean();
  await assert.rejects(recover(manager.access_token,{...lostTarget,challengeId:lost.id}));await clean();
  assert.equal((await db.query('select count(*)::int n from qr_attendance_private.registered_scanners')).rows[0].n,2);
  assert.equal((await db.query('select count(*)::int n from qr_attendance_private.scanner_registration_receipts')).rows[0].n,2);
  console.log('PASS isolated real GoTrue -> scanner challenge -> bcrypt proof -> Ed25519 registration; OFF, metadata, tampered JWT, expired/deleted SID and pool cleanup');
  console.log('PASS isolated real GoTrue lost-COMMIT registration receipt recovery; exact old SID, same-UID other SID denied, one audit/receipt, no relink/re-register or receipt deletion');
  console.log('LIMIT synthetic company permissions and privileged pool; no public endpoint, real device custody, normal QR attendance writer or production activation');
 } finally {
  await db.query("update private.master_feature_settings set enabled=false where feature_key='qr_attendance'");
  await pool.end();
 }
}
