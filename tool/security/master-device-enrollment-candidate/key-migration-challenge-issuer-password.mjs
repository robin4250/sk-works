// Isolated fixture assertions using the existing real password verifier.
// Synthetic credentials only; this is not an owner approval or public endpoint.
import assert from 'node:assert/strict';
import {issuePasswordVerifiedMigrationKeyChallenge} from './key-migration-challenge-issuer.mjs';
export async function checkPasswordBoundChallenge({pool,authenticatedPool,actor,session,publicKeyPem}) {
 const deviceId='00000000-0000-0000-0000-000000000008';
 await pool.query(`insert into private.master_devices(id,master_user_id,device_key,device_name,device_type)
 values ($1,$2,'synthetic-password-gated-device','Synthetic iPad','ipad')`,[deviceId,actor]);
 const args={pool:authenticatedPool,actor,session,deviceId,publicKeyPem};
 const count=async()=>Number((await pool.query('select count(*) from master_device_enrollment_candidate.key_possession_challenges where device_id=$1',[deviceId])).rows[0].count);
 const credential=async()=>(await pool.query('select failed_attempts,locked_until,password_hash from public.user_secondary_credentials where user_id=$1',[actor])).rows[0];
 const before=await credential();
 for(let attempt=1;attempt<=5;attempt++) {
  assert.deepEqual(await issuePasswordVerifiedMigrationKeyChallenge({...args,secondPassword:'synthetic-wrong'}),{accepted:false});
  assert.equal((await credential()).failed_attempts,attempt,'wrong-password counters must commit');
  assert.equal(await count(),0,'wrong password cannot issue a challenge');
 }
 assert.ok((await credential()).locked_until);
 await assert.rejects(issuePasswordVerifiedMigrationKeyChallenge({...args,secondPassword:'synthetic-correct'}));
 assert.equal((await credential()).failed_attempts,5);assert.equal(await count(),0);
 // Advance only this synthetic lock fixture; never modify actual credentials.
 await pool.query('update public.user_secondary_credentials set locked_until=clock_timestamp()-interval \'1 second\' where user_id=$1',[actor]);
 const accepted=await issuePasswordVerifiedMigrationKeyChallenge({...args,secondPassword:'synthetic-correct'});
 assert.equal(accepted.accepted,true);assert.equal(accepted.challenge.actor,actor);
 assert.equal(accepted.challenge.session,session);assert.equal(accepted.challenge.deviceId,deviceId);
 assert.equal(await count(),1);assert.equal((await credential()).failed_attempts,0);
 assert.equal((await credential()).password_hash,before.password_hash,'verification cannot replace the existing password');
 assert.equal((await pool.query('select device_key from private.master_devices where id=$1',[deviceId])).rows[0].device_key,'synthetic-password-gated-device');
}
