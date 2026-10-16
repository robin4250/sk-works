import {collectPlatformWindow} from './platform_log_adapter.mjs';

// Isolated fixture orchestration only. No CLI, timer, environment/credential lookup,
// default network, logging, production hook or persistent queue. Callers must supply
// both fixture transports; importing this file performs no I/O. Real deployment,
// source attribution, notifications and continuous coverage remain unimplemented.
export async function deliverPlatformFixtureWindow(options) {
  try {
    if (!options || typeof options.fetchFixture !== 'function' ||
        typeof options.ingestFixture !== 'function') throw Error('Invalid fixture');
    const {projectRef, source, from, to, hmacKey, keyEpoch, managementToken,
      fetchFixture, ingestFixture} = options;
    // Reuse the existing projection and strict sanitizer. Never forward options,
    // upstream bodies, credentials or additional fields to the service RPC.
    const batch = await collectPlatformWindow({
      projectRef, source, from, to, hmacKey, keyEpoch, managementToken,
      fetchImpl: fetchFixture,
    });
    for (const event of batch.events) Object.freeze(event);
    Object.freeze(batch.events);
    Object.freeze(batch);
    const params = Object.freeze({p_batch: batch});
    // Exactly one attempt. A lost response is an uncertain outcome, not a reason
    // to blindly retry; an operator can explicitly repeat the same window using
    // the existing RPC's idempotency/conflict rules.
    const result = await ingestFixture('service_ingest_platform_monitor', params);
    if (!Number.isInteger(result) || result !== batch.events.length) {
      throw Error('Invalid receipt');
    }
    return Object.freeze({
      source: batch.source, window_from: batch.window_from,
      window_to: batch.window_to, key_epoch: batch.key_epoch,
      coverage: batch.coverage, event_count: result,
    });
  } catch {
    // Do not attach cause/upstream errors, token, key or batch to a thrown error.
    throw Error('Platform fixture delivery unavailable');
  }
}
