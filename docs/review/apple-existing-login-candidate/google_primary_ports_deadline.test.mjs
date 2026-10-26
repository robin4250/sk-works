import test from 'node:test';
import assert from 'node:assert/strict';
import {createGooglePrimaryPorts} from './google_primary_ports.mjs';

const origin='https://ztktgquxvcxcjxtluspu.supabase.co';
const jwk={kid:'synthetic-key',kty:'RSA',alg:'RS256',use:'sig',n:'AQAB',e:'AQAB'};
const cfg={enabled:true,baseUrl:origin,publicKey:'synthetic-public',audiences:['synthetic-client'],authorizedPresenters:[],loadChallenge:async()=>null,consumeChallenge:async()=>false,timeoutMs:25,now:()=>1800000000};
const unavailable=/google_primary_verification_unavailable/;

test('outer deadline ends an ignored-abort network operation',async()=>{
 let signal;const p=createGooglePrimaryPorts({...cfg,fetcher:(_url,init)=>{signal=init.signal;return new Promise(()=>{});}});
 const before=Date.now();await assert.rejects(p.resolveGoogleKey(jwk.kid),unavailable);assert(Date.now()-before<1000);assert.equal(signal.aborted,true);
});
test('deadline covers response body consumption and cancels a stalled reader',async()=>{
 let cancelled=false;const p=createGooglePrimaryPorts({...cfg,fetcher:async()=>new Response(new ReadableStream({cancel(){cancelled=true;}}))});
 await assert.rejects(p.resolveGoogleKey(jwk.kid),unavailable);assert.equal(cancelled,true);
});
test('oversized declared response is rejected before its body is consumed',async()=>{
 let cancelled=false;const p=createGooglePrimaryPorts({...cfg,fetcher:async()=>new Response(new ReadableStream({cancel(){cancelled=true;}}),{headers:{'content-length':'65537'}})});
 await assert.rejects(p.resolveGoogleKey(jwk.kid),unavailable);assert.equal(cancelled,true);
});
test('oversized streamed response is rejected without caching keys',async()=>{
 let calls=0;const p=createGooglePrimaryPorts({...cfg,fetcher:async()=>{calls++;return new Response(new Uint8Array(65537));}});
 await assert.rejects(p.resolveGoogleKey(jwk.kid),unavailable);await assert.rejects(p.resolveGoogleKey(jwk.kid),unavailable);assert.equal(calls,2);
});
test('duplicate identifiers and any private RSA fields are never cached',async()=>{
 for(const keys of [[jwk,jwk],...['d','p','q','dp','dq','qi','oth'].map(field=>[{...jwk,[field]:'rejected-synthetic-value'}])]){
  const p=createGooglePrimaryPorts({...cfg,fetcher:async()=>Response.json({keys})});await assert.rejects(p.resolveGoogleKey(jwk.kid),unavailable);
 }
});
test('audience and presenter allowlists are immutable configuration snapshots',async()=>{
 const audiences=['synthetic-client'],authorizedPresenters=['synthetic-presenter'];const p=createGooglePrimaryPorts({...cfg,audiences,authorizedPresenters});
 audiences.push('unreviewed');authorizedPresenters.push('unreviewed');assert.deepEqual(p.audiences,['synthetic-client']);assert.deepEqual(p.authorizedPresenters,['synthetic-presenter']);assert(Object.isFrozen(p.audiences));assert(Object.isFrozen(p.authorizedPresenters));
});
test('trusted timeout is bounded and an OFF adapter still performs no network',async()=>{
 for(const timeoutMs of [0,-1,10001,1.5,NaN])assert.throws(()=>createGooglePrimaryPorts({...cfg,timeoutMs}),unavailable);
 let calls=0;const p=createGooglePrimaryPorts({...cfg,enabled:false,fetcher:async()=>{calls++;throw Error('network forbidden');}});
 await assert.rejects(p.resolveGoogleKey(jwk.kid),unavailable);assert.equal(calls,0);
});
