export function distributionFixtureUrl(raw) {
  let url;
  try { url = new URL(raw); } catch { throw Error('Disposable distribution fixture URL required'); }
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
      url.protocol !== 'postgresql:' || url.pathname !== '/sko_distribution_fixture' ||
      url.username !== 'postgres' || url.password !== 'fixture-only' ||
      url.search || url.hash) throw Error('Disposable loopback distribution fixture only');
  return url.href;
}

