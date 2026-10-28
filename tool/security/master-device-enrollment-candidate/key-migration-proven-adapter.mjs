// Internal review-only proof-to-pending adapter. No endpoint, grants or key activation.
// Trusted challenge issuance and independent owner approval remain unimplemented.
// pool must be a trusted pool whose transaction already carries verified auth
// context; this adapter NEVER installs caller supplied JWT/settings or credentials.
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
import {verifyMigrationKeyPossession} from './key-migration-possession.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export async function storeProvenPendingDeviceKey({pool,actor,session,deviceId,publicKeyPem,challengeId,signature}) {
 if(!uuid.test(actor)||!uuid.test(session)||!uuid.test(deviceId)||!uuid.test(challengeId)||!Buffer.isBuffer(signature)||signature.length<8||signature.length>80||!pool||typeof pool.connect!=='function') throw new Error('invalid pending request');
 const client=await pool.connect();
 try {
  await client.query('begin');
  // Availability bound only; contention must roll back, never retry a write.
  // LOCAL settings are discarded on commit/rollback before pool reuse.
  await client.query("set local lock_timeout = '1s'");
  await client.query("set local statement_timeout = '5s'");
  const identity=await client.query(`select auth.uid() as actor,
   private.require_reauthentication_session() as session,
   public.is_current_user_master_admin() as master`);
  const row=identity.rows[0];
  if(identity.rows.length!==1||row.actor!==actor||row.session!==session||row.master!==true) throw new Error('eligible owner session required');
  const devices=await client.query(`select id,master_user_id,is_locked,revoked_at
   from private.master_devices where id=$1 and master_user_id=$2 for share`,[deviceId,actor]);
  if(devices.rows.length!==1) throw new Error('eligible owned device required');
  const proposal=pendingDeviceKeyMigration({actor,device:devices.rows[0],publicKeyPem});
  // The challenge row is server-owned, locked and never supplied by the caller.
  const challenges=await client.query(`select id,actor,session_id as session,
   device_id as "deviceId",key_sha256 as "keySha256",nonce,
   created_ms as "createdMs",expires_ms as "expiresMs",consumed_at is not null as consumed,
   floor(extract(epoch from clock_timestamp())*1000)::float8 as "databaseNowMs"
   from master_device_enrollment_candidate.key_possession_challenges
   where id=$1 for update`,[challengeId]);
  if(challenges.rows.length!==1 || !verifyMigrationKeyPossession({challenge:challenges.rows[0],
   actor,session,device:devices.rows[0],publicKeyPem,signature,databaseNowMs:challenges.rows[0].databaseNowMs}))
   throw new Error('fresh migration key proof required');
  // An identical retry reads its original proposal, never promotes or changes it.
  const saved=await client.query(`insert into master_device_enrollment_candidate.pending_key_migrations
   (actor,device_id,public_key_pem,key_sha256) values ($1,$2,$3,$4)
   on conflict (device_id,key_sha256) do nothing returning id,status`,
   [actor,deviceId,proposal.public_key_pem,proposal.key_sha256]);
  const result=saved.rows.length===1?saved:await client.query(`select id,status from master_device_enrollment_candidate.pending_key_migrations
   where actor=$1 and device_id=$2 and key_sha256=$3 and public_key_pem=$4`,[actor,deviceId,proposal.key_sha256,proposal.public_key_pem]);
  if(result.rows.length!==1||result.rows[0].status!=='pending'||!uuid.test(result.rows[0].id)) throw new Error('pending proposal mismatch');
  // Recheck live identity and the expiry after lock waits and the insert. One
  // transaction either records the pending proposal AND consumes the nonce, or
  // rolls both back. It still grants no trust or active signing authority.
  const consumed=await client.query(`update master_device_enrollment_candidate.key_possession_challenges
   set consumed_at=clock_timestamp() where id=$1 and actor=auth.uid()
   and session_id=private.require_reauthentication_session()
   and public.is_current_user_master_admin() and consumed_at is null
   and expires_ms>floor(extract(epoch from clock_timestamp())*1000)
   returning id`,[challengeId]);
  if(consumed.rows.length!==1) throw new Error('migration key proof no longer valid');
  await client.query('commit');
  return Object.freeze({id:result.rows[0].id,status:'pending'});
 } catch(error) {
  try { await client.query('rollback'); } catch { /* original result stays unknown */ }
  throw error;
 } finally { client.release(); }
}
