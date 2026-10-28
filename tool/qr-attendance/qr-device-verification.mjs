// Cryptographic building block only: not an authentication endpoint. Callers
// must load all expected fields from locked server-side records and atomically
// consume the challenge with the attendance write. Never trust client keys.
import { createHash, createPublicKey, verify } from 'node:crypto';

const utf8 = new TextEncoder();
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const hex = /^[0-9a-f]{64}$/;

export function qrDeviceSigningBytes({companyId, deviceId, challengeId, tokenHash, action, sourceClockInId}) {
  if (![companyId, deviceId, challengeId].every(x => typeof x === 'string' && uuid.test(x)) ||
      typeof tokenHash !== 'string' || !hex.test(tokenHash) ||
      !['clock_in', 'clock_out'].includes(action) ||
      (action === 'clock_in' && sourceClockInId !== null) ||
      (action === 'clock_out' && (typeof sourceClockInId !== 'string' || !uuid.test(sourceClockInId)))) {
    throw new TypeError('invalid_qr_device_challenge');
  }
  // A JSON array avoids ambiguous concatenation. All fields have bounded,
  // validated alphabet; domain separates QR approval from other signatures.
  return utf8.encode(JSON.stringify(['sko.qr.attendance.scan.v1', companyId.toLowerCase(),
    deviceId.toLowerCase(), challengeId.toLowerCase(), tokenHash, action,
    sourceClockInId?.toLowerCase() ?? null]));
}

export function qrTokenHash(raw) {
  if (typeof raw !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(raw)) {
    throw new TypeError('invalid_qr_token');
  }
  return createHash('sha256').update(raw, 'ascii').digest('hex');
}

export function verifyQrDeviceChallenge({publicKeyDer, signature, challenge, enabled,
    deviceActive, authorized, expiresAt, now, consumed}) {
  if (enabled !== true || deviceActive !== true || authorized !== true || consumed !== false ||
      !Number.isSafeInteger(expiresAt) || !Number.isSafeInteger(now) || now >= expiresAt ||
      !Buffer.isBuffer(publicKeyDer) || publicKeyDer.length !== 44 ||
      !Buffer.isBuffer(signature) || signature.length !== 64) return false;
  try {
    const key = createPublicKey({key: publicKeyDer, format: 'der', type: 'spki'});
    if (key.asymmetricKeyType !== 'ed25519') return false;
    return verify(null, qrDeviceSigningBytes(challenge), key, signature);
  } catch (_) { return false; }
}
