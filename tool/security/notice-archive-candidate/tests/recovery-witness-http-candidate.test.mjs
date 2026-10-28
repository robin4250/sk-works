import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {TestWitness} from './recovery-witness-sqlite-fixture.mjs';
import {createWitnessHttpCandidate} from '../src/recovery-witness-http-candidate.mjs';
import {requestWitnessReceipt} from '../src/recovery-witness-transport-candidate.mjs';
const keys=generateKeyPairSync('ed25519'),key=keys.publicKey.export({format:'jwk'});
const config={endpoint:'https://witness.invalid/receipt',bearer:'synthetic-witness-credential',scopes:['fixture'],key,now:()=>1000};
const body={operation:'consume',scope:'fixture',nonce:'a'.repeat(64),proposalHash:'b'.repeat(64),challenge:'c'.repeat(64)};
const req=(data=body,options={})=>new Request(config.endpoint,{method:'POST',headers:{authorization:`Bearer ${config.bearer}`,'content-type':'application/json'},body:JSON.stringify(data),...options});
const temporary=()=>{const directory=mkdtempSync(join(tmpdir(),'witness-http-'));const witness=new TestWitness(join(directory,'ledger.db'),keys.privateKey);return {witness,close(){witness.close();rmSync(directory,{recursive:true,force:true});}};};
test('client and HTTP boundary use one durable consumption and explicit fresh lookup',async()=>{
  const fixture=temporary();try{
    let calls=0;
    const handler=createWitnessHttpCandidate({...config,authority:{consume:args=>{calls++;return fixture.witness.consume(args);},lookup:args=>fixture.witness.lookup(args)}});
    const fetchImpl=(url,init)=>handler(new Request(url,init));
    const options={...config,scope:'fixture',nonce:body.nonce,proposalHash:body.proposalHash,minSequence:1,fetchImpl};
    assert.equal((await requestWitnessReceipt({...options,operation:'consume'})).sequence,1);
    assert.equal((await requestWitnessReceipt({...options,operation:'lookup'})).sequence,1);
    await assert.rejects(requestWitnessReceipt({...options,operation:'consume'}));
    assert.equal(calls,2);assert.equal(fixture.witness.db.prepare('select count(*) n from consumed').get().n,1);
  }finally{fixture.close();}
});
test('lost commit response is held, not repeated, and can be reconciled with lookup',async()=>{
  const fixture=temporary();try{
    let calls=0;
    const handler=createWitnessHttpCandidate({...config,authority:{consume:args=>{calls++;return fixture.witness.consume({...args,loseAfterCommit:true});},lookup:args=>fixture.witness.lookup(args)}});
    const first=await handler(req());assert.equal(first.status,503);assert.equal(calls,1);
    assert.equal((await handler(req({...body,operation:'lookup',challenge:'d'.repeat(64)}))).status,200);
    assert.equal(calls,1);
  }finally{fixture.close();}
});
test('authentication, exact endpoint, operation scope and bounded fields precede authority',async()=>{
  let calls=0;const handler=createWitnessHttpCandidate({...config,authority:{consume(){calls++;},lookup(){calls++;}}});
  assert.equal((await handler(req(body,{headers:{'content-type':'application/json',authorization:'Bearer incorrect'}}))).status,401);
  assert.equal((await handler(new Request(config.endpoint+'?query=1',{method:'POST'}))).status,404);
  for(const input of [{...body,scope:'other'},{...body,actor:'forged'},{...body,nonce:'bad'},{...body,operation:'reset'},{...body,scope:'x'.repeat(3000)}])assert.equal((await handler(req(input))).status,400);
  assert.equal(calls,0);
});
test('untrusted authority errors or unsigned receipts do not leak content',async()=>{
  for(const result of [()=>{throw Error(config.bearer);},()=>({payload:{},signature:'0'.repeat(128)})]){
    const handler=createWitnessHttpCandidate({...config,authority:{consume:result,lookup:result}});
    const response=await handler(req());assert.equal(response.status,503);
    assert.equal(response.headers.get('cache-control'),'no-store');assert.equal((await response.text()).includes(config.bearer),false);
  }
});
test('authority and body deadlines settle without cancellation or automatic retry',async()=>{
  let calls=0;const handler=createWitnessHttpCandidate({...config,timeoutMs:10,authority:{consume(){calls++;return new Promise(()=>{});},lookup(){throw Error('must not call');}}});
  assert.equal((await handler(req())).status,503);assert.equal(calls,1);
  const stalled=new ReadableStream({pull(){return new Promise(()=>{});},cancel(){return new Promise(()=>{});}});
  const request=new Request(config.endpoint,{method:'POST',headers:{authorization:`Bearer ${config.bearer}`,'content-type':'application/json'},body:stalled,duplex:'half'});
  assert.equal((await handler(request)).status,503);assert.equal(calls,1);
});
