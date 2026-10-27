// A host-owned, dedicated database pool is required. No credentials or SQL are
// accepted from HTTP callers. This adapter does not grant a database role access.
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const validId = value => typeof value === 'string' && uuid.test(value);
const unavailable = () => Error('inspection_unavailable');

export function createQualificationUploadDbAdapter({ pool }) {
  if (!pool || typeof pool.connect !== 'function') throw unavailable();

  async function transaction(query, values) {
    let client;
    try { client = await pool.connect(); }
    catch (_) { throw unavailable(); }
    let begun = false;
    let discard;
    try {
      await client.query('BEGIN');
      begun = true;
      await client.query("SET LOCAL statement_timeout = '5s'");
      await client.query("SET LOCAL lock_timeout = '3s'");
      const result = await client.query(query, values);
      if (result.rowCount !== 1 || !result.rows?.[0]) throw unavailable();
      await client.query('COMMIT');
      begun = false;
      return result.rows[0].value;
    } catch (_) {
      // COMMIT may have reached the server before a transport failure. The
      // immutable receipt is retryable; never report success on uncertainty.
      if (begun) {
        try { await client.query('ROLLBACK'); }
        catch (rollbackError) { discard = rollbackError; }
      } else {
        discard = unavailable();
      }
      throw unavailable();
    } finally {
      try { client.release(discard); }
      catch (_) { /* Do not expose connection details in an error response. */ }
    }
  }

  return Object.freeze({
    async authorizedPendingSlot({ actorId, sessionId, requestId, slotId }) {
      if (![actorId, sessionId, requestId, slotId].every(validId)) throw unavailable();
      const value = await transaction(
        'SELECT qualification_upload_candidate.inspection_slot($1::uuid,$2::uuid,$3::uuid,$4::uuid) AS value',
        [requestId, slotId, actorId, sessionId],
      );
      if (!value || typeof value !== 'object' || Array.isArray(value)) throw unavailable();
      return value;
    },
    async commitReceiptAtomically({ proof, expectedState }) {
      if (expectedState !== 'prepared' || !proof || typeof proof !== 'object' || Array.isArray(proof)) throw unavailable();
      // Take a detached value before the first await. Never send bearer tokens,
      // bytes or an arbitrary body object to the database.
      const fields = ['contract','companyId','workerId','qualificationMasterId','targetId','actorId','sessionId','requestId','slotId','bucket','path','objectId','objectVersion','mime','bytes','sha256'];
      if (Object.keys(proof).length !== fields.length || fields.some(key => !Object.hasOwn(proof, key))) throw unavailable();
      const copy = Object.fromEntries(fields.map(key => [key, proof[key]]));
      if (!['companyId','workerId','qualificationMasterId','targetId','actorId','sessionId','requestId','slotId','objectId'].every(key => validId(copy[key])) || copy.contract !== 'qualification_management_upload_v1' || copy.bucket !== 'qualification-certificates' || typeof copy.path !== 'string' || copy.path.length > 1024 || typeof copy.objectVersion !== 'string' || !copy.objectVersion || copy.objectVersion.length > 256 || !Number.isSafeInteger(copy.bytes) || copy.bytes < 8 || copy.bytes > 20971520 || typeof copy.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(copy.sha256) || !['image/jpeg','image/png','image/heic','application/pdf'].includes(copy.mime)) throw unavailable();
      const encoded = JSON.stringify(copy);
      return await transaction(
        'SELECT qualification_upload_candidate.record_receipt($1::uuid,$2::uuid,$3::uuid,$4::jsonb) AS value',
        [copy.requestId, copy.slotId, copy.actorId, encoded],
      ) === true;
    },
  });
}
