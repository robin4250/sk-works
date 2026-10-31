import { createHash } from 'node:crypto';
import { inspectPendingUpload } from './document_upload_inspection.mjs';

const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value);
const fail = () => { throw Error('inspection_unavailable'); };

// Unregistered server composition, not an HTTP endpoint or Storage authority.
// Reuses the existing file-inspection adapter. Production still requires an
// actual live-session verifier, immutable reader and transaction-bound DB.
export function createAuthenticatedDocumentUploadInspection({ verifySession, db, storage, validateFile }) {
  if (typeof verifySession !== 'function' || typeof db?.authorizedPendingUpload !== 'function' ||
      typeof db?.commitInspectionAtomically !== 'function' ||
      typeof storage?.readImmutableVersion !== 'function' || typeof validateFile !== 'function') fail();
  return async ({ bearerToken, requestId, uploadId }) => {
    if (typeof bearerToken !== 'string' || !bearerToken || !uuid(requestId) || !uuid(uploadId)) fail();
    const verified = await verifySession(bearerToken);
    const session = verified && typeof verified === 'object' ? Object.freeze({ ...verified }) : null;
    if (!session || session.active !== true || session.anonymous !== false ||
        !uuid(session.actorId) || !uuid(session.sessionId)) fail();
    const scope = Object.freeze({ actorId: session.actorId, sessionId: session.sessionId, requestId, uploadId });
    const result = await db.authorizedPendingUpload(scope);
    const pending = result && typeof result === 'object' ? Object.freeze({ ...result }) : null;
    if (!pending || pending.contract !== 'worker_document_upload_v2' ||
        pending.status !== 'awaiting_inspection' || pending.actorId !== scope.actorId ||
        pending.sessionId !== scope.sessionId || pending.requestId !== requestId || pending.uploadId !== uploadId) fail();
    for (const key of ['companyId', 'workerId', 'requirementId', 'targetId', 'objectId']) if (!uuid(pending[key])) fail();
    const prefix = `${pending.companyId}/${pending.workerId}/${pending.requirementId}/${requestId}/`;
    if (pending.bucket !== 'worker-documents' || typeof pending.path !== 'string' ||
        pending.path.length > 1024 || !pending.path.startsWith(prefix) || pending.path.length === prefix.length ||
        pending.path.includes('..') || pending.path.includes('\\') || pending.path.includes('//') ||
        typeof pending.objectVersion !== 'string' || !pending.objectVersion || pending.objectVersion.length > 256 ||
        !Number.isSafeInteger(pending.declaredBytes) || pending.declaredBytes < 8 || pending.declaredBytes > 20971520 ||
        typeof pending.declaredSha256 !== 'string' || !/^[a-f0-9]{64}$/.test(pending.declaredSha256)) fail();
    await inspectPendingUpload({ actorId: scope.actorId, requestId, validateFile,
      db: {
        getAuthorizedPendingInspection: async () => pending,
        commitInspectionAtomically: async ({ verified: proof, expectedState }) => {
          // The adapter must recheck these exact identities, live authority,
          // target snapshot, OFF switch and object version under one DB lock.
          if (expectedState !== 'awaiting_inspection' || proof.sha256 !== pending.declaredSha256 ||
              proof.bytes !== pending.declaredBytes || proof.objectId !== pending.objectId ||
              proof.objectVersion !== pending.objectVersion) fail();
          return await db.commitInspectionAtomically({ scope, pending, proof });
        },
      },
      storage: {
        readImmutableVersion: async () => {
          const object = await storage.readImmutableVersion({ bucket: pending.bucket, path: pending.path,
            objectId: pending.objectId, version: pending.objectVersion,
            maxBytes: 20971520, expectedBytes: pending.declaredBytes });
          if (!object || object.objectId !== pending.objectId || object.version !== pending.objectVersion ||
              !(object.bytes instanceof Uint8Array) || object.bytes.length !== pending.declaredBytes ||
              createHash('sha256').update(object.bytes).digest('hex') !== pending.declaredSha256) fail();
          // Keep the inspector's local bytes independent of adapter buffer reuse.
          return { objectId: object.objectId, version: object.version, bytes: Uint8Array.from(object.bytes) };
        },
      },
    });
    return Object.freeze({ inspected: true, requestId, uploadId });
  };
}
