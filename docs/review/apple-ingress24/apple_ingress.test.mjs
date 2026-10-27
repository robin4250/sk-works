import test from 'node:test';
import assert from 'node:assert/strict';
import {createAppleKeyResolver} from './apple_key_resolver.mjs';
import {createAppleEnrollmentRateGate} from './apple_rate_gate.mjs';
const key = {kid:'key1',kty:'RSA',alg:'RS256',use:'sig',n:'a'.repeat(350),e:'AQAB'};
const json = value => new Response(JSON.stringify(value),{headers:{'content-type':'application/json'}});
test('fixed Apple origin, cache and rotation expiry',async()=>{let calls=0,clock=0;const resolve=createAppleKeyResolver({now:()=>clock,ttlMs:10,fetcher:async (u,o)=>{calls++;assert.equal(u,'https://appleid.apple.com/auth/keys');assert.equal(o.redirect,'error');return json({keys:[key]});}});assert.equal((await resolve('key1')).kid,'key1');await resolve('key1');assert.equal(calls,1);clock=11;await resolve('key1');assert.equal(calls,2);});
test('malformed, duplicate, private keys and absent kid are denied',async()=>{for(const keys of [[key,key],[{...key,d:'secret'}],[{...key,kty:'EC'}],[]]){const resolve=createAppleKeyResolver({fetcher:async()=>json({keys})});await assert.rejects(resolve('key1'));}const resolve=createAppleKeyResolver({fetcher:async()=>json({keys:[key]})});await assert.rejects(resolve('missing'));});
test('fetch and response body that ignore abort cannot hang',async()=>{let resolve=createAppleKeyResolver({timeoutMs:20,fetcher:()=>new Promise(()=>{})});await assert.rejects(resolve('key1'));resolve=createAppleKeyResolver({timeoutMs:20,fetcher:async()=>new Response(new ReadableStream({pull(){return new Promise(()=>{});}}))});await assert.rejects(resolve('key1'));});
test('concurrent refresh coalesces and errors do not produce a cached key',async()=>{let calls=0;const resolve=createAppleKeyResolver({fetcher:async()=>{calls++;return json({keys:[key]});}});await Promise.all([resolve('key1'),resolve('key1')]);assert.equal(calls,1);});
test('durable trusted actor limiter defaults off and fails closed',async()=>{const actorId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',sessionId='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';let calls=0;const disabled=createAppleEnrollmentRateGate({take:async()=>({allowed:true,durable:true})});await assert.rejects(disabled.check({actorId,sessionId}));const gate=createAppleEnrollmentRateGate({enabled:true,take:async x=>{calls++;assert.deepEqual(x,{actorId,sessionId});return {allowed:true,durable:true};}});await gate.check({actorId,sessionId});assert.equal(calls,1);for(const answer of [{allowed:false,durable:true},{allowed:true,durable:false},null]){const bad=createAppleEnrollmentRateGate({enabled:true,take:async()=>answer});await assert.rejects(bad.check({actorId,sessionId}));}});
test('late response after timeout cannot populate the cache',async()=>{let release,calls=0;const resolve=createAppleKeyResolver({timeoutMs:20,fetcher:()=>{calls++;if(calls===1)return new Promise(r=>{release=r;});return Promise.resolve(json({keys:[key]}));}});await assert.rejects(resolve('key1'));release(json({keys:[key]}));await new Promise(r=>setTimeout(r,0));await resolve('key1');assert.equal(calls,2);});

test('oversized streaming JWKS is denied and the reader is cancelled',async()=>{
  let cancelled=false;
  const stream=new ReadableStream({start(c){c.enqueue(new Uint8Array(65537));},cancel(){cancelled=true;}});
  const resolve=createAppleKeyResolver({fetcher:async()=>new Response(stream)});
  await assert.rejects(resolve('key1'));
  assert.equal(cancelled,true);
});
test('expired key is never served if a later refresh fails',async()=>{
  let clock=0,calls=0;
  const resolve=createAppleKeyResolver({now:()=>clock,ttlMs:10,fetcher:async()=>{if(++calls===1)return json({keys:[key]});throw Error('network');}});
  await resolve('key1');clock=10;await assert.rejects(resolve('key1'));assert.equal(calls,2);
});

test('shared rate port denies mismatched identities and cancels oversized replies',async()=>{
 const {createAppleSharedRatePort}=await import('./wired/apple_shared_rate_port.mjs');
 const actor='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',sid='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
 let calls=0,cancelled=false;
 const gate=createAppleSharedRatePort({enabled:true,baseUrl:'https://ztktgquxvcxcjxtluspu.supabase.co',serviceKey:'fixture-service',fetcher:async()=>{calls++;return new Response(new ReadableStream({start(c){c.enqueue(new Uint8Array(4097));},cancel(){cancelled=true;}}));}});
 await assert.rejects(gate.takeVerified({user:{id:actor},claims:{sub:sid,session_id:sid}}));
 assert.equal(calls,0);
 await assert.rejects(gate.takeVerified({user:{id:actor},claims:{sub:actor,session_id:sid}}));
 assert.equal(calls,1);assert.equal(cancelled,true);
});
