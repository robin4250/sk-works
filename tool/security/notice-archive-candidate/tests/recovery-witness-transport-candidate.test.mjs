import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign} from 'node:crypto';
import {receiptBytes} from '../src/recovery-witness-model.mjs';
import {requestWitnessReceipt} from '../src/recovery-witness-transport-candidate.mjs';
const keys=generateKeyPairSync('ed25519');
const options={endpoint:'https://witness.invalid/receipt',bearer:'synthetic-bearer-only',key:keys.publicKey.export({format:'jwk'}),operation:'consume',scope:'fixture',nonce:'a'.repeat(64),proposalHash:'b'.repeat(64),minSequence:1,now:()=>1000};
const signed=(body)=>{const p={v:1,scope:body.scope,nonce:body.nonce,proposal_hash:body.proposalHash,challenge:body.challenge,sequence:1,issued:1000};return {payload:p,signature:sign(null,receiptBytes(p),keys.privateKey).toString('hex')};};
test('one authenticated bounded request verifies a fresh signed challenge',async()=>{
  const challenges=[];
  const fetchImpl=async(url,init)=>{assert.equal(url,options.endpoint);assert.equal(init.redirect,'error');assert.equal(init.headers.authorization,'Bearer synthetic-bearer-only');const body=JSON.parse(init.body);challenges.push(body.challenge);return Response.json(signed(body));};
  assert.equal((await requestWitnessReceipt({...options,fetchImpl})).sequence,1);
  await requestWitnessReceipt({...options,operation:'lookup',fetchImpl});
  assert.notEqual(challenges[0],challenges[1]);
});
test('uncertain consume never retries and does not expose remote error or credential',async()=>{
  let calls=0;await assert.rejects(requestWitnessReceipt({...options,fetchImpl:async()=>{calls++;throw Error(options.bearer);}}),{message:'witness outcome unknown; reconcile before retry'});assert.equal(calls,1);
});
test('redirect, oversized streaming data and invalid signed receipts are refused',async()=>{
  for(const fetchImpl of [async()=>new Response('',{status:302}),async()=>new Response('x'.repeat(8193),{headers:{'content-type':'application/json'}}),async()=>Response.json({payload:{},signature:'0'.repeat(128)})])await assert.rejects(requestWitnessReceipt({...options,fetchImpl}));
  await assert.rejects(requestWitnessReceipt({...options,endpoint:'http://witness.invalid',fetchImpl:()=>{throw Error('must not call');}}));
});

test('deadline settles an uncooperative fetch without retry',async()=>{
  let calls=0;
  await assert.rejects(requestWitnessReceipt({...options,timeoutMs:10,fetchImpl:()=>{calls++;return new Promise(()=>{});}}),{message:'witness outcome unknown; reconcile before retry'});
  assert.equal(calls,1);
});
test('deadline settles a stalled reader even when cancellation does not finish',async()=>{
  let cancelled=0,released=0;
  const reader={read:()=>new Promise(()=>{}),cancel:()=>{cancelled++;return new Promise(()=>{});},releaseLock:()=>{released++;}};
  const fetchImpl=async()=>({ok:true,redirected:false,url:options.endpoint,headers:new Headers({'content-type':'application/json'}),body:{getReader:()=>reader}});
  await assert.rejects(requestWitnessReceipt({...options,timeoutMs:10,fetchImpl}),{message:'witness outcome unknown; reconcile before retry'});
  assert.equal(cancelled,1);assert.equal(released,1);
});
