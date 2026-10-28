import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {mkdtempSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createExternalSignerWitnessCandidate} from '../src/recovery-witness-external-signer-candidate.mjs';
import {validateWitnessReceipt} from '../src/recovery-witness-model.mjs';

const keys=generateKeyPairSync('ed25519'),key=keys.publicKey.export({format:'jwk'});
const input={scope:'synthetic',nonce:'a'.repeat(64),proposalHash:'b'.repeat(64),challenge:'c'.repeat(64)};
const committed=()=>({committed:true,scope:input.scope,nonce:input.nonce,proposalHash:input.proposalHash,sequence:1});
test('commit precedes external signing and lost signing response reconciles by lookup without reconsume',async()=>{
  let used=false,consumes=0,signs=0,lose=true;
  const store={consumeCommitted:async()=>{consumes++;assert.equal(used,false);used=true;return committed();},readCommitted:async()=>{assert.equal(used,true);return committed();}};
  const witness=createExternalSignerWitnessCandidate({store,key,now:()=>1000,signReceipt:async bytes=>{signs++;assert.equal(used,true);if(lose)throw Error('synthetic key provider unavailable');return sign(null,bytes,keys.privateKey);}});
  await assert.rejects(witness.consume(input),/outcome unknown/);assert.equal(consumes,1);assert.equal(signs,1);
  lose=false;const receipt=await witness.lookup({...input,challenge:'d'.repeat(64)});
  assert.equal(validateWitnessReceipt(receipt,{...input,challenge:'d'.repeat(64),key,now:1000,minSequence:1}).sequence,1);
  assert.equal(consumes,1);assert.equal(signs,2);
});
test('uncommitted or substituted ledger rows never reach signer; foreign signature and mutated signer bytes reject',async()=>{
  let signs=0,row=committed();const store={consumeCommitted:async()=>row,readCommitted:async()=>row};
  const witness=createExternalSignerWitnessCandidate({store,key,now:()=>1000,signReceipt:async bytes=>{signs++;return sign(null,bytes,keys.privateKey);}});
  for(const altered of [{...row,committed:false},{...row,scope:'other'},{...row,nonce:'d'.repeat(64)},{...row,proposalHash:'e'.repeat(64)},{...row,sequence:0}]){
    row=altered;await assert.rejects(witness.consume(input));
  }
  assert.equal(signs,0);row=committed();
  const foreign=generateKeyPairSync('ed25519');
  await assert.rejects(createExternalSignerWitnessCandidate({store,key,now:()=>1000,signReceipt:bytes=>sign(null,bytes,foreign.privateKey)}).consume(input));
  await assert.rejects(createExternalSignerWitnessCandidate({store,key,now:()=>1000,signReceipt:bytes=>{bytes.fill(0);return sign(null,bytes,keys.privateKey);}}).consume(input));
});
test('input, ledger and key mutations during async signing cannot change the receipt binding',async()=>{
  let release,entered;const waiting=new Promise(r=>{entered=r;}),gate=new Promise(r=>{release=r;});
  const row=committed(),mutable={...input},pin={...key};
  const witness=createExternalSignerWitnessCandidate({store:{consumeCommitted:async()=>row,readCommitted:async()=>row},key:pin,now:()=>1000,signReceipt:async bytes=>{entered();await gate;return sign(null,bytes,keys.privateKey);}});
  const pending=witness.consume(mutable);await waiting;mutable.scope='other';row.sequence=9;pin.x=generateKeyPairSync('ed25519').publicKey.export({format:'jwk'}).x;release();
  const receipt=await pending;assert.equal(receipt.payload.scope,input.scope);assert.equal(receipt.payload.sequence,1);
});
test('store or signer timeout does not retry or leak secret failure text; private keys are refused',async()=>{
  let consumes=0,signs=0;const store={consumeCommitted:()=>{consumes++;return new Promise(()=>{});},readCommitted:async()=>committed()};
  const witness=createExternalSignerWitnessCandidate({store,key,timeoutMs:20,signReceipt:()=>{signs++;return new Uint8Array(64);}});
  await assert.rejects(witness.consume(input),e=>e.message==='witness outcome unknown; reconcile before retry');assert.equal(consumes,1);assert.equal(signs,0);
  await assert.rejects(createExternalSignerWitnessCandidate({store:{...store,consumeCommitted:async()=>committed()},key,timeoutMs:20,signReceipt:()=>new Promise(()=>{})}).consume(input),/outcome unknown/);
  assert.throws(()=>createExternalSignerWitnessCandidate({store,key:keys.privateKey.export({format:'jwk'}),signReceipt:()=>new Uint8Array(64)}),/invalid witness signer configuration/);
});
test('file-backed committed nonce survives restart after signer failure, while lookup uses a fresh challenge',async()=>{
  const directory=mkdtempSync(join(tmpdir(),'witness-external-signer-'));
  let db;
  // Test-only ledger. It is local SQLite, not rollback-resistant independent custody.
  const open=()=>{
    db=new DatabaseSync(join(directory,'ledger.db'));
    db.exec('CREATE TABLE IF NOT EXISTS consumed(scope TEXT NOT NULL,nonce TEXT NOT NULL,proposal_hash TEXT NOT NULL,sequence INTEGER NOT NULL,PRIMARY KEY(scope,nonce))');
    const readCommitted=({scope,nonce,proposalHash})=>{
      const row=db.prepare('SELECT proposal_hash,sequence FROM consumed WHERE scope=? AND nonce=?').get(scope,nonce);
      if(!row||row.proposal_hash!==proposalHash)throw Error('unavailable');
      return {committed:true,scope,nonce,proposalHash,sequence:row.sequence};
    };
    return {readCommitted,consumeCommitted:args=>{
      db.exec('BEGIN IMMEDIATE');
      try{
        const sequence=db.prepare('SELECT coalesce(max(sequence),0)+1 n FROM consumed').get().n;
        db.prepare('INSERT INTO consumed VALUES(?,?,?,?)').run(args.scope,args.nonce,args.proposalHash,sequence);
        db.exec('COMMIT');
      }catch(e){db.exec('ROLLBACK');throw e;}
      return readCommitted(args);
    }};
  };
  try{
    const first=createExternalSignerWitnessCandidate({store:open(),key,now:()=>1000,signReceipt:()=>{throw Error('synthetic signer failure');}});
    await assert.rejects(first.consume(input),/outcome unknown/);db.close();
    const restarted=createExternalSignerWitnessCandidate({store:open(),key,now:()=>1001,signReceipt:bytes=>sign(null,bytes,keys.privateKey)});
    await assert.rejects(restarted.consume(input),/outcome unknown/);
    const receipt=await restarted.lookup({...input,challenge:'d'.repeat(64)});
    assert.equal(validateWitnessReceipt(receipt,{...input,challenge:'d'.repeat(64),key,now:1001,minSequence:1}).sequence,1);
    assert.equal(db.prepare('SELECT count(*) n FROM consumed').get().n,1);
  }finally{db?.close();rmSync(directory,{recursive:true,force:true});}
});
