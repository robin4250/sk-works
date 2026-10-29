// Disposable-only proof issuer -> existing PoP registration composition.
// Auth/session/permission/rollout are synthetic; the password verifier, proof
// ledger, issuer/consumer and scanner registration/PoP SQL are actual candidates.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {generateKeyPairSync,randomBytes,sign} from 'node:crypto';
import {scannerRegistrationSigningBytes,createScannerRegistrationPossessionAdapter} from './qr-scanner-possession.mjs';
import {createScannerRegistrationProofIssuer,createScannerProofIssuanceReader} from './qr-scanner-proof-issuer.mjs';
import {createScannerRegistrationChallengeAdapter} from './qr-scanner-challenge-adapter.mjs';
import {createRecoverableScannerRegistrationAdapter} from './qr-scanner-registration-recovery.mjs';
const base=dirname(new URL(import.meta.url).pathname),root=resolve(process.argv[3]??'.');
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const expand=p=>readFileSync(p,'utf8').split('\n').filter(x=>!x.startsWith('\\set')).map(x=>x.startsWith('\\ir ')?expand(resolve(dirname(p),x.slice(4))):x).join('\n');
let admin,pool,created=false,database,tearingDown=false;let phase='setup';
if(process.argv[2]){
 const {PGlite}=await import(resolve(process.argv[2]));const {pgcrypto}=await import(resolve(dirname(process.argv[2]),'contrib/pgcrypto.js'));
 const db=new PGlite({extensions:{pgcrypto}});const query=async(s,v)=>v?db.query(s,v):(await db.exec(s)).at(-1)||{rows:[]};
 pool={query,connect:async()=>({query,release(){}}),end:async()=>db.close()};
}else{
 if(process.env.CI!=='true'||process.env.PGHOST!=='127.0.0.1')throw Error('disposable loopback CI required');
 const pg=(await import(resolve('tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 admin=new pg.Client();await admin.connect();database='qr_proof_'+randomBytes(8).toString('hex');
 await admin.query(`create database ${database}`);created=true;pool=new pg.Pool({database,max:4});
 pool.on('error',error=>{if(tearingDown&&error?.code==='57P01')return;console.error('QR proof fixture pool error');process.exitCode=1;});
}
const fixtureSession=async c=>{await c.query("select set_config('fixture.actor',$1,true),set_config('fixture.session',$2,true),set_config('fixture.live','yes',true),set_config('fixture.manage','yes',true),set_config('fixture.qr','yes',true),set_config('fixture.secondary','yes',true)",[id(5),id(6)]);return {actor:id(5),session:id(6)};};
const issuer=()=>createScannerRegistrationProofIssuer({pool,initializeVerifiedSession:fixtureSession});
const recoverable=process.env.SKO_QR_REGISTRATION_RECEIPTS_FIXTURE==='1';
const registration=recoverable?{complete:value=>createRecoverableScannerRegistrationAdapter({enabled:true,pool,initializeVerifiedSession:fixtureSession}).complete(value)}:
 createScannerRegistrationPossessionAdapter({pool,initializeVerifiedSession:fixtureSession});
async function challenge(device){const keys=generateKeyPairSync('ed25519'),keyHex=keys.publicKey.export({type:'spki',format:'der'}).toString('hex');
 const adapter=createScannerRegistrationChallengeAdapter({pool,initializeVerifiedSession:fixtureSession});
 const target={companyId:id(1),deviceId:device,keyHex};
 const value=await adapter.issue(target);
 const reread=await createScannerRegistrationChallengeAdapter({pool,initializeVerifiedSession:fixtureSession}).read(target);
 assert.equal(reread.id,value.id);assert.equal(reread.nonce,value.nonce);assert.equal(reread.expiresMs,value.expiresMs);
 return {challengeId:value.id,signature:sign(null,scannerRegistrationSigningBytes(value),keys.privateKey)};
}

const proofCount=async()=>(await pool.query('select count(*)::int n from private.reauthentication_proofs')).rows[0].n;
const wrong=async challengeId=>assert.deepEqual(await issuer().issue({challengeId,password:'synthetic-wrong'}),{accepted:false});
try{
 await pool.query(expand(resolve(base,'qr-scanner-registration-test.sql')));
 await pool.query('drop trigger reject_test_audit on qr_attendance_private.scanner_registration_events');
 await pool.query(readFileSync(resolve(base,'qr-scanner-possession.sql.review-only'),'utf8'));
 await pool.query('create schema extensions;create extension pgcrypto with schema extensions');
 await pool.query('create table public.user_secondary_credentials(user_id uuid primary key,password_hash text not null,failed_attempts int not null default 0,locked_until timestamptz,updated_at timestamptz)');
 await pool.query('revoke all on public.user_secondary_credentials from public,anon,authenticated,service_role');
 const staged=readFileSync(resolve(root,'tool/staged/reauthentication_proofs.sql'),'utf8');
 await pool.query(staged.slice(staged.indexOf('create table private.reauthentication_proofs ('),staged.indexOf('create function private.reauthentication_scope')));
 await pool.query("create function private.reauthentication_required(text) returns boolean language sql as $$select current_setting('fixture.secondary',true)='yes'$$");
 const migration=readFileSync(resolve(root,'supabase/migrations/20260919193000_add_secure_admin_onboarding.sql'),'utf8');
 const start=migration.indexOf('create or replace function public.verify_secondary_password(p_password text)');
 assert.ok(start>=0);const end=migration.indexOf('revoke execute on function public.secondary_password_configured()',start);assert.ok(end>start);
 await pool.query(migration.slice(start,end));
 await pool.query("insert into public.user_secondary_credentials values($1,extensions.crypt('synthetic-correct',extensions.gen_salt('bf',4)),0,null,clock_timestamp())",[id(5)]);
 const genericBefore=(await pool.query("select prosrc from pg_proc where oid='private.consume_reauthentication_proof(text,jsonb,text)'::regprocedure")).rows[0].prosrc;
 await pool.query(readFileSync(resolve(base,'qr-scanner-registration-proof.sql.review-only'),'utf8'));
 assert.equal((await pool.query("select prosrc from pg_proc where oid='private.consume_reauthentication_proof(text,jsonb,text)'::regprocedure")).rows[0].prosrc,genericBefore);
 await pool.query(readFileSync(resolve(base,'qr-scanner-challenge-read.sql.review-only'),'utf8'));
 if(recoverable)await pool.query(readFileSync(resolve(base,'qr-scanner-registration-receipt.sql.review-only'),'utf8'));
 phase='unknown-challenge-commit';
 const unknownKeys=generateKeyPairSync('ed25519'),unknownTarget={companyId:id(1),deviceId:id(70),keyHex:unknownKeys.publicKey.export({type:'spki',format:'der'}).toString('hex')};
 const uncertainPool={connect:async()=>{const c=await pool.connect();return {query:async(s,v)=>{const r=await c.query(s,v);if(s==='commit')throw Error('synthetic lost commit response');return r;},release:x=>c.release(x)};}};
 const uncertain=createScannerRegistrationChallengeAdapter({pool:uncertainPool,initializeVerifiedSession:fixtureSession});
 await assert.rejects(uncertain.issue(unknownTarget));await assert.rejects(uncertain.issue(unknownTarget));
 const recovered=await createScannerRegistrationChallengeAdapter({pool,initializeVerifiedSession:fixtureSession}).read(unknownTarget);
 assert.ok(recovered);assert.equal(recovered.device,id(70));
 const recoveredAgain=await createScannerRegistrationChallengeAdapter({pool,initializeVerifiedSession:fixtureSession}).read(unknownTarget);
 assert.equal(recoveredAgain.id,recovered.id);assert.equal(recoveredAgain.nonce,recovered.nonce);assert.equal(recoveredAgain.expiresMs,recovered.expiresMs);
 assert.equal((await pool.query('select count(*)::int n from qr_attendance_private.scanner_key_challenges where device_id=$1',[id(70)])).rows[0].n,1);
 const stranger=createScannerRegistrationChallengeAdapter({pool,initializeVerifiedSession:async c=>{await fixtureSession(c);await c.query("select set_config('fixture.session',$1,true)",[id(90)]);return {actor:id(5),session:id(90)};}});
 await assert.rejects(stranger.read(unknownTarget));
 assert.equal(await createScannerRegistrationChallengeAdapter({pool,initializeVerifiedSession:fixtureSession}).read({...unknownTarget,deviceId:id(71)}),null);
 await pool.query("update qr_attendance_private.scanner_key_challenges set created_ms=created_ms-100000,expires_ms=expires_ms-100000 where id=$1",[recovered.id]);
 assert.equal(await createScannerRegistrationChallengeAdapter({pool,initializeVerifiedSession:fixtureSession}).read(unknownTarget),null);
 assert.equal((await pool.query('select count(*)::int n from qr_attendance_private.scanner_key_challenges where device_id=$1',[id(70)])).rows[0].n,1);
 phase='wrong-password';const a=await challenge(id(40));
 const issuance=challengeId=>createScannerProofIssuanceReader({pool,initializeVerifiedSession:fixtureSession}).read({challengeId});
 assert.deepEqual(await issuance(a.challengeId),{status:'not_found'});await wrong(a.challengeId);
 assert.deepEqual(await issuance(a.challengeId),{status:'not_found'});
 assert.equal((await pool.query('select failed_attempts from public.user_secondary_credentials')).rows[0].failed_attempts,1);assert.equal(await proofCount(),0);
 for(let i=0;i<4;i++)await wrong(a.challengeId);
 await assert.rejects(issuer().issue({challengeId:a.challengeId,password:'synthetic-correct'}));
 assert.equal((await pool.query('select failed_attempts,locked_until>clock_timestamp() as locked from public.user_secondary_credentials')).rows[0].failed_attempts,5);
 await pool.query("update public.user_secondary_credentials set locked_until=clock_timestamp()-interval '1 second'");
 phase='proof-issuance-receipt-rollback';
 await pool.query('create trigger reject_test_issuance before insert on qr_attendance_private.scanner_proof_issuance_receipts for each row execute function private.registration_test_reject_audit()');
 await assert.rejects(issuer().issue({challengeId:a.challengeId,password:'synthetic-correct'}));
 assert.equal(await proofCount(),0);assert.deepEqual(await issuance(a.challengeId),{status:'not_found'});
 await pool.query('drop trigger reject_test_issuance on qr_attendance_private.scanner_proof_issuance_receipts');
 phase='registration';const p=await issuer().issue({challengeId:a.challengeId,password:'synthetic-correct'});assert.equal(p.accepted,true);assert.equal(await proofCount(),1);
 assert.deepEqual(await issuance(a.challengeId),{status:'committed_unrecoverable'});
 for(const query of ['update qr_attendance_private.scanner_proof_issuance_receipts set challenge_id=challenge_id','delete from qr_attendance_private.scanner_proof_issuance_receipts','truncate qr_attendance_private.scanner_proof_issuance_receipts'])await assert.rejects(pool.query(query),e=>e.code==='42501');
 assert.equal((await pool.query("select has_table_privilege('authenticated','qr_attendance_private.scanner_proof_issuance_receipts','select') or has_function_privilege('service_role','qr_attendance_private.read_own_registration_proof_issuance(uuid)','execute') exposed")).rows[0].exposed,false);

 await assert.rejects(registration.complete({...a,signature:Buffer.alloc(64),reauthenticationProof:p.proof}));
 assert.equal((await pool.query('select consumed_at is null as unused from private.reauthentication_proofs')).rows[0].unused,true);
 assert.deepEqual(await registration.complete({...a,reauthenticationProof:p.proof}),{deviceId:id(40)});
 await assert.rejects(registration.complete({...a,reauthenticationProof:p.proof}));
 phase='rollback';const b=await challenge(id(41)),p2=await issuer().issue({challengeId:b.challengeId,password:'synthetic-correct'});
 await pool.query('create trigger reject_test_audit before insert on qr_attendance_private.scanner_registration_events for each row execute function private.registration_test_reject_audit()');
 await assert.rejects(registration.complete({...b,reauthenticationProof:p2.proof}));
 assert.equal((await pool.query('select count(*)::int n from qr_attendance_private.registered_scanners where device_id=$1',[id(41)])).rows[0].n,0);
 assert.equal((await pool.query('select consumed_at is null as unused from qr_attendance_private.scanner_key_challenges where id=$1',[b.challengeId])).rows[0].unused,true);
 await pool.query('drop trigger reject_test_audit on qr_attendance_private.scanner_registration_events');
 assert.deepEqual(await registration.complete({...b,reauthenticationProof:p2.proof}),{deviceId:id(41)});
 phase='credential-rotation';const c=await challenge(id(42)),p3=await issuer().issue({challengeId:c.challengeId,password:'synthetic-correct'});
 await pool.query("update public.user_secondary_credentials set password_hash=extensions.crypt('synthetic-correct',extensions.gen_salt('bf',4))");
 await assert.rejects(registration.complete({...c,reauthenticationProof:p3.proof}));
 assert.equal((await pool.query('select consumed_at is null as unused from qr_attendance_private.scanner_key_challenges where id=$1',[c.challengeId])).rows[0].unused,true);
 phase='proof-scope';const scoped=await challenge(id(44)),scopedProof=await issuer().issue({challengeId:scoped.challengeId,password:'synthetic-correct'});
 const attempt=await pool.connect();try{await attempt.query('begin');await fixtureSession(attempt);
  const key=(await attempt.query('select qr_attendance_private.load_scanner_key_challenge($1) as challenge',[scoped.challengeId])).rows[0].challenge.keyHex;
  await assert.rejects(attempt.query('select qr_attendance_private.register_own_scanner_with_proof($1,$2,$3,$4)',[id(1),id(45),key,scopedProof.proof]));
  await attempt.query('rollback');
 }finally{attempt.release();}
 await pool.query('insert into auth.sessions values($1,$2)',[id(90),id(5)]);
 const outsider=createScannerRegistrationProofIssuer({pool,initializeVerifiedSession:async x=>{
  await fixtureSession(x);await x.query("select set_config('fixture.session',$1,true)",[id(90)]);return {actor:id(5),session:id(90)};}});
 const countBefore=await proofCount();await assert.rejects(outsider.issue({challengeId:scoped.challengeId,password:'synthetic-correct'}));assert.equal(await proofCount(),countBefore);
 await pool.query("update private.reauthentication_proofs set issued_at=clock_timestamp()-interval '100 seconds',expires_at=clock_timestamp()-interval '99 seconds' where proof_hash=encode(extensions.digest($1,'sha256'),'hex')",[scopedProof.proof]);
 await assert.rejects(registration.complete({...scoped,reauthenticationProof:scopedProof.proof}));
 assert.equal((await pool.query('select count(*)::int n from qr_attendance_private.registered_scanners where device_id in($1,$2)',[id(44),id(45)])).rows[0].n,0);
 assert.equal((await pool.query("select has_function_privilege('authenticated','qr_attendance_private.issue_registration_proof(uuid,text,text)','execute') or has_function_privilege('service_role','qr_attendance_private.consume_registration_proof(uuid,uuid,text,text)','execute') as exposed")).rows[0].exposed,false);
 assert.equal((await pool.query("select has_function_privilege('authenticated','qr_attendance_private.read_own_scanner_key_challenge(uuid,uuid,text)','execute') as exposed")).rows[0].exposed,false);
 if(!process.argv[2]){phase='concurrent';const d=await challenge(id(43)),p4=await issuer().issue({challengeId:d.challengeId,password:'synthetic-correct'});
  const outcomes=await Promise.allSettled([registration.complete({...d,reauthenticationProof:p4.proof}),registration.complete({...d,reauthenticationProof:p4.proof})]);
  assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
  assert.equal((await pool.query('select count(*)::int n from qr_attendance_private.scanner_registration_events where device_id=$1',[id(43)])).rows[0].n,1);
 }
 if(recoverable){
  phase='registration-lost-commit';
  const lost=await challenge(id(80)),issued=await issuer().issue({challengeId:lost.challengeId,password:'synthetic-correct'});
  const key=(await pool.query('select public_key_hex from qr_attendance_private.scanner_key_challenges where id=$1',[lost.challengeId])).rows[0].public_key_hex;
  const target={challengeId:lost.challengeId,companyId:id(1),deviceId:id(80),keyHex:key};
  const counts=async()=>(await pool.query('select (select count(*)::int from qr_attendance_private.scanner_registration_events) events,(select count(*)::int from qr_attendance_private.scanner_registration_receipts) receipts')).rows[0];
  const before=await counts();
  const unknownPool={connect:async()=>{const c=await pool.connect();return {query:async(s,v)=>{const result=await c.query(s,v);if(s==='commit')throw Error('synthetic lost COMMIT response');return result;},release:discard=>c.release(discard)};}};
  const unknown=createRecoverableScannerRegistrationAdapter({enabled:true,pool:unknownPool,initializeVerifiedSession:fixtureSession});
  const command={...lost,reauthenticationProof:issued.proof};
  await assert.rejects(unknown.complete(command));await assert.rejects(unknown.complete(command));await assert.rejects(unknown.read(target));
  const read=()=>createRecoverableScannerRegistrationAdapter({enabled:true,pool,initializeVerifiedSession:fixtureSession}).read(target);
  const receipt=await read();assert.equal(receipt.challengeId,lost.challengeId);assert.equal(receipt.deviceId,id(80));
  assert.deepEqual(await read(),receipt);
  assert.deepEqual(await counts(),{events:before.events+1,receipts:before.receipts+1});
  await assert.rejects(registration.complete(command));
  await pool.query('update qr_attendance_private.scanner_key_challenges set created_ms=created_ms-100000,expires_ms=expires_ms-100000 where id=$1',[lost.challengeId]);
  assert.deepEqual(await read(),receipt); // original expiry never extends
  await pool.query('update qr_attendance_private.registered_scanners set revoked_at=clock_timestamp() where device_id=$1',[id(80)]);
  await assert.rejects(read());await pool.query('update qr_attendance_private.registered_scanners set revoked_at=null where device_id=$1',[id(80)]);
  await pool.query("update qr_attendance_private.registered_scanners set public_key_der=decode('302a300506032b6570032100'||repeat('cd',32),'hex') where device_id=$1",[id(80)]);
  await assert.rejects(read());await pool.query('update qr_attendance_private.registered_scanners set public_key_der=decode($1,\'hex\') where device_id=$2',[key,id(80)]);
  const otherSession=createRecoverableScannerRegistrationAdapter({enabled:true,pool,initializeVerifiedSession:async c=>{
   await fixtureSession(c);await c.query("select set_config('fixture.session',$1,true)",[id(90)]);return {actor:id(5),session:id(90)};
  }});
  assert.equal(await otherSession.read(target),null);
  phase='receipt-original-retention';
  await assert.rejects(pool.query('update qr_attendance_private.scanner_registration_receipts set session_id=$1 where challenge_id=$2',[id(90),lost.challengeId]));
  await assert.rejects(pool.query('delete from qr_attendance_private.scanner_registration_receipts where challenge_id=$1',[lost.challengeId]));
  await assert.rejects(pool.query('truncate qr_attendance_private.scanner_registration_receipts'),e=>e.code==='42501');
  await assert.rejects(pool.query('delete from qr_attendance_private.scanner_registration_events where id=$1',[receipt.registrationEventId]));
  await assert.rejects(pool.query('delete from qr_attendance_private.scanner_key_challenges where id=$1',[lost.challengeId]));
  // Old unreceipted candidate rows retain their prior deletion behavior.
  const old=await challenge(id(81));await pool.query('delete from qr_attendance_private.scanner_key_challenges where id=$1',[old.challengeId]);
  assert.equal((await pool.query('select count(*)::int n from qr_attendance_private.scanner_key_challenges where id=$1',[old.challengeId])).rows[0].n,0);
  const legacy=await challenge(id(83)),legacyProof=await issuer().issue({challengeId:legacy.challengeId,password:'synthetic-correct'});
  await createScannerRegistrationPossessionAdapter({pool,initializeVerifiedSession:fixtureSession}).complete({...legacy,reauthenticationProof:legacyProof.proof});
  assert.equal((await pool.query('select count(*)::int n from qr_attendance_private.scanner_registration_receipts where challenge_id=$1',[legacy.challengeId])).rows[0].n,0);
  await pool.query('delete from qr_attendance_private.scanner_registration_events where device_id=$1',[id(83)]);
  await pool.query('delete from qr_attendance_private.registered_scanners where device_id=$1',[id(83)]);
  await pool.query('delete from qr_attendance_private.scanner_key_challenges where id=$1',[legacy.challengeId]);
  assert.equal((await pool.query("select has_table_privilege('authenticated','qr_attendance_private.scanner_registration_receipts','select') or has_function_privilege('service_role','qr_attendance_private.read_own_scanner_key_registration(uuid,uuid,uuid,text)','execute') as exposed")).rows[0].exposed,false);
  assert.deepEqual(await read(),receipt);
  phase='receipt-late-failure-rollback';
  const late=await challenge(id(82)),lateProof=await issuer().issue({challengeId:late.challengeId,password:'synthetic-correct'});
  const stable=await counts();
  await pool.query('create trigger reject_test_receipt before insert on qr_attendance_private.scanner_registration_receipts for each row execute function private.registration_test_reject_audit()');
  await assert.rejects(registration.complete({...late,reauthenticationProof:lateProof.proof}));
  assert.deepEqual(await counts(),stable);
  assert.equal((await pool.query('select count(*)::int n from qr_attendance_private.registered_scanners where device_id=$1',[id(82)])).rows[0].n,0);
  assert.equal((await pool.query('select consumed_at is null unused from qr_attendance_private.scanner_key_challenges where id=$1',[late.challengeId])).rows[0].unused,true);
  assert.equal((await pool.query("select consumed_at is null unused from private.reauthentication_proofs where proof_hash=encode(extensions.digest($1,'sha256'),'hex')",[lateProof.proof])).rows[0].unused,true);
  await pool.query('drop trigger reject_test_receipt on qr_attendance_private.scanner_registration_receipts');
  assert.deepEqual(await registration.complete({...late,reauthenticationProof:lateProof.proof}),{deviceId:id(82)});
  console.log('QR lost registration COMMIT -> exact private receipt recovery; one event/receipt, expiry/replay/revocation/SID/retention/ACL passed');
 }
 console.log('QR exact-target second-password proof -> key possession -> registration: counters, lockout, credential rotation, rollback, replay, ACL passed');
 console.log('LIMIT synthetic Auth/session/permissions/rollout; no public route, real JWT boundary, device custody or attendance writer');
}catch(error){console.error('QR proof integration failed phase='+phase+' code='+(typeof error?.code==='string'?error.code:'ASSERTION'));process.exitCode=1;}finally{tearingDown=true;if(pool)await pool.end();if(created)await admin.query(`drop database ${database} with (force)`);if(admin)await admin.end();}

