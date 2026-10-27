import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { createDocumentFileValidator } from './document_file_validator.mjs';

// The runtime directory is supplied by the test runner; production must use
// separately installed and pinned packages, not a host-specific directory.
const root = process.env.SKO_TEST_NODE_MODULES;
if (!root) throw Error('SKO_TEST_NODE_MODULES is required');
const require = createRequire(`${root}/`);
const sharp = require('sharp');
const { PDFDocument } = require('pdf-lib');
const pdfjs = await import(pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.mjs')));
const validate = createDocumentFileValidator({ sharp, pdfjs });

test('a real image is decoded and malformed image is rejected', async () => {
  const valid = await sharp({ create: { width: 8, height: 8, channels: 3, background: '#4682b4' } }).png().toBuffer();
  assert.equal(await validate({ bytes: valid, mime: 'image/png' }), true);
  assert.equal(await validate({ bytes: valid.subarray(0, 20), mime: 'image/png' }), false);
  assert.equal(await validate({ bytes: valid, mime: 'image/jpeg' }), false);
});
test('a real PDF is parsed, truncation and empty pages are rejected', async () => {
  const pdf = await PDFDocument.create(); pdf.addPage([100, 100]);
  const bytes = await pdf.save();
  assert.equal(await validate({ bytes, mime: 'application/pdf' }), true);
  assert.equal(await validate({ bytes: bytes.subarray(0, 40), mime: 'application/pdf' }), false);
  const empty = await (await PDFDocument.create()).save({ addDefaultPage: false });
  assert.equal(await validate({ bytes: empty, mime: 'application/pdf' }), false);
});
