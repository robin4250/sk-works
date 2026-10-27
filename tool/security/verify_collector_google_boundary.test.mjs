// Offline compatibility proof only. No endpoint, credential acquisition or issuer.
import test from 'node:test';
import assert from 'node:assert/strict';
import { verifyGooglePrimary, GooglePrimaryDenied } from '../../docs/review/apple-existing-login-candidate/google_primary_verifier.mjs';

const now = 1800000000;
const actor = '00000000-0000-0000-0000-000000000001';
const sid = '00000000-0000-0000-0000-000000000002';
const operation = 'master.security_collector.read';
const target = { scope: 'decoy_collector' };
const keys = await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5', modulusLength:2048, publicExponent:new Uint8Array([1,0,1]), hash:'SHA-256'}, true, ['sign','verify']);
const jwk = {...await crypto.subtle.exportKey('jwk', keys.publicKey), kid:'synthetic-key', alg:'RS256', use:'sig'};
const base64 = x => Buffer.from(typeof x === 'string' ? x : JSON.stringify(x)).toString('base64url');
async function signed(changes = {}) {
  const claim = {iss:'https://accounts.google.com', aud:'synthetic-web', azp:'synthetic-ios', sub:'synthetic-subject', nonce:'n'.repeat(43), iat:now, exp:now+600, auth_time:now, ...changes};
  const data = base64({alg:'RS256',kid:jwk.kid})+'.'+base64(claim);
  return data+'.'+Buffer.from(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',keys.privateKey,new TextEncoder().encode(data))).toString('base64url');
}
function setup() {
  let consumed = false;
  const calls = [];
  const challenge = {actor_id:actor, session_id:sid, operation, target, nonce:'n'.repeat(43), issued_at:now, expires_at:now+120};
  const user = {id:actor,is_anonymous:false,identities:[{provider:'google',user_id:actor,identity_data:{sub:'synthetic-subject'}}]};
  const ports = {enabled:true,now:()=>now,audiences:['synthetic-web'],authorizedPresenters:['synthetic-ios'],
    authenticateExactBearer:async()=>({user,claims:{sub:actor,role:'authenticated',session_id:sid,exp:now+600}}),
    loadChallenge:async()=>structuredClone(challenge), resolveGoogleKey:async()=>jwk,
    consumeChallenge:async binding=>{calls.push(binding);if(consumed)return false;consumed=true;return true;}};
  return {ports,challenge,calls};
}
const input = async changes => ({exactBearer:'synthetic-bearer',challengeId:'c'.repeat(43),idToken:await signed(changes)});

test('collector challenge produces bound internal evidence, never an operation proof or session', async()=>{
  const f=setup(), value=await verifyGooglePrimary(await input(),f.ports);
  assert.equal(value.operation,operation);assert.deepEqual(value.target,target);
  assert.equal(value.actor,actor);assert.equal(value.session,sid);
  assert.equal('proof' in value,false);assert.equal('access_token' in value,false);
  assert.deepEqual(f.calls[0].target,target);assert.equal(f.calls[0].operation,operation);
  await assert.rejects(verifyGooglePrimary(await input(),f.ports),GooglePrimaryDenied);
});
test('old Google authentication cannot obtain fresh collector evidence even with a fresh token',async()=>{
  const f=setup();await assert.rejects(verifyGooglePrimary(await input({auth_time:now-3600}),f.ports),GooglePrimaryDenied);assert.equal(f.calls.length,0);
});
test('foreign bearer session cannot consume an existing collector challenge',async()=>{
  const f=setup();f.challenge.session_id='00000000-0000-0000-0000-000000000003';
  await assert.rejects(verifyGooglePrimary(await input(),f.ports),GooglePrimaryDenied);assert.equal(f.calls.length,0);
});
