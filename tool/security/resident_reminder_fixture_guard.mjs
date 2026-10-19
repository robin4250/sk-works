export function resident_reminderFixtureUrl(raw) {
  let url;
  try { url = new URL(raw); } catch { throw Error('Disposable resident_reminder fixture URL required'); }
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
      url.protocol !== 'postgresql:' || url.pathname !== '/sko_resident_reminder_fixture' ||
      url.username !== 'postgres' || url.password !== 'fixture-only' ||
      url.search || url.hash) throw Error('Disposable loopback resident_reminder fixture only');
  return url.href;
}

