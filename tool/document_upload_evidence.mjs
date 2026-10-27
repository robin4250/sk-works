// Display-free validation for an independently inspected immutable upload.
// It does not fetch files or authorize users; the caller must obtain evidence
// from trusted storage and verify file bytes before calling this function.
export function uploadEvidenceMatches(expected, actual) {
  if (!expected || !actual || typeof expected !== 'object' || typeof actual !== 'object') return false;
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const hash = /^[0-9a-f]{64}$/;
  const types = new Set(['image/jpeg', 'image/png', 'image/heic', 'application/pdf']);
  for (const key of ['companyId', 'workerId', 'requirementId', 'requestId', 'actorId']) {
    if (typeof expected[key] !== 'string' || !uuid.test(expected[key]) || actual[key] !== expected[key]) return false;
  }
  if (expected.bucket !== 'worker-documents' || actual.bucket !== expected.bucket) return false;
  const prefix = `${expected.companyId}/${expected.workerId}/${expected.requirementId}/${expected.requestId}/`;
  if (typeof expected.path !== 'string' || expected.path.length > 1024 || !expected.path.startsWith(prefix) || expected.path.length === prefix.length) return false;
  if (expected.path.includes('..') || expected.path.includes('\\') || expected.path.includes('//') || actual.path !== expected.path) return false;
  if (!types.has(expected.mime) || actual.mime !== expected.mime) return false;
  if (!Number.isSafeInteger(expected.bytes) || expected.bytes <= 0 || expected.bytes > 20 * 1024 * 1024 || actual.bytes !== expected.bytes) return false;
  if (typeof expected.sha256 !== 'string' || !hash.test(expected.sha256) || actual.sha256 !== expected.sha256) return false;
  if (expected.status !== 'inspected' || actual.status !== 'inspected' || actual.objectVersion !== expected.objectVersion) return false;
  return typeof expected.objectVersion === 'string' && expected.objectVersion.length > 0 && expected.objectVersion.length <= 256;
}
