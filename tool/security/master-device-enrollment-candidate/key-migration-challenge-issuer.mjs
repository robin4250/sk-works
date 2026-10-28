// Internal review-only issuance, not a public endpoint or owner approval.
// pool must supply independently verified transaction-local authentication.
// Never log/deliver challenges outside the verified requesting owner session.
import {randomBytes,randomUUID} from 'node:crypto';
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
import {migrationPossessionPayload} from './key-migration-possession.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export async function issueMigrationKeyChallenge({pool,actor,session,deviceId,publicKeyPem}) {
 return issueChallenge({pool,actor,session,deviceId,publicKeyPem},false);
}
// Additional internal composition: second-password verification is not owner
// approval or a biometric assertion. No public endpoint is enabled by this.
export async function issuePasswordVerifiedMigrationKeyChallenge({pool,actor,session,deviceId,publicKeyPem,secondPassword}) {
 if(typeof secondPassword!=='string'||secondPassword.length>1024) throw Error('invalid password verification request');
 return issueChallenge({pool,actor,session,deviceId,publicKeyPem,secondPassword},true);
}
async function issueChallenge({pool,actor,session,deviceId,publicKeyPem,secondPassword},verifyPassword) {
 if(!uuid.test(actor)||!uuid.test(session)||!uuid.test(deviceId)||!pool||typeof pool.connect!=='function') throw Error('invalid challenge request');
 const client=await pool.connect();
 try {
  await client.query('begin');
  await client.query("set local lock_timeout = '1s'");
  await client.query("set local statement_timeout = '5s'");
  const identity=await client.query(`select auth.uid() as actor,
   private.require_reauthentication_session() as session,
   public.is_current_user_master_admin() as master`);
  const owner=identity.rows[0];
  if(identity.rows.length!==1||owner.actor!==actor||owner.session!==session||owner.master!==true) throw Error('eligible owner session required');
  if(verifyPassword) {
   const verification=await client.query('select public.verify_secondary_password($1) as verified',[secondPassword]);
   if(verification.rows.length!==1||typeof verification.rows[0].verified!=='boolean') throw Error('password verification unavailable');
   if(verification.rows[0].verified!==true) {
    // A wrong password must commit the existing verifier's failure counter.
    // Throwing/rolling back here would silently disable its lockout behavior.
    await client.query('commit');
    return Object.freeze({accepted:false});
   }
  }
  // Serialize issuance for the device, also excluding concurrent revoke/lock.
  const devices=await client.query(`select id,master_user_id,is_locked,revoked_at
   from private.master_devices where id=$1 and master_user_id=$2 for update`,[deviceId,actor]);
  if(devices.rows.length!==1) throw Error('eligible owned device required');
  const proposal=pendingDeviceKeyMigration({actor,device:devices.rows[0],publicKeyPem});
  // Do not replace a still-active challenge or implicitly retry unknown issuance.
  const active=await client.query(`select id from master_device_enrollment_candidate.key_possession_challenges
   where device_id=$1 and consumed_at is null
   and expires_ms>floor(extract(epoch from clock_timestamp())*1000) limit 1`,[deviceId]);
  if(active.rows.length!==0) throw Error('active challenge exists; wait for expiry');
  const created=await client.query(`with stamp as (
    select floor(extract(epoch from clock_timestamp())*1000)::float8 as ms)
   insert into master_device_enrollment_candidate.key_possession_challenges
   (id,actor,session_id,device_id,key_sha256,nonce,created_ms,expires_ms)
   select $1,auth.uid(),private.require_reauthentication_session(),$2,$3,$4,ms,ms+120000
   from stamp where public.is_current_user_master_admin()
   returning id,actor,session_id as session,device_id as "deviceId",key_sha256 as "keySha256",
   nonce,created_ms as "createdMs",expires_ms as "expiresMs",false as consumed`,
   [randomUUID(),deviceId,proposal.key_sha256,randomBytes(32).toString('hex')]);
  const challenge=created.rows[0];
  if(created.rows.length!==1||challenge.actor!==actor||challenge.session!==session) throw Error('challenge identity changed');
  // Validate the exact canonical signing contract before committing/delivery.
  migrationPossessionPayload(challenge,proposal);
  await client.query('commit');
  return verifyPassword?Object.freeze({accepted:true,challenge:Object.freeze(challenge)}):Object.freeze(challenge);
 } catch(error) {
  try {await client.query('rollback');} catch { /* issuance may be unknown */ }
  throw error;
 } finally {client.release();}
}
