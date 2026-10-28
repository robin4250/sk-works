// Review-only prerequisite for key migration. Not owner approval or key activation.
// The challenge, device snapshot and databaseNowMs MUST come from an authenticated,
// locked server transaction. A later adapter must consume the nonce atomically
// with the migration decision. This pure verifier cannot establish any of that.
import {verify} from 'node:crypto';
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const sha=/^[a-f0-9]{64}$/;
export function migrationPossessionPayload(challenge,proposal) {
 if(!challenge || !proposal || !uuid.test(challenge.id) || !uuid.test(challenge.actor) ||
    !uuid.test(challenge.session) || !uuid.test(challenge.deviceId) ||
    !sha.test(challenge.keySha256) || !sha.test(challenge.nonce) ||
    !Number.isSafeInteger(challenge.createdMs) || challenge.createdMs<0 ||
    !Number.isSafeInteger(challenge.expiresMs) ||
    challenge.expiresMs<=challenge.createdMs || challenge.expiresMs-challenge.createdMs>120000 ||
    challenge.actor!==proposal.actor || challenge.deviceId!==proposal.device_id ||
    challenge.keySha256!==proposal.key_sha256 || proposal.status!=='pending') throw Error('invalid migration proof challenge');
 return Buffer.from(JSON.stringify(['sko-master-key-migration-possession-v1',challenge.id,
  challenge.actor,challenge.session,challenge.deviceId,challenge.keySha256,challenge.nonce,
  challenge.createdMs,challenge.expiresMs]),'utf8');
}
export function verifyMigrationKeyPossession({challenge,actor,session,device,publicKeyPem,signature,databaseNowMs}) {
 try {
  if(!uuid.test(session) || challenge?.actor!==actor || challenge.session!==session ||
     challenge.consumed!==false || !Number.isSafeInteger(databaseNowMs) ||
     databaseNowMs<challenge.createdMs || databaseNowMs>=challenge.expiresMs ||
     !Buffer.isBuffer(signature) || signature.length<8 || signature.length>80) return null;
  const proposal=pendingDeviceKeyMigration({actor,device,publicKeyPem});
  if(!verify('sha256',migrationPossessionPayload(challenge,proposal),publicKeyPem,signature)) return null;
  // Remains pending. Possession of a newly generated key does not identify its
  // holder as the owner and must never activate or replace a registered key.
  return proposal;
 } catch { return null; }
}
