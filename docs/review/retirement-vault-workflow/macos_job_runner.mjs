import { setTimeout as sleep } from 'node:timers/promises';

// Single-job polling on the Mac. Supabase owns the durable lease. If the Mac
// stops or a call times out, a later claim can pick up the same job. Only the
// trusted publication transaction can mark it complete.
export async function runMacRetirementJobs({ claim, processJob, signal,
  retryDelay = 5000, onFailure = () => {} }) {
  if (!signal || !Number.isSafeInteger(retryDelay) || retryDelay < 1) {
    throw Error('retirement_runner_configuration');
  }
  while (!signal.aborted) {
    try {
      const job = await claim({ signal });
      if (job && !signal.aborted) await processJob(job, { signal });
    } catch {
      if (!signal.aborted) onFailure('retirement_job_retry');
    }
    if (signal.aborted) return;
    try {
      await sleep(retryDelay, undefined, { signal });
    } catch (error) {
      if (!signal.aborted) throw error;
    }
  }
}
