// Internal review-only REQUEST, never independent approval or key activation.
// A trusted request-scoped pool must install independently verified auth locally.
// The independent verifier, request delivery, owner decision and recovery do not
// exist here. A pending self-signature is explicitly not ownership approval.
import {randomUUID,randomBytes} from 'node:crypto';
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export async function requestIndependentOwnerApproval({pool,actor,session,deviceId,publicKeyPem,challengeId,pendingId}) {
 if(![actor,session,deviceId,challengeId,pendingId].every(x=>typeof x==='string'&&uuid.test(x))||!pool||typeof pool.connect!=='function')throw Error('invalid owner review request');
 const c=await pool.connect();
 try {
  await c.query('begin');
  await c.query("set local lock_timeout = '1s'");
  await c.query("set local statement_timeout = '5s'");
  const identity=await c.query(`select auth.uid() as actor,private.require_reauthentication_session() as session,
   public.is_current_user_master_admin() as master`);
  if(identity.rows.length!==1||identity.rows[0].actor!==actor||identity.rows[0].session!==session||identity.rows[0].master!==true)throw Error('eligible owner session required');
  const device=await c.query(`select id,master_user_id,is_locked,revoked_at from private.master_devices
   where id=$1 and master_user_id=$2 for share`,[deviceId,actor]);
  if(device.rows.length!==1)throw Error('eligible owned device required');
  const proposal=pendingDeviceKeyMigration({actor,device:device.rows[0],publicKeyPem});
  // Lock the original consumed proof and exact pending key before creating the
  // review request. Its expiry cannot be extended by a retry or an arbitrary key.
  const source=await c.query(`select ch.expires_ms from master_device_enrollment_candidate.key_possession_challenges ch
   join master_device_enrollment_candidate.pending_key_migrations p
    on p.id=$2 and p.actor=ch.actor and p.device_id=ch.device_id and p.key_sha256=ch.key_sha256
   where ch.id=$1 and ch.actor=auth.uid() and ch.actor=$3
    and ch.session_id=private.require_reauthentication_session() and ch.session_id=$4
    and ch.device_id=$5 and ch.key_sha256=$6 and p.public_key_pem=$7
    and ch.consumed_at is not null and p.status='pending'
    and ch.expires_ms>floor(extract(epoch from clock_timestamp())*1000)
    and public.is_current_user_master_admin() for update of ch,p`,
   [challengeId,pendingId,actor,session,deviceId,proposal.key_sha256,proposal.public_key_pem]);
  if(source.rows.length!==1)throw Error('fresh original pending proof required');
  await c.query(`insert into master_device_enrollment_candidate.owner_approval_requests
   (id,challenge_id,pending_id,actor,requester_session,device_id,key_sha256,review_nonce,expires_ms)
   select $1,$2,$3,auth.uid(),private.require_reauthentication_session(),$4,$5,$6,$7::float8
   where public.is_current_user_master_admin() and $7::float8>floor(extract(epoch from clock_timestamp())*1000)
   on conflict(challenge_id) do nothing`,[randomUUID(),challengeId,pendingId,deviceId,proposal.key_sha256,randomBytes(32).toString('hex'),source.rows[0].expires_ms]);
  const saved=await c.query(`select id,status,key_sha256 from master_device_enrollment_candidate.owner_approval_requests
   where challenge_id=$1 and pending_id=$2 and actor=auth.uid() and actor=$3
    and requester_session=private.require_reauthentication_session() and requester_session=$4
    and device_id=$5 and key_sha256=$6 and status='awaiting_independent_owner'
    and expires_ms=$7 and expires_ms>floor(extract(epoch from clock_timestamp())*1000)
    and public.is_current_user_master_admin() for share`,
   [challengeId,pendingId,actor,session,deviceId,proposal.key_sha256,source.rows[0].expires_ms]);
  if(saved.rows.length!==1||!uuid.test(saved.rows[0].id))throw Error('original owner review unavailable');
  await c.query('commit');
  return Object.freeze({id:saved.rows[0].id,status:'awaiting_independent_owner',keySha256:saved.rows[0].key_sha256});
 }catch(error){try{await c.query('rollback');}catch{}throw error;}
 finally{c.release();}
}
