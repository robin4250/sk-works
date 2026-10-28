import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { verifyVaultPdfBytes } from './verify_archive_bytes.mjs';
const bytes = Buffer.from('%PDF-1.7\nsynthetic\n%%EOF\n');
const receipt = {status:'verified',contentType:'application/pdf',byteLength:bytes.length,
  pdfSha256:createHash('sha256').update(bytes).digest('hex'),objectPath:'fixture/person/version.pdf',immutableVersion:'v1'};
const object = {objectPath:receipt.objectPath,version:'v1',contentType:'application/pdf'};
test('checks trusted exact version and verified bytes without mutating inputs',()=>{
  const saved=Buffer.from(bytes); assert.equal(verifyVaultPdfBytes(bytes,receipt,object).verified,true);
  assert.deepEqual(bytes,saved);
});
test('rejects swapped version, path, size, MIME and receipt',()=>{
  for(const other of [{...object,version:'v2'},{...object,objectPath:'elsewhere'},{...object,contentType:'text/plain'}])
    assert.throws(()=>verifyVaultPdfBytes(bytes,receipt,other));
  for(const bad of [{...receipt,byteLength:bytes.length+1},{...receipt,status:'draft'},{...receipt,pdfSha256:'a'.repeat(64)}])
    assert.throws(()=>verifyVaultPdfBytes(bytes,bad,object));
});
test('rejects corrupt payload and missing PDF markers even with matching supplied digest',()=>{
  for(const bad of [Buffer.from('no PDF header! %%EOF'),Buffer.from('%PDF-1.7 no end')]) {
    const r={...receipt,byteLength:bad.length,pdfSha256:createHash('sha256').update(bad).digest('hex')};
    assert.throws(()=>verifyVaultPdfBytes(bad,r,object));
  }
});
