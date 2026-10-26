// Offline protocol primitive, not an endpoint or an authentication service.
// Callers MUST obtain the intent and registered public key from trusted server
// storage, verify the approving device's live owner session and execute an
// atomic replay-protected claim. No private keys belong in this process.
import { createPublicKey, verify } from 'node:crypto';

const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const sha=/^[0-9a-f]{64}$/;
export function approvalPayload(intent,device) {
  if (!intent || !device || !uuid.test(intent.id) || !uuid.test(intent.actor) ||
      !uuid.test(intent.requesterSession) || !uuid.test(device.id) ||
      !sha.test(intent.deviceKeyHash) || !sha.test(intent.nonce) ||
      !Number.isSafeInteger(intent.createdMs) || !Number.isSafeInteger(intent.expiresMs)) {
    throw new Error('invalid master approval challenge');
  }
  return Buffer.from(JSON.stringify([
    'sko-master-device-approval-v1',intent.id,intent.actor,intent.requesterSession,
    intent.deviceKeyHash,intent.nonce,intent.createdMs,intent.expiresMs,device.id
  ]),'utf8');
}
export function verifyApprovalSignature({intent,device,signature,nowMs}) {
  try {
    if (!Number.isSafeInteger(nowMs) || !device.active || device.actor!==intent.actor ||
        intent.consumed || intent.expiresMs<=nowMs || intent.createdMs>nowMs ||
        intent.expiresMs-intent.createdMs>120000 || !Buffer.isBuffer(signature) ||
        signature.length<8 || signature.length>80) return false;
    const publicKey=createPublicKey(device.publicKeyPem);
    if (publicKey.asymmetricKeyType!=='ec' || publicKey.asymmetricKeyDetails?.namedCurve!=='prime256v1') return false;
    return verify('sha256',approvalPayload(intent,device),publicKey,signature);
  } catch (_) { return false; }
}
