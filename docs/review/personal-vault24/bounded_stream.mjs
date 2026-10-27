// Offline building block only: provider object-version guarantees and actor
// authorization must be enforced by the eventual storage adapter.
export async function readBoundedPdfStream(stream, {maxBytes}) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 12 || maxBytes > 50 * 1024 * 1024 ||
      !stream || typeof stream[Symbol.asyncIterator] !== 'function') throw Error('vault_stream_invalid');
  const chunks = [];
  let size = 0;
  for await (const chunk of stream) {
    if (!(chunk instanceof Uint8Array)) throw Error('vault_stream_invalid');
    if (chunk.byteLength > maxBytes - size) throw Error('vault_stream_limit_exceeded');
    // Copy before the producer can mutate or reuse its buffer.
    chunks.push(Buffer.from(chunk));
    size += chunk.byteLength;
  }
  if (size !== maxBytes) throw Error('vault_stream_size_mismatch');
  return Buffer.concat(chunks, size);
}
