import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { networkInterfaces } from 'node:os';
import { createConnection } from 'node:net';
import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { startIsolatedTransport } from './isolated_transport.mjs';

// This opt-in entry runs only after Docker network-none is inspected by CI.
assert.equal(process.env.SKO_DECOY_NETWORK_NONE_FIXTURE, '1');
assert.equal(process.platform, 'linux');
assert.equal(process.getuid(), 65534, 'unprivileged fixture uid');
const status = await readFile('/proc/self/status', 'utf8');
assert.match(status, /^CapEff:\s+0+$/m);
assert.match(status, /^NoNewPrivs:\s+1$/m);
const interfaces = Object.entries(networkInterfaces());
assert.ok(interfaces.length > 0);
for (const [name, addresses] of interfaces) {
  assert.equal(name, 'lo');
  assert.ok(addresses.every(address => address.internal));
}
const ipv4Routes = (await readFile('/proc/net/route', 'utf8')).trim().split('\n').slice(1);
assert.equal(ipv4Routes.length, 0, 'no IPv4 route, including host/production');
for (const row of (await readFile('/proc/net/ipv6_route', 'utf8')).trim().split('\n').filter(Boolean)) {
  assert.equal(row.trim().split(/\s+/).at(-1), 'lo', 'no external IPv6 route');
}

// RFC documentation-only addresses, not an actual service or production target.
// A timeout is NOT accepted as evidence of kernel isolation.
for (const host of ['192.0.2.1', '2001:db8::1']) {
  await new Promise((resolve, reject) => {
    const socket = createConnection({host, port: 9});
    socket.setTimeout(1000, () => { socket.destroy(); reject(Error('Isolation probe timed out')); });
    socket.once('connect', () => { socket.destroy(); reject(Error('Unexpected external route')); });
    socket.once('error', error => {
      socket.destroy();
      try { assert.equal(error.code, 'ENETUNREACH'); resolve(); } catch (failure) { reject(failure); }
    });
  });
}

// A separate synthetic normal service: no app/DB/Auth/employee data is mounted.
const normal = http.createServer((_request, response) => {
  response.writeHead(200, {'Content-Type': 'application/json', 'Cache-Control': 'no-store'});
  response.end('{"environment":"synthetic-normal","unchanged":true}');
});
await new Promise(resolve => normal.listen(0, '127.0.0.1', resolve));
const normalUrl = `http://127.0.0.1:${normal.address().port}`;
const token = randomBytes(32).toString('hex');
const lab = await startIsolatedTransport({operatorToken: token});
async function normalUnchanged() {
  const response = await fetch(normalUrl, {signal: AbortSignal.timeout(2000)});
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {environment: 'synthetic-normal', unchanged: true});
}
async function call(path, expected, authenticated = false) {
  const response = await fetch(lab.origin + path, {
    method: path.startsWith('/operator/') ? 'POST' : 'GET',
    headers: authenticated ? {Authorization: `Bearer ${token}`} : {},
    signal: AbortSignal.timeout(2000),
  });
  assert.equal(response.status, expected);
  await response.arrayBuffer();
}
try {
  await normalUnchanged();
  const oldLure = lab.inspect().lure;
  await call(oldLure, 200);
  await call('/operator/quarantine', 403);
  await call(oldLure, 200);
  await call('/operator/quarantine', 204, true);
  await call(oldLure, 503);
  await normalUnchanged();
  await call('/operator/rotate', 204, true);
  const newLure = lab.inspect().lure;
  assert.notEqual(newLure, oldLure);
  await call(newLure, 503);
  await normalUnchanged();
  await call('/operator/release', 204, true);
  await call(newLure, 200);
  await call(oldLure, 200);
  await call('/normal-app-route', 404);
  await normalUnchanged();
  assert.ok(lab.inspect().events.every(event => Object.keys(event).sort().join(',') === 'at,kind'));
  console.log('PASS: kernel network-none IPv4/IPv6 egress refusal, unprivileged/no-capability process, loopback decoy rotation/quarantine/release and independent synthetic normal service unchanged');
} finally {
  await lab.close();
  await new Promise(resolve => { normal.close(resolve); normal.closeAllConnections(); });
}
