export function collectorFixtureUrl(raw) {
  let url;
  try { url = new URL(raw); } catch { throw Error('Disposable collector fixture URL required'); }
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
      url.protocol !== 'postgresql:' || url.pathname !== '/sko_collector_fixture' ||
      url.username !== 'postgres' || url.password !== 'fixture-only' ||
      url.search || url.hash) throw Error('Disposable loopback collector fixture only');
  return url.href;
}
