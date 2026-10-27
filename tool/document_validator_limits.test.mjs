import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createDocumentFileValidator } from './document_file_validator.mjs';

test('invalid dimensions are rejected before image decoding', async () => {
  let decoded = 0;
  for (const [width, height] of [[-1, 3], [1.5, 3], [10000, 4001], [Infinity, 3]]) {
    const sharp = () => ({
      metadata: async () => ({ format: 'png', width, height }),
      raw: () => ({ toBuffer: async () => { decoded++; return Buffer.alloc(1); } }),
    });
    const validate = createDocumentFileValidator({ sharp, pdfjs: { getDocument() {} } });
    assert.equal(await validate({ bytes: new Uint8Array(8), mime: 'image/png' }), false);
  }
  assert.equal(decoded, 0);
});
