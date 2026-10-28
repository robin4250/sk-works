// Offline candidate only. Produces a pending proposal, never a trusted key.
// The device snapshot must be loaded by a future authenticated, locked adapter.
import {createPublicKey,createHash} from 'node:crypto';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export function pendingDeviceKeyMigration({actor,device,publicKeyPem}) {
  if (!uuid.test(actor) || !device || !uuid.test(device.id) ||
      device.master_user_id!==actor || device.is_locked!==false || device.revoked_at!==null ||
      typeof publicKeyPem!=='string' || publicKeyPem.length>1024 ||
      !publicKeyPem.startsWith('-----BEGIN PUBLIC KEY-----\n')) throw new Error('migration proposal invalid');
  const key=createPublicKey(publicKeyPem);
  if(key.asymmetricKeyType!=='ec'||key.asymmetricKeyDetails?.namedCurve!=='prime256v1') throw new Error('P-256 public key required');
  const canonical=key.export({format:'pem',type:'spki'}).toString();
  // Reject trailing data or alternative text encodings, keeping existing intent
  // hash semantics (SHA256 of canonical PEM) explicit and unambiguous.
  if(canonical!==publicKeyPem) throw new Error('canonical public key required');
  return Object.freeze({actor,device_id:device.id,public_key_pem:canonical,
    key_sha256:createHash('sha256').update(canonical).digest('hex'),status:'pending'});
}
