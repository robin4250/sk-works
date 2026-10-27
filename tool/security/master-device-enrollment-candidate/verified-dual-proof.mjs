// Offline-only composition for an additional device. This is not an endpoint.
// A trusted adapter must read authoritative session/intent/device state and,
// under a database lock, revalidate the exact snapshots, live sessions, state,
// server time and both device keys before atomically claiming an approval.
// The return token has no implemented secure delivery channel.
import {createHash, randomBytes} from 'node:crypto';
import {verifyApprovalSignature} from './approval-signature.mjs';
import {verifyNewDeviceProof} from './new-device-proof.mjs';

export async function issueDualProofApproval({adapter,actor,session,intentId,deviceId,approvingSignature,newPublicKeyPem,newSignature,nowMs}) {
  if (!adapter || typeof adapter.loadTrustedContext !== 'function' || typeof adapter.claimVerifiedApproval !== 'function') throw new TypeError('trusted adapter required');
  const context=await adapter.loadTrustedContext({actor,session,intentId,deviceId});
  if (!context || context.sessionActive !== true || context.master !== true ||
      context.sessionActor !== actor || context.sessionId !== session ||
      context.intent?.id !== intentId || context.intent?.actor !== actor ||
      context.device?.id !== deviceId || context.device?.actor !== actor ||
      !verifyApprovalSignature({intent:context.intent,device:context.device,signature:approvingSignature,nowMs}) ||
      !verifyNewDeviceProof({intent:context.intent,approvingDevice:context.device,newPublicKeyPem,signature:newSignature,nowMs})) return null;
  const token=randomBytes(32).toString('hex');
  const tokenHash=createHash('sha256').update(token).digest('hex');
  const accepted=await adapter.claimVerifiedApproval({actor,session,intentId,deviceId,
    expectedIntent:context.intent,expectedDevice:context.device,expectedNewPublicKeyPem:newPublicKeyPem,tokenHash});
  return accepted === true ? token : null;
}
