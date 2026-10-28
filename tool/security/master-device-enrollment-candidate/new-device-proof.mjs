// Isolated proof-of-possession primitive only. Not an enrollment endpoint.
// The verifier must read intent and time from trusted server state, bind the
// device-key representation exactly as stored and consume the challenge in
// the same transaction as enrollment. This primitive supplies none of those.
import {createHash, createPublicKey, verify} from 'node:crypto';
import {approvalPayload} from './approval-signature.mjs';

export function verifyNewDeviceProof({intent, approvingDevice, newPublicKeyPem, signature, nowMs}) {
  try {
    if (typeof newPublicKeyPem !== 'string' || Buffer.byteLength(newPublicKeyPem, 'utf8') > 4096 ||
        !Buffer.isBuffer(signature) || signature.length < 8 || signature.length > 80 ||
        !Number.isSafeInteger(nowMs) || intent.consumed !== false ||
        intent.createdMs > nowMs || intent.expiresMs <= nowMs ||
        intent.expiresMs - intent.createdMs > 120000) return false;
    const digest = createHash('sha256').update(newPublicKeyPem, 'utf8').digest('hex');
    if (digest !== intent.deviceKeyHash) return false;
    const key = createPublicKey(newPublicKeyPem);
    if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') return false;
    const payload = Buffer.concat([Buffer.from('sko-master-new-device-proof-v1\n'), approvalPayload(intent, approvingDevice)]);
    return verify('sha256', payload, key, signature);
  } catch (_) { return false; }
}
