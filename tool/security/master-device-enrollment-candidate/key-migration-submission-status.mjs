// Internal review-only reconciliation. This is pending status, not owner approval.
// Only an independently verified request pool may install transaction-local auth.
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export async function readOwnMigrationKeySubmission({pool,actor,session,deviceId,publicKeyPem,challengeId}) {
 if(!uuid.test(actor)||!uuid.test(session)||!uuid.test(deviceId)||!uuid.test(challengeId)||!pool||typeof pool.connect!=='function')throw Error('invalid migration status');
 const client=await pool.connect();
 try {
  await client.query('begin');
  await client.query("set local lock_timeout = '1s'");
  await client.query("set local statement_timeout = '5s'");
  const identity=await client.query(`select auth.uid() as actor,
   private.require_reauthentication_session() as session,
   public.is_current_user_master_admin() as master`);
  if(identity.rows.length!==1||identity.rows[0].actor!==actor||identity.rows[0].session!==session||identity.rows[0].master!==true)throw Error('eligible owner session required');
  const devices=await client.query(`select id,master_user_id,is_locked,revoked_at
   from private.master_devices where id=$1 and master_user_id=$2 for share`,[deviceId,actor]);
  if(devices.rows.length!==1)throw Error('eligible owned device required');
  const proposal=pendingDeviceKeyMigration({actor,device:devices.rows[0],publicKeyPem});
  // Expired-but-consumed challenges may be reconciled by their original live
  // session. No nonce, expiry or signature is returned and no write is attempted.
  const result=await client.query(`select p.id,p.status
   from master_device_enrollment_candidate.key_possession_challenges c
   join master_device_enrollment_candidate.pending_key_migrations p
    on p.actor=c.actor and p.device_id=c.device_id and p.key_sha256=c.key_sha256
   where c.id=$1 and c.actor=auth.uid() and c.actor=$2
    and c.session_id=private.require_reauthentication_session() and c.session_id=$3
    and c.device_id=$4 and c.key_sha256=$5 and c.consumed_at is not null
    and p.public_key_pem=$6 and p.status='pending'
    and public.is_current_user_master_admin() for share of c,p`,
   [challengeId,actor,session,deviceId,proposal.key_sha256,proposal.public_key_pem]);
  if(result.rows.length!==1||!uuid.test(result.rows[0].id)||result.rows[0].status!=='pending')throw Error('original migration submission unavailable');
  const live=await client.query(`select auth.uid() as actor,
   private.require_reauthentication_session() as session,
   public.is_current_user_master_admin() as master`);
  if(live.rows.length!==1||live.rows[0].actor!==actor||live.rows[0].session!==session||live.rows[0].master!==true)throw Error('live owner session required');
  await client.query('commit');
  return Object.freeze({id:result.rows[0].id,status:'pending'});
 } catch(error) {
  try {await client.query('rollback');}catch{}
  throw error;
 } finally {client.release();}
}
