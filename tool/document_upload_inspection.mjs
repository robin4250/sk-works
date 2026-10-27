import { createHash } from 'node:crypto';
import { uploadEvidenceMatches } from './document_upload_evidence.mjs';

// Server-side adapter candidate. All adapters must use privileged, trusted
// credentials and enforce the actor/session scope server side. No caller may
// supply bytes, object metadata, or an inspection result.
export async function inspectPendingUpload({ actorId, requestId, db, storage, validateFile }) {
  // A header alone is not proof of a valid image or PDF. Until a trusted,
  // bounded parser is installed, inspection must remain unavailable.
  if (!db || !storage || typeof validateFile !== 'function' || typeof actorId !== 'string' || typeof requestId !== 'string') throw Error('inspection_unavailable');
  const pending = await db.getAuthorizedPendingInspection({ actorId, requestId });
  if (!pending || pending.status !== 'awaiting_inspection' || pending.actorId !== actorId || pending.requestId !== requestId) throw Error('inspection_unavailable');
  const object = await storage.readImmutableVersion({ bucket: pending.bucket, path: pending.path, version: pending.objectVersion, maxBytes: 20 * 1024 * 1024 });
  if (!object || !(object.bytes instanceof Uint8Array) || object.bytes.byteLength === 0 || object.bytes.byteLength > 20 * 1024 * 1024) throw Error('invalid_file');
  const b = object.bytes;
  const ascii = (start, end) => String.fromCharCode(...b.slice(start, end));
  const detected = ascii(0, 5) === '%PDF-' ? 'application/pdf'
    : b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff ? 'image/jpeg'
    : b.length >= 8 && [137,80,78,71,13,10,26,10].every((x,i) => b[i] === x) ? 'image/png'
    : b.length >= 12 && ascii(4,8) === 'ftyp' && ['heic','heix','hevc','hevx','mif1','msf1'].includes(ascii(8,12)) ? 'image/heic' : null;
  if (detected !== pending.mime || object.version !== pending.objectVersion) throw Error('invalid_file');
  const inspectedHash = createHash('sha256').update(b).digest('hex');
  if (await validateFile({ bytes: b, mime: detected }) !== true) throw Error('invalid_file');
  const sha256 = createHash('sha256').update(b).digest('hex');
  // Do not commit evidence for bytes changed by a parser or asynchronous adapter.
  if (sha256 !== inspectedHash) throw Error('invalid_file');
  const verified = { ...pending, status: 'inspected', sha256, bytes: b.byteLength };
  if (!uploadEvidenceMatches(verified, {...verified, objectVersion: object.version})) throw Error('invalid_file');
  // This transaction MUST lock and recheck live authorization, request state,
  // feature switch, immutable object identity and single-use status. A truthy
  // return is only valid after commit. Missing/untrusted adapters fail closed.
  const committed = await db.commitInspectionAtomically({ actorId, requestId, expectedState: 'awaiting_inspection', verified });
  if (committed !== true) throw Error('inspection_conflict');
  return { inspected: true };
}
