// Offline composition candidate. This is not an HTTP handler or a deployed service.
// The adapter must obtain all facts from trusted storage and revalidate them
// under a lock when claiming the challenge. No client-provided role or key is trusted.
import { createHash, randomBytes } from 'node:crypto';
import { verifyApprovalSignature } from './approval-signature.mjs';

export async function issueVerifiedApproval({adapter, actor, session, intentId, deviceId, signature, nowMs}) {
  if (!adapter || typeof adapter.loadTrustedContext !== 'function' ||
      typeof adapter.claimVerifiedApproval !== 'function') throw new TypeError('trusted adapter required');
  const context = await adapter.loadTrustedContext({actor, session, intentId, deviceId});
  if (!context || context.sessionActive !== true || context.master !== true ||
      context.sessionActor !== actor || context.sessionId !== session ||
      context.intent?.id !== intentId || context.intent?.actor !== actor ||
      context.device?.id !== deviceId || context.device?.actor !== actor ||
      !verifyApprovalSignature({intent:context.intent, device:context.device, signature, nowMs})) return null;
  const token=randomBytes(32).toString('hex');
  const tokenHash=createHash('sha256').update(token).digest('hex');
  // This callback is required to atomically re-check actor, current session,
  // device, exact intent version, expiry and unused state before persisting.
  const accepted=await adapter.claimVerifiedApproval({actor,session,intentId,deviceId,
    expectedIntent:context.intent,expectedDevice:context.device,tokenHash});
  return accepted === true ? token : null;
}
