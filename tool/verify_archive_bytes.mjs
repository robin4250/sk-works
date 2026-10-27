import { createHash, timingSafeEqual } from 'node:crypto';

// Internal-only boundary: the caller must obtain the immutable object version
// and receipt from trusted Storage/catalog APIs, never from the requesting user.
// This detects corrupt or substituted bytes; it does not prove PDF privacy,
// authenticate the caller, or guarantee provider-level immutable storage.
export function verifyVaultPdfBytes(bytes, receipt, object) {
  if (!Buffer.isBuffer(bytes) || bytes.length < 12 || bytes.length > 20 * 1024 * 1024 ||
      receipt?.status !== 'verified' || receipt?.contentType !== 'application/pdf' ||
      !Number.isSafeInteger(receipt.byteLength) || receipt.byteLength !== bytes.length ||
      typeof receipt.pdfSha256 !== 'string' || !/^[a-f0-9]{64}$/.test(receipt.pdfSha256) ||
      typeof receipt.objectPath !== 'string' || !receipt.objectPath ||
      typeof receipt.immutableVersion !== 'string' || !receipt.immutableVersion ||
      object?.objectPath !== receipt.objectPath || object?.version !== receipt.immutableVersion ||
      object?.contentType !== 'application/pdf') throw Error('vault_object_receipt_rejected');
  if (!bytes.subarray(0, 5).equals(Buffer.from('%PDF-')) ||
      !/%%EOF\s*$/.test(bytes.subarray(Math.max(0, bytes.length - 1024)).toString('latin1'))) {
    throw Error('vault_pdf_structure_rejected');
  }
  const expected = Buffer.from(receipt.pdfSha256, 'hex');
  const actual = createHash('sha256').update(bytes).digest();
  if (!timingSafeEqual(actual, expected)) throw Error('vault_pdf_digest_mismatch');
  return { verified: true, byteLength: bytes.length, sha256: actual.toString('hex') };
}
