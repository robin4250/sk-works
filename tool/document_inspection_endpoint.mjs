import { inspectPendingUpload } from './document_upload_inspection.mjs';

// The platform must supply a trusted token verifier, transaction-bound DB
// adapter, immutable Storage reader and isolated parser. Never trust actor IDs
// or inspection results supplied in a request body.
export function createInspectionEndpoint({ verifySession, db, storage, validateFile }) {
  if (typeof verifySession !== 'function' || !db || !storage || typeof validateFile !== 'function') {
    throw Error('inspection_unavailable');
  }
  return async function inspect({ bearerToken, requestId }) {
    if (typeof bearerToken !== 'string' || !bearerToken ||
        typeof requestId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(requestId)) {
      throw Error('inspection_unavailable');
    }
    const session = await verifySession(bearerToken);
    if (!session || session.active !== true || session.anonymous !== false ||
        typeof session.actorId !== 'string' || !session.actorId) throw Error('inspection_unavailable');
    return inspectPendingUpload({ actorId: session.actorId, requestId, db, storage, validateFile });
  };
}
