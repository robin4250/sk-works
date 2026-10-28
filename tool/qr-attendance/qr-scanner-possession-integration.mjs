// Disposable-only real candidate SQL/crypto composition. Auth, permission and
// reauthentication proof authorities are synthetic; registration is not enabled.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {generateKeyPairSync,randomBytes,sign} from 'node:crypto';
import {scannerRegistrationSigningBytes,createScannerRegistrationPossessionAdapter} from './qr-scanner-possession.mjs';
const base=dirname(new URL(import.meta.url).pathname),id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const expand=p=>readFileSync(p,'utf8').split('\n').filter(x=>!x.startsWith('\\set')).map(x=>x.startsWith('\\ir ')?expand(resolve(dirname(p),x.slice(4))):x).join('\n');
const pglite=process.argv[2];let admin,pool,created=false,db,droppingOwnedFixture=false;
if(pglite){const {PGlite}=await import(resolve(pglite));db=new PGlite();
 const query=async(s,v)=>v?db.query(s,v):(await db.exec(s)).at(-1)||{rows:[]};pool={query,connect:async()=>({query,release(){}}),end:async()=>db.close()};
}else{
 if(process.env.CI!=='true'||process.env.PGHOST!=='127.0.0.1')throw Error('disposable loopback CI required');
 const pg=(await import(resolve('tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 admin=new pg.Client();await admin.connect();db='qr_register_'+randomBytes(8).toString('hex');await admin.query(`create database ${db}`);created=true;pool=new pg.Pool({database:db,max:4});
 pool.on('error',error=>{if(droppingOwnedFixture&&error?.code==='57P01')return;console.error('QR possession fixture pool failure');process.exitCode=1;});
}
const keys=generateKeyPairSync('ed25519'),keyHex=keys.publicKey.export({type:'spki',format:'der'}).toString('hex');
const fixtureSession=async c=>{await c.query("select set_config('fixture.actor',$1,true),set_config('fixture.session',$2,true),set_config('fixture.live','yes',true),set_config('fixture.manage','yes',true),set_config('fixture.qr','yes',true)",[id(5),id(6)]);return {actor:id(5),session:id(6)};};
const adapter=createScannerRegistrationPossessionAdapter({pool,initializeVerifiedSession:fixtureSession});
async function make(device,proof){
 const c=await pool.connect();try{await c.query('begin');await fixtureSession(c);
  const cid=(await c.query('select qr_attendance_private.issue_scanner_key_challenge($1,$2,$3) as id',[id(1),device,keyHex])).rows[0].id;
  assert.equal((await c.query('select qr_attendance_private.issue_scanner_key_challenge($1,$2,$3) as id',[id(1),device,keyHex])).rows[0].id,cid);
  const challenge=(await c.query('select qr_attendance_private.load_scanner_key_challenge($1) as challenge',[cid])).rows[0].challenge;
  await c.query("insert into private.registration_test_proofs(proof,actor,session_id,operation,target) values($1,$2,$3,'qr.scanner.register',jsonb_build_object('company_id',$4::uuid,'device_id',$5::uuid,'actor_id',$2::uuid,'public_key_hex',$6::text))",[proof,id(5),id(6),id(1),device,keyHex]);
  await c.query('commit');return {challengeId:cid,signature:sign(null,scannerRegistrationSigningBytes(challenge),keys.privateKey),reauthenticationProof:proof};
 }catch(e){await c.query('rollback');throw e;}finally{c.release();}}
try{
 await pool.query(expand(resolve(base,'qr-scanner-registration-test.sql')));
 await pool.query('drop trigger reject_test_audit on qr_attendance_private.scanner_registration_events');
 await pool.query(readFileSync(resolve(base,'qr-scanner-possession.sql.review-only'),'utf8'));
 const a=await make(id(30),'possession-30'),invalid={...a,signature:Buffer.alloc(64)};
 await assert.rejects(adapter.complete(invalid));
 await assert.rejects(adapter.complete({...a,reauthenticationProof:'missing-exact-proof'}));
 const outsider=await pool.connect();try{
  await outsider.query('begin');await fixtureSession(outsider);
  await outsider.query('insert into auth.sessions values($1,$2)',[id(9),id(5)]);
  await outsider.query("select set_config('fixture.session',$1,true)",[id(9)]);
  await assert.rejects(outsider.query('select qr_attendance_private.load_scanner_key_challenge($1)',[a.challengeId]));
  await outsider.query('rollback');
 }finally{outsider.release();}
 assert.equal((await pool.query("select consumed from private.registration_test_proofs where proof='possession-30'")).rows[0].consumed,false);
 assert.deepEqual(await adapter.complete(a),{deviceId:id(30)});await assert.rejects(adapter.complete(a));
 assert.equal((await pool.query('select consumed_at is not null as used from qr_attendance_private.scanner_key_challenges where id=$1',[a.challengeId])).rows[0].used,true);
 const b=await make(id(31),'possession-31');
 await pool.query('create trigger reject_test_audit before insert on qr_attendance_private.scanner_registration_events for each row execute function private.registration_test_reject_audit()');
 await assert.rejects(adapter.complete(b));
 assert.equal((await pool.query('select count(*)::int as n from qr_attendance_private.registered_scanners where device_id=$1',[id(31)])).rows[0].n,0);
 assert.equal((await pool.query("select consumed from private.registration_test_proofs where proof='possession-31'")).rows[0].consumed,false);
 assert.equal((await pool.query('select consumed_at is null as unused from qr_attendance_private.scanner_key_challenges where id=$1',[b.challengeId])).rows[0].unused,true);
 await pool.query('drop trigger reject_test_audit on qr_attendance_private.scanner_registration_events');
 assert.deepEqual(await adapter.complete(b),{deviceId:id(31)});
 const expired=await make(id(32),'possession-32');await pool.query('update qr_attendance_private.scanner_key_challenges set created_ms=created_ms-120000,expires_ms=expires_ms-120000 where id=$1',[expired.challengeId]);
 await assert.rejects(adapter.complete(expired));
 assert.equal((await pool.query("select has_table_privilege('authenticated','qr_attendance_private.scanner_key_challenges','select') or has_function_privilege('service_role','qr_attendance_private.consume_scanner_key_challenge(uuid)','execute') as exposed")).rows[0].exposed,false);
 if(!pglite){const concurrent=await make(id(33),'possession-33');const results=await Promise.allSettled([adapter.complete(concurrent),adapter.complete(concurrent)]);assert.equal(results.filter(x=>x.status==='fulfilled').length,1);
  assert.equal((await pool.query('select count(*)::int as n from qr_attendance_private.scanner_registration_events where device_id=$1',[id(33)])).rows[0].n,1);}
 console.log('scanner registration key possession, replay, rollback, expiry and ACL composition passed');
}finally{if(pool)await pool.end();if(created){droppingOwnedFixture=true;await admin.query(`drop database ${db} with (force)`);}if(admin)await admin.end();}
