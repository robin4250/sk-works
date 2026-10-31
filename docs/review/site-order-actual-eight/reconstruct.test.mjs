import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {reconstruct, hash} from './reconstruct.mjs';
const root = path.resolve(new URL('../../../', import.meta.url).pathname);
const read = file => fs.readFile(path.join(root, file), 'utf8');
const contract = JSON.parse(await fs.readFile(new URL('./source-contract.json', import.meta.url), 'utf8'));
test('all eight bodies come from pinned public sources', async () => {
  const result = await reconstruct(read, contract);
  assert.equal(result.generic.length, 7);
  assert.equal(Buffer.byteLength(result.sealBody), 1751);
  assert.equal(hash('md5', result.sealBody), '823cc52d0c652e7f04ff816a8a8eaf64');
  assert.ok(!result.generic.some(item => item.signature.includes('document_company_seal_snapshot')));
});
test('every public input rejects byte drift', async () => {
  for (const file of Object.keys(contract.files)) {
    await assert.rejects(reconstruct(async name => (await read(name)) + (name === file ? '\n' : ''), contract));
  }
});
test('wrong base fingerprint and public patch fingerprint reject', async () => {
  await assert.rejects(reconstruct(read, {...contract, seal_base_body_md5: '0'.repeat(32)}));
  await assert.rejects(reconstruct(read, {...contract, seal_patch_statement_sha256: '0'.repeat(64)}));
});
