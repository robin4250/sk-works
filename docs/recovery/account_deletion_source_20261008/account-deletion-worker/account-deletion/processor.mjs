// Server-side orchestration only. No public HTTP entry point is provided.
// Persistent adapters must acquire/renew a lease and enforce job ownership.
// Each erasure adapter must accept an idempotency key: it may be called again
// after an external operation succeeds but checkpoint persistence fails.
export const deletionSteps = Object.freeze([
  'restrictAccess',
  'preserveRequiredRecords',
  'revokeExternalIdentity',
  'erasePersonalContent',
  'erasePersonalFiles',
  'eraseAuthAccount',
  'verifyErasure',
  'notifyCompletion',
]);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function validJob(job, id) {
  return job?.id === id && uuid.test(job.userId ?? '') &&
    typeof job.policyVersion === 'string' && job.policyVersion.length > 0 &&
    /^[a-f0-9]{64}$/.test(job.reviewedPlanDigest ?? '') &&
    Array.isArray(job.completedSteps) &&
    job.completedSteps.every((s,i) => s === deletionSteps[i]) &&
    job.completedSteps.length <= deletionSteps.length;
}

export async function processDeletion(id, ports) {
  if (!uuid.test(id)) throw Error('invalid_job');
  for (const name of ['claim','checkEligibility','renew','checkpoint','complete','fail',...deletionSteps]) {
    if (typeof ports[name] !== 'function') throw Error('incomplete_processor');
  }
  const job = await ports.claim(id);
  if (!job) return {status:'busy_or_unavailable'};
  let current = 'eligibility';
  try {
    if (!validJob(job,id)) throw Error('invalid_plan');
    // Check before EVERY attempt, even when some steps are already complete.
    // The adapter must recognize prior transfer/account removal on retries.
    if (await ports.checkEligibility(job) !== true) throw Error('not_ready');
    for (const step of deletionSteps.slice(job.completedSteps.length)) {
      current = step;
      if (await ports.renew(job) !== true) return {status:'lease_lost'};
      // No mutable user ID or deletion targets are taken from request bodies.
      const verified = await ports[step](job, `${id}:${step}`);
      if (verified !== true) throw Error('step_unconfirmed');
      if (await ports.checkpoint(job,step) !== true) return {status:'lease_lost'};
    }
    if (await ports.complete(job) !== true) return {status:'lease_lost'};
    return {status:'completed'};
  } catch (_) {
    // Do not persist provider responses, credentials or document contents.
    await ports.fail(job,current).catch(()=>{});
    return {status:'failed',step:current};
  }
}
