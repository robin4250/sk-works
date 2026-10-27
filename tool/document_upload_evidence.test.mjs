import { test } from 'node:test';
import assert from 'node:assert/strict';
import { uploadEvidenceMatches } from './document_upload_evidence.mjs';

const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const item = { companyId:id(1), workerId:id(2), requirementId:id(3), requestId:id(4), actorId:id(5), bucket:'worker-documents', path:'document-change/opaque/object', mime:'application/pdf', bytes:1024, sha256:'a'.repeat(64), status:'inspected', objectVersion:'version-1' };
test('matching trusted evidence is accepted', () => assert.equal(uploadEvidenceMatches(item, {...item}), true));
test('cross-scope or modified objects are rejected', () => {
  for (const [key, value] of Object.entries({ companyId:id(8), workerId:id(8), requirementId:id(8), requestId:id(8), actorId:id(8), bucket:'other', path:'document-change/other', mime:'image/png', bytes:2048, sha256:'b'.repeat(64), status:'pending', objectVersion:'version-2' })) {
    assert.equal(uploadEvidenceMatches(item, {...item, [key]:value}), false, key);
  }
});
test('malformed expected data and missing immutable version fail closed', () => {
  for (const [key, value] of Object.entries({path:'document-change/../other', mime:'text/html', bytes:0, sha256:'no', status:'pending', objectVersion:''})) {
    const invalid = {...item, [key]:value};
    assert.equal(uploadEvidenceMatches(invalid, {...invalid}), false, key);
  }
  assert.equal(uploadEvidenceMatches(null, item), false);
});
