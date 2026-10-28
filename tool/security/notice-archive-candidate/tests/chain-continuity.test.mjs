// Synthetic, in-memory chain experiment. Not production evidence or custody.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, sign, verify} from 'node:crypto';
const keys = generateKeyPairSync('ed25519');
const digest = value => createHash('sha256').update(value).digest('hex');
const encode = x => Buffer.from(JSON.stringify({sequence:x.sequence, previous:x.previous, payload:x.payload}));
const issue = (sequence, previous, payload) => { const record = {sequence, previous, payload}; return {record, signature:sign(null, encode(record), keys.privateKey)}; };
const hash = item => digest(encode(item.record));
function verifyExtension(checkpoint, records) {
  if (!Array.isArray(records) || records.length > 100) throw new Error('invalid chain');
  let current = checkpoint;
  for (const item of records) {
    const r = item?.record;
    if (!r || !Number.isSafeInteger(r.sequence) || r.sequence !== current.sequence+1 || r.previous !== current.hash || !verify(null, encode(r), keys.publicKey, item.signature)) throw new Error('invalid extension');
    current = {sequence:r.sequence,hash:hash(item)};
  }
  return current;
}
const checkpoint={sequence:0,hash:'0'.repeat(64)};
test('signed contiguous history extends prior checkpoint',()=>{const a=issue(1,checkpoint.hash,'a'), b=issue(2,hash(a),'b');assert.deepEqual(verifyExtension(checkpoint,[a,b]),{sequence:2,hash:hash(b)});});
test('higher sequence alone does not prove ancestry',()=>{const a=issue(1,checkpoint.hash,'original'), fork=issue(2,'f'.repeat(64),'fork');assert.throws(()=>verifyExtension({sequence:1,hash:hash(a)},[fork]));});
test('rejects gaps, body edits and reordered history',()=>{const a=issue(1,checkpoint.hash,'a'), b=issue(2,hash(a),'b');assert.throws(()=>verifyExtension(checkpoint,[b]));assert.throws(()=>verifyExtension(checkpoint,[b,a]));const changed={record:{...a.record,payload:'changed'},signature:a.signature};assert.throws(()=>verifyExtension(checkpoint,[changed]));});
