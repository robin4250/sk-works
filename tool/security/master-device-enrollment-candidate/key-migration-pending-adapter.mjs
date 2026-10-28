// Internal review-only PostgreSQL adapter. No HTTP endpoint, grants or key activation.
// pool must be a trusted pool whose transaction already carries verified auth
// context; this adapter NEVER installs caller supplied JWT/settings or credentials.
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export async function storePendingDeviceKey({pool,actor,session,deviceId,publicKeyPem}) {
 if(!uuid.test(actor)||!uuid.test(session)||!uuid.test(deviceId)||!pool||typeof pool.connect!=='function') throw new Error('invalid pending request');
 const client=await pool.connect();
 try {
  await client.query('begin');
  const identity=await client.query(`select auth.uid() as actor,
   private.require_reauthentication_session() as session,
   public.is_current_user_master_admin() as master`);
  const row=identity.rows[0];
  if(identity.rows.length!==1||row.actor!==actor||row.session!==session||row.master!==true) throw new Error('eligible owner session required');
  const devices=await client.query(`select id,master_user_id,is_locked,revoked_at
   from private.master_devices where id=$1 and master_user_id=$2 for share`,[deviceId,actor]);
  if(devices.rows.length!==1) throw new Error('eligible owned device required');
  const proposal=pendingDeviceKeyMigration({actor,device:devices.rows[0],publicKeyPem});
  // An identical retry reads its original proposal, never promotes or changes it.
  const saved=await client.query(`insert into master_device_enrollment_candidate.pending_key_migrations
   (actor,device_id,public_key_pem,key_sha256) values ($1,$2,$3,$4)
   on conflict (device_id,key_sha256) do nothing returning id,status`,
   [actor,deviceId,proposal.public_key_pem,proposal.key_sha256]);
  const result=saved.rows.length===1?saved:await client.query(`select id,status from master_device_enrollment_candidate.pending_key_migrations
   where actor=$1 and device_id=$2 and key_sha256=$3 and public_key_pem=$4`,[actor,deviceId,proposal.key_sha256,proposal.public_key_pem]);
  if(result.rows.length!==1||result.rows[0].status!=='pending'||!uuid.test(result.rows[0].id)) throw new Error('pending proposal mismatch');
  await client.query('commit');
  return Object.freeze({id:result.rows[0].id,status:'pending'});
 } catch(error) {
  try { await client.query('rollback'); } catch { /* original result stays unknown */ }
  throw error;
 } finally { client.release(); }
}
