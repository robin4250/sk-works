import { createHash } from 'node:crypto';
import { readBoundedPdfStream } from '../personal-vault24/bounded_stream.mjs';

// Server-only candidate, not an endpoint. The coordinator must independently
// authorize the owner/session and supply the saved receipt's hash and version.
// Storage REST reads the current object: this does not establish immutable
// version retention. Changed current bytes are refused by the receipt hash.
export function createVaultStorageDownload({origin, bucket, publishableKey,
  authorizationHeader, fetchImpl = fetch, timeoutMs = 15000}) {
  const base = new URL(origin);
  if (base.protocol !== 'https:' || base.username || base.password || base.search || base.hash ||
      base.pathname !== '/' || !/^[a-z0-9][a-z0-9_-]{0,62}$/.test(bucket) ||
      !/^sb_publishable_[A-Za-z0-9_-]+$/.test(publishableKey) ||
      typeof authorizationHeader !== 'function' || typeof fetchImpl !== 'function' ||
      !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 30000)
    throw Error('vault_storage_config_invalid');
  return async (path, version, {maxBytes, expectedSha256} = {}) => {
    if (!/^personal-vault\/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\/[a-f0-9]{64}\.pdf$/.test(path) ||
        typeof version !== 'string' || version.length < 1 || version.length > 256 ||
        !Number.isSafeInteger(maxBytes) || maxBytes < 12 || maxBytes > 50 * 1024 * 1024 ||
        !/^[a-f0-9]{64}$/.test(expectedSha256 ?? '')) throw Error('vault_storage_request_invalid');
    const abort = new AbortController();
    let timer, reader;
    const expired = new Promise((_, reject) => {
      timer = setTimeout(() => { abort.abort(); reject(Error('vault_storage_timeout')); }, timeoutMs);
    });
    const within = operation => Promise.race([Promise.resolve().then(operation), expired]);
    try {
      const bearer = await within(authorizationHeader);
      if (typeof bearer !== 'string' || !/^Bearer [A-Za-z0-9_.-]+$/.test(bearer))
        throw Error('vault_storage_session_invalid');
      const url = new URL(`/storage/v1/object/${bucket}/${path}`, base);
      const response = await within(() => fetchImpl(url.href, {
        method:'GET', redirect:'manual', cache:'no-store', signal:abort.signal,
        headers:{Authorization:bearer, apikey:publishableKey, Accept:'application/pdf'},
      }));
      if (response.status !== 200 || response.redirected === true || !response.body?.getReader ||
          response.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/pdf' ||
          ![null,'identity'].includes(response.headers.get('content-encoding')))
        throw Error('vault_storage_response_rejected');
      const length = response.headers.get('content-length');
      if (length !== null && (!/^\d+$/.test(length) || Number(length) !== maxBytes))
        throw Error('vault_storage_response_rejected');
      reader = response.body.getReader();
      async function* chunks() {
        while (true) {
          const next = await within(() => reader.read());
          if (next.done) return;
          yield next.value;
        }
      }
      const bytes = await readBoundedPdfStream(chunks(), {maxBytes});
      if (createHash('sha256').update(bytes).digest('hex') !== expectedSha256)
        throw Error('vault_storage_hash_mismatch');
      return bytes;
    } catch (error) {
      // Never forward fetch exceptions, URLs or bearer data to a caller/log.
      if (error instanceof Error && /^vault_(storage|stream)_/.test(error.message)) throw error;
      throw Error('vault_storage_download_failed');
    } finally {
      clearTimeout(timer); abort.abort();
      // Cleanup must not extend the deadline when a provider ignores abort.
      if (reader) { try { Promise.resolve(reader.cancel()).catch(() => {}); } catch (_) {} }
    }
  };
}
