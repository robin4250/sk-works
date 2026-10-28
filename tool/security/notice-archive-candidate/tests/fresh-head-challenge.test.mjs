// Isolated protocol experiment; no production endpoints or real keys.
import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign,verify,randomBytes} from 'node:crypto';
const {privateKey,publicKey}=generateKeyPairSync('ed25519');
const canonical = x => Buffer.from(JSON.stringify({v:x.v,scope:x.scope,nonce:x.nonce,sequence:x.sequence,hash:x.hash,issued:x.issued}));
function issue(nonce, sequence, hash, issued=1000, scope='fixture') {const payload={v:1,scope,nonce,sequence,hash,issued};return {payload,signature:sign(null,canonical(payload),privateKey)};}
function check(response,{nonce,now,checkpoint,scope='fixture'}) {const p=response?.payload;if(!p||p.v!==1||p.scope!==scope||p.nonce!==nonce||!Number.isSafeInteger(p.issued)||p.issued>now||now-p.issued>30000||!Number.isSafeInteger(p.sequence)||p.sequence<checkpoint.sequence||typeof p.hash!=='string'||!(/^[0-9a-f]{64}$/.test(p.hash))||!verify(null,canonical(p),publicKey,response.signature))throw Error('rejected'); if(p.sequence===checkpoint.sequence&&p.hash!==checkpoint.hash)throw Error('fork');return {sequence:p.sequence,hash:p.hash};}
const h='a'.repeat(64),h2='b'.repeat(64),nonce=()=>randomBytes(32).toString('hex');
test('bound challenge accepts signed fresh head',()=>{let n=nonce();assert.deepEqual(check(issue(n,2,h2),{nonce:n,now:1000,checkpoint:{sequence:1,hash:h}}),{sequence:2,hash:h2});});
test('stale replay and cross scope are rejected',()=>{let n=nonce(),signed=issue(n,2,h2);assert.throws(()=>check(signed,{nonce:nonce(),now:1000,checkpoint:{sequence:1,hash:h}}));assert.throws(()=>check(signed,{nonce:n,now:31001,checkpoint:{sequence:1,hash:h}}));assert.throws(()=>check(signed,{nonce:n,scope:'other',now:1000,checkpoint:{sequence:1,hash:h}}));});
test('rollback fork and changed signed body fail',()=>{let n=nonce(),context={nonce:n,now:1000,checkpoint:{sequence:2,hash:h2}};assert.throws(()=>check(issue(n,1,h),context));assert.throws(()=>check(issue(n,2,h),context));let s=issue(n,2,h2);s.payload.hash=h;assert.throws(()=>check(s,context));});
// A signed current-challenge response from a lying or restored authority can
// still hide newer history. This is not a replacement for an independent,
// durable witness, authenticated channel, key custody, or production recovery.
