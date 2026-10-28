// Review-only orchestration. No endpoint or database adapter is implemented.
// runLockedTransaction MUST hold the QR rollout/settings gate, session/device,
// source attendance and challenge locks until commit, and rollback ALL writes
// on any error. It must not retry callbacks with external side effects.
import {createPublicKey, verify} from 'node:crypto';
import {qrDeviceSigningBytes, qrTokenHash} from './qr-device-verification.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const denied = () => new Error('qr_scan_not_accepted');
const normalized = value => typeof value === 'string' && uuid.test(value) ? value.toLowerCase() : null;

export async function acceptQrScan({adapter, actor, session, challengeId, rawToken, signature}) {
  if (!adapter || typeof adapter.runLockedTransaction !== 'function') throw denied();
  actor = normalized(actor); session = normalized(session); challengeId = normalized(challengeId);
  if (!actor || !session || !challengeId || !Buffer.isBuffer(signature) || signature.length !== 64) throw denied();
  const tokenHash = qrTokenHash(rawToken);
  // Copy before awaiting trusted I/O; caller mutation cannot replace a signature.
  const signatureSnapshot = Buffer.from(signature);
  return adapter.runLockedTransaction(async tx => {
    for (const method of ['loadLockedScan', 'writeRegularAttendance', 'consumeWithReceipt']) {
      if (typeof tx?.[method] !== 'function') throw denied();
    }
    const state = await tx.loadLockedScan({actor, session, challengeId});
    const challenge = state?.challenge;
    if (!state || state.actor !== actor || state.session !== session ||
        state.sessionActive !== true || state.scannerAuthorized !== true ||
        state.deviceActive !== true || state.subjectActive !== true || state.qrEnabled !== true ||
        normalized(challenge?.challengeId) !== challengeId || challenge?.tokenHash !== tokenHash ||
        !Number.isSafeInteger(state.nowMs) || !Number.isSafeInteger(state.expiresMs) ||
        !Buffer.isBuffer(state.publicKeyDer) || state.publicKeyDer.length !== 44) throw denied();
    try {
      const key = createPublicKey({key: state.publicKeyDer, format:'der', type:'spki'});
      if (key.asymmetricKeyType !== 'ed25519' ||
          !verify(null, qrDeviceSigningBytes(challenge), key, signatureSnapshot)) throw denied();
    } catch { throw denied(); }
    // A retry can read its existing receipt after expiry, but still needs the
    // current live scanner/device/subject/gate authorization and exact signature.
    if (state.consumed === true) {
      if (normalized(state.receiptId) === null) throw denied();
      return {receiptId: state.receiptId, alreadyRecorded: true};
    }
    if (state.consumed !== false || state.receiptId != null || state.nowMs >= state.expiresMs) throw denied();
    // The adapter calls the existing normal attendance writer, with all locked
    // subject/site/source/time and photo/route/report constraints revalidated.
    // It must not fabricate an attendance row or invoke a remote write here.
    const receiptId = await tx.writeRegularAttendance({lockedState: state});
    if (!normalized(receiptId) || await tx.consumeWithReceipt({challengeId, receiptId}) !== true) throw denied();
    return {receiptId, alreadyRecorded: false};
  });
}
