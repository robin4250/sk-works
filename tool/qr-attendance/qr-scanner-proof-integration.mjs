// Disposable-only proof issuer -> existing PoP registration composition.
// Auth/session/permission/rollout are synthetic; the password verifier, proof
// ledger, issuer/consumer and scanner registration/PoP SQL are actual candidates.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {generateKeyPairSync,randomBytes,sign} from 'node:crypto';
import {scannerRegistrationSigningBytes,createScannerRegistrationPossessionAdapter} from './qr-scanner-possession.mjs';
import {createScannerRegistrationProofIssuer} from './qr-scanner-proof-issuer.mjs';
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
const registration=createScannerRegistrationPossessionAdapter({pool,initializeVerifiedSession:fixtureSession});
async function challenge(device){const keys=generateKeyPairSync('ed25519'),keyHex=keys.publicKey.export({type:'spki',format:'der'}).toString('hex');
 const c=await pool.connect();try{await c.query('begin');await fixtureSession(c);
  const cid=(await c.query('select qr_attendance_private.issue_scanner_key_challenge($1,$2,$3) as id',[id(1),device,keyHex])).rows[0].id;
  const value=(await c.query('select qr_attendance_private.load_scanner_key_challenge($1) as challenge',[cid])).rows[0].challenge;
  await c.query('commit');return {challengeId:cid,signature:sign(null,scannerRegistrationSigningBytes(value),keys.privateKey)};
 }catch(e){await c.query('rollback');throw e;}finally{c.release();}}
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
 phase='wrong-password';const a=await challenge(id(40));await wrong(a.challengeId);
 assert.equal((await pool.query('select failed_attempts from public.user_secondary_credentials')).rows[0].failed_attempts,1);assert.equal(await proofCount(),0);
 for(let i=0;i<4;i++)await wrong(a.challengeId);
 await assert.rejects(issuer().issue({challengeId:a.challengeId,password:'synthetic-correct'}));
 assert.equal((await pool.query('select failed_attempts,locked_until>clock_timestamp() as locked from public.user_secondary_credentials')).rows[0].failed_attempts,5);
 await pool.query("update public.user_secondary_credentials set locked_until=clock_timestamp()-interval '1 second'");
 phase='registration';const p=await issuer().issue({challengeId:a.challengeId,password:'synthetic-correct'});assert.equal(p.accepted,true);assert.equal(await proofCount(),1);
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
 if(!process.argv[2]){phase='concurrent';const d=await challenge(id(43)),p4=await issuer().issue({challengeId:d.challengeId,password:'synthetic-correct'});
  const outcomes=await Promise.allSettled([registration.complete({...d,reauthenticationProof:p4.proof}),registration.complete({...d,reauthenticationProof:p4.proof})]);
  assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
  assert.equal((await pool.query('select count(*)::int n from qr_attendance_private.scanner_registration_events where device_id=$1',[id(43)])).rows[0].n,1);
 }
 console.log('QR exact-target second-password proof -> key possession -> registration: counters, lockout, credential rotation, rollback, replay, ACL passed');
 console.log('LIMIT synthetic Auth/session/permissions/rollout; no public route, real JWT boundary, device custody or attendance writer');
}catch(error){console.error('QR proof integration failed phase='+phase+' code='+(typeof error?.code==='string'?error.code:'ASSERTION'));process.exitCode=1;}finally{tearingDown=true;if(pool)await pool.end();if(created)await admin.query(`drop database ${database} with (force)`);if(admin)await admin.end();}
