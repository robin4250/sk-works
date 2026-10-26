import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, randomBytes, sign } from 'node:crypto';
import { qrDeviceSigningBytes, qrTokenHash, verifyQrDeviceChallenge } from './qr-device-verification.mjs';

const { privateKey, publicKey } = generateKeyPairSync('ed25519');
const key = publicKey.export({format:'der', type:'spki'});
const c = {companyId:'00000000-0000-4000-8000-000000000001', deviceId:'00000000-0000-4000-8000-000000000002', challengeId:'00000000-0000-4000-8000-000000000003', tokenHash:qrTokenHash(randomBytes(32).toString('base64url')), action:'clock_out', sourceClockInId:'00000000-0000-4000-8000-000000000004'};
const signature = sign(null, qrDeviceSigningBytes(c), privateKey);
const valid = {publicKeyDer:key, signature, challenge:c, enabled:true, deviceActive:true,
  authorized:true, expiresAt:1200, now:1000, consumed:false};

test('valid approved device signature', () => assert.equal(verifyQrDeviceChallenge(valid), true));
test('every challenge component is bound to signature', () => {
  for (const [field, value] of Object.entries({companyId:'00000000-0000-4000-8000-000000000010', deviceId:'00000000-0000-4000-8000-000000000011', challengeId:'00000000-0000-4000-8000-000000000012', tokenHash:'a'.repeat(64), sourceClockInId:'00000000-0000-4000-8000-000000000013'})) {
    assert.equal(verifyQrDeviceChallenge({...valid, challenge:{...c, [field]:value}}), false, field);
  }
  assert.equal(verifyQrDeviceChallenge({...valid, challenge:{...c, action:'clock_in', sourceClockInId:null}}), false);
});
test('off, revoked, unauthorized, expired and consumed fail closed', () => {
  for (const change of [{enabled:false}, {deviceActive:false}, {authorized:false}, {now:1200}, {consumed:true}, {consumed:null}]) {
    assert.equal(verifyQrDeviceChallenge({...valid, ...change}), false);
  }
});
test('malformed keys, signatures and QR tokens rejected', () => {
  assert.equal(verifyQrDeviceChallenge({...valid, signature:Buffer.alloc(64)}), false);
  assert.equal(verifyQrDeviceChallenge({...valid, publicKeyDer:Buffer.alloc(44)}), false);
  assert.throws(() => qrTokenHash('short'));
  assert.throws(() => qrDeviceSigningBytes({...c, action:'clock_in'}));
});
