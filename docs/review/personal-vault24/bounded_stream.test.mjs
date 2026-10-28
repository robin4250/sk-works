import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readBoundedPdfStream} from './bounded_stream.mjs';

test('copies chunks so a reused stream buffer cannot alter prior content', async () => {
  async function* chunks() { const b=Buffer.from('abcdef'); yield b; b.fill(120); yield b; }
  assert.equal((await readBoundedPdfStream(chunks(), {maxBytes:12})).toString(), 'abcdefxxxxxx');
});
test('oversize is refused while streaming and closes iterator', async () => {
  let closed=false;
  async function* chunks() { try {yield Buffer.alloc(10); yield Buffer.alloc(3); throw Error('should not consume');} finally {closed=true;} }
  await assert.rejects(readBoundedPdfStream(chunks(), {maxBytes:12}), /vault_stream_limit_exceeded/);
  assert.equal(closed,true);
});
test('short, invalid, and failed streams are refused', async () => {
  async function* short(){yield Buffer.alloc(11)}
  async function* bad(){yield 'not bytes'}
  async function* failed(){yield Buffer.alloc(2);throw Error('read failed')}
  await assert.rejects(readBoundedPdfStream(short(), {maxBytes:12}), /vault_stream_size_mismatch/);
  await assert.rejects(readBoundedPdfStream(bad(), {maxBytes:12}), /vault_stream_invalid/);
  await assert.rejects(readBoundedPdfStream(failed(), {maxBytes:12}), /read failed/);
  await assert.rejects(readBoundedPdfStream(short(), {maxBytes:50*1024*1024+1}), /vault_stream_invalid/);
});
