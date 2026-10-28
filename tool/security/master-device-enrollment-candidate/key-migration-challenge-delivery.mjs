// Internal review-only readback. Not a public endpoint or independent owner approval.
// Recover an uncertain issuance by reading its original challenge; never issue a
// replacement, extend its lifetime, consume it, or reveal another session's nonce.
// pool must install independently verified transaction-local auth, not request claims.
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
import {migrationPossessionPayload} from './key-migration-possession.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export async function readOwnMigrationKeyChallenge({pool,actor,session,deviceId,publicKeyPem}) {
 if(!uuid.test(actor)||!uuid.test(session)||!uuid.test(deviceId)||!pool||typeof pool.connect!=='function') throw Error('invalid challenge read');
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
  const devices=await client.query(`select id,master_user_id,is_locked,revoked_at
   from private.master_devices where id=$1 and master_user_id=$2 for share`,[deviceId,actor]);
  if(devices.rows.length!==1) throw Error('eligible owned device required');
  const proposal=pendingDeviceKeyMigration({actor,device:devices.rows[0],publicKeyPem});
  const found=await client.query(`select id,actor,session_id as session,device_id as "deviceId",
   key_sha256 as "keySha256",nonce,created_ms as "createdMs",expires_ms as "expiresMs",false as consumed
   from master_device_enrollment_candidate.key_possession_challenges
   where device_id=$1 and actor=auth.uid() and actor=$2
   and session_id=private.require_reauthentication_session() and session_id=$3
   and key_sha256=$4 and consumed_at is null
   and public.is_current_user_master_admin()
   and created_ms<=floor(extract(epoch from clock_timestamp())*1000)
   and expires_ms>floor(extract(epoch from clock_timestamp())*1000)
   for share`,[deviceId,actor,session,proposal.key_sha256]);
  if(found.rows.length!==1) throw Error('original live challenge unavailable');
  const challenge=found.rows[0];
  // Reject malformed server state before returning the original canonical fields.
  migrationPossessionPayload(challenge,proposal);
  await client.query('commit');
  return Object.freeze(challenge);
 } catch(error) {
  try {await client.query('rollback');} catch { /* no automatic retry */ }
  throw error;
 } finally {client.release();}
}
