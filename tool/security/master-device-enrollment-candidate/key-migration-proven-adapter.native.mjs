// Native PostgreSQL, synthetic auth fixture. No real owner/key migration.
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {generateKeyPairSync,randomBytes,sign} from 'node:crypto';
import assert from 'node:assert/strict';
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
import {migrationPossessionPayload} from './key-migration-possession.mjs';
import {storeProvenPendingDeviceKey} from './key-migration-proven-adapter.mjs';
import {checkOwnerApprovalRequest} from './key-migration-owner-request-check.mjs';
const require=createRequire(process.cwd()+'/tool/security/fixture_dependencies/package.json');
const {Pool}=require('pg');
const pool=new Pool({max:4});
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const actor=id(1),session=id(2),deviceId=id(3);
const fixturePool={connect:async()=>{const c=await pool.connect();
 await c.query("select set_config('test.actor',$1,false),set_config('test.jwt',$2,false)",
 [actor,JSON.stringify({role:'authenticated',session_id:session,is_anonymous:false})]);return c;}};
const pendingCount=async()=>Number((await pool.query('select count(*) from master_device_enrollment_candidate.pending_key_migrations')).rows[0].count);
async function challenge({expired=false}={}){
 const pair=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),publicKeyPem=pair.publicKey.export({type:'spki',format:'pem'}).toString();
 const proposal=pendingDeviceKeyMigration({actor,device:{id:deviceId,master_user_id:actor,is_locked:false,revoked_at:null},publicKeyPem});
 const now=Number((await pool.query('select floor(extract(epoch from clock_timestamp())*1000)::float8 as now')).rows[0].now);
 const createdMs=expired?now-120000:now,expiresMs=expired?now-60000:now+120000;
 const row=(await pool.query(`insert into master_device_enrollment_candidate.key_possession_challenges
 (actor,session_id,device_id,key_sha256,nonce,created_ms,expires_ms)
 values ($1,$2,$3,$4,$5,$6,$7) returning id`,[actor,session,deviceId,proposal.key_sha256,randomBytes(32).toString('hex'),createdMs,expiresMs])).rows[0];
 const stored=(await pool.query(`select id,actor,session_id as session,device_id as "deviceId",
 key_sha256 as "keySha256",nonce,created_ms as "createdMs",expires_ms as "expiresMs",false as consumed
 from master_device_enrollment_candidate.key_possession_challenges where id=$1`,[row.id])).rows[0];
 return {pool:fixturePool,actor,session,deviceId,publicKeyPem,challengeId:row.id,
 signature:sign('sha256',migrationPossessionPayload(stored,proposal),pair.privateKey)};
}
const consumed=async id=>(await pool.query('select consumed_at is not null as consumed from master_device_enrollment_candidate.key_possession_challenges where id=$1',[id])).rows[0].consumed;
try{
 for(const name of ['native-setup.sql','native-real-functions.sql','key-migration-registry.sql.review-only','key-migration-challenges.sql.review-only','key-migration-owner-request.sql.review-only'])await pool.query(await readFile(new URL(name,import.meta.url),'utf8'));
 await pool.query(`insert into private.master_devices(id,master_user_id,device_key,device_name,device_type)
 values ($1,$2,'synthetic-legacy-id','Synthetic iPhone','iphone')`,[deviceId,actor]);
 const first=await challenge();const firstSaved=await storeProvenPendingDeviceKey(first);assert.equal(firstSaved.status,'pending');
 assert.equal(await consumed(first.challengeId),true);assert.equal(await pendingCount(),1);
 await assert.rejects(storeProvenPendingDeviceKey(first));assert.equal(await pendingCount(),1);
 await checkOwnerApprovalRequest({pool,args:first,pendingId:firstSaved.id,concurrency:true});
 const invalid=await challenge();const bad=Buffer.from(invalid.signature);bad[0]^=1;
 await assert.rejects(storeProvenPendingDeviceKey({...invalid,signature:bad}));
 assert.equal(await consumed(invalid.challengeId),false);assert.equal(await pendingCount(),1);
 const expired=await challenge({expired:true});await assert.rejects(storeProvenPendingDeviceKey(expired));
 assert.equal(await consumed(expired.challengeId),false);
 await assert.rejects(storeProvenPendingDeviceKey({...invalid,session:id(99)}));
 assert.equal(await consumed(invalid.challengeId),false);
 // A downstream failure must not consume the nonce. Explicit new invocation after
 // correcting the fixture may use the same previously unconsumed challenge.
 await pool.query(`create function master_device_enrollment_candidate.reject_fixture_insert() returns trigger
 language plpgsql as $$ begin raise exception 'synthetic downstream failure';end $$;
 create trigger reject_fixture before insert on master_device_enrollment_candidate.pending_key_migrations
 for each row execute function master_device_enrollment_candidate.reject_fixture_insert()`);
 await assert.rejects(storeProvenPendingDeviceKey(invalid));
 assert.equal(await consumed(invalid.challengeId),false);assert.equal(await pendingCount(),1);
 await pool.query('drop trigger reject_fixture on master_device_enrollment_candidate.pending_key_migrations');
 assert.equal((await storeProvenPendingDeviceKey(invalid)).status,'pending');
 assert.equal(await consumed(invalid.challengeId),true);assert.equal(await pendingCount(),2);
 // Separate PostgreSQL connections race for the same server-owned row. Exactly
 // one commits. The other reads consumed=true after its lock wait and rolls back.
 const racing=await challenge();const results=await Promise.allSettled([storeProvenPendingDeviceKey(racing),storeProvenPendingDeviceKey(racing)]);
 assert.equal(results.filter(x=>x.status==='fulfilled').length,1);assert.equal(results.filter(x=>x.status==='rejected').length,1);
 assert.equal(await consumed(racing.challengeId),true);assert.equal(await pendingCount(),3);
 for(const role of ['anon','authenticated']){
  const c=await pool.connect();try{await c.query('begin');await c.query('set local role '+role);
   await assert.rejects(c.query('select * from master_device_enrollment_candidate.key_possession_challenges'),e=>e.code==='42501');
  }finally{await c.query('rollback');c.release();}
 }
 assert.equal((await pool.query('select device_key from private.master_devices where id=$1',[deviceId])).rows[0].device_key,'synthetic-legacy-id');
 console.log('Native proof-to-pending: signature validation, replay/expiry/session rejection, atomic rollback, concurrent single consumption, client ACL, pending-only and unchanged legacy identifier passed. Synthetic auth only.');
}finally{await pool.end();}
