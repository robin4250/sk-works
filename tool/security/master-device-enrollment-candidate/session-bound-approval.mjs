// Offline candidate only: no authorization, endpoint or production adapter.
import { createPublicKey, verify } from 'node:crypto';
import { approvalPayload } from './approval-signature.mjs';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export function sessionBoundApprovalPayload(intent, device, approvingSession) {
  if (!uuid.test(approvingSession)) throw new Error('invalid approving session');
  return Buffer.from(JSON.stringify(['sko-master-device-approval-session-v2', approvingSession, approvalPayload(intent, device).toString('base64')]), 'utf8');
}
export function verifySessionBoundApproval({intent, device, approvingSession, sessionActor, sessionActive, signature, nowMs}) {
  try {
    if (sessionActive !== true || sessionActor !== intent.actor || !Number.isSafeInteger(nowMs) ||
        device.active !== true || device.actor !== intent.actor || intent.consumed !== false ||
        intent.expiresMs <= nowMs || intent.createdMs > nowMs || intent.expiresMs-intent.createdMs > 120000 ||
        !Buffer.isBuffer(signature) || signature.length < 8 || signature.length > 80) return false;
    const key = createPublicKey(device.publicKeyPem);
    if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') return false;
    return verify('sha256', sessionBoundApprovalPayload(intent, device, approvingSession), key, signature);
  } catch (_) { return false; }
}
