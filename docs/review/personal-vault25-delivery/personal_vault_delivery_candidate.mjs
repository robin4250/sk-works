import { verifyVaultPdfBytes } from './verify_archive_bytes.mjs';
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const hash = /^[a-f0-9]{64}$/;
const sourceFields = ['source_company_id','source_worker_id','source_id','source_revision','snapshot_hash','manifest_hash','kind'];
const maxPdfBytes = 50 * 1024 * 1024;

// Isolation candidate: all adapters below MUST be bound server-side to the
// same verified bearer session. The client supplies only manifest/artifact.
// Real GoTrue, Storage version semantics and the independent content inspector
// are NOT wired; until they are, this must not be exposed as an endpoint.
export async function downloadOwnVaultPdf({manifestId, artifactKey}, services) {
  if (!uuid.test(manifestId ?? '') || !hash.test(artifactKey ?? '')) throw Error('vault_request_invalid');
  const actor = await services.liveActor();
  if (!uuid.test(actor?.ownerId ?? '') || !uuid.test(actor?.sessionId ?? '')) throw Error('vault_session_invalid');
  const entries = await services.listMine();
  const matches = entries.filter(x => x.manifest_id === manifestId && x.artifact_key === artifactKey &&
    ['own_attendance','own_payroll'].includes(x.kind));
  if (matches.length !== 1) throw Error('vault_owner_or_manifest_rejected');
  const sourceRows = await services.sourceMine(manifestId, artifactKey);
  if (!Array.isArray(sourceRows) || sourceRows.length !== 1) throw Error('vault_source_binding_rejected');
  const source = Object.freeze({...sourceRows[0]});
  if (!['source_company_id','source_worker_id','source_id'].every(k => uuid.test(source[k] ?? '')) ||
      typeof source.source_revision !== 'string' || !source.source_revision || source.source_revision.length > 256 ||
      !hash.test(source.snapshot_hash ?? '') || !hash.test(source.manifest_hash ?? '') ||
      source.kind !== matches[0].kind || source.source_company_id !== matches[0].source_company_id)
    throw Error('vault_source_binding_rejected');
  const rows = await services.itemMine(manifestId, artifactKey);
  if (!Array.isArray(rows) || rows.length !== 1) throw Error('vault_receipt_rejected');
  const row = rows[0];
  const path = `personal-vault/${actor.ownerId}/${artifactKey}.pdf`;
  if (row.object_path !== path || typeof row.object_version !== 'string' || !row.object_version ||
      !hash.test(row.pdf_hash ?? '') || !Number.isSafeInteger(row.byte_length) ||
      row.byte_length < 12 || row.byte_length > maxPdfBytes) throw Error('vault_receipt_rejected');
  const object = await services.storageMetadata(path, row.object_version);
  if (!object || object.objectPath !== path || object.version !== row.object_version ||
      object.contentType !== 'application/pdf' || object.byteLength !== row.byte_length) throw Error('vault_storage_object_rejected');
  // The real adapter must enforce this limit while streaming, before buffering.
  const downloaded = await services.download(path, row.object_version,
    {maxBytes: row.byte_length, expectedSha256: row.pdf_hash});
  // Reject a buffer with the wrong length before copying it. The real adapter
  // must still enforce the limit while streaming.
  if (!Buffer.isBuffer(downloaded) || downloaded.length !== row.byte_length)
    throw Error('vault_download_invalid');
  // Detach from a mutable storage-owned buffer before any further awaits.
  const bytes = Buffer.from(downloaded);
  const receipt = {status:'verified',contentType:'application/pdf',byteLength:row.byte_length,
    pdfSha256:row.pdf_hash,objectPath:path,immutableVersion:row.object_version};
  verifyVaultPdfBytes(bytes, receipt, object);
  // Inspection proof must come from a separately configured, trusted server
  // inspector; PDF header/text scanning alone does not establish privacy.
  const proof = await services.trustedPrivacyProof({manifestId,artifactKey,pdfSha256:row.pdf_hash,sourceBinding:source});
  if (!proof || proof.passed !== true || proof.policy !== 'own-snapshot-v2' ||
      proof.ownerId !== actor.ownerId || proof.manifestId !== manifestId ||
      proof.artifactKey !== artifactKey || proof.kind !== matches[0].kind || proof.pdfSha256 !== row.pdf_hash ||
      !proof.sourceBinding || sourceFields.some(k => proof.sourceBinding[k] !== source[k]))
    throw Error('vault_privacy_proof_rejected');
  const after = await services.liveActor();
  if (after?.ownerId !== actor.ownerId || after?.sessionId !== actor.sessionId) throw Error('vault_session_changed');
  const check = await services.itemMine(manifestId, artifactKey);
  const sourceCheck = await services.sourceMine(manifestId, artifactKey);
  if (!Array.isArray(sourceCheck) || sourceCheck.length !== 1 ||
      sourceFields.some(k => sourceCheck[0][k] !== source[k])) throw Error('vault_source_changed');
  const current = await services.storageMetadata(path, row.object_version);
  if (!Array.isArray(check) || check.length !== 1 || ['object_path','object_version','pdf_hash','byte_length']
      .some(k => check[0][k] !== row[k]) || !current || current.version !== object.version || current.objectPath !== path || current.contentType !== object.contentType || current.byteLength !== row.byte_length)
    throw Error('vault_receipt_or_object_changed');
  return bytes;
}
