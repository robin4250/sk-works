import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync, randomBytes, sign} from 'node:crypto';
import {acceptQrScan} from './qr-scan-coordinator.mjs';
import {qrDeviceSigningBytes, qrTokenHash} from './qr-device-verification.mjs';
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
function fixture(overrides={}) {
  const {privateKey,publicKey}=generateKeyPairSync('ed25519'), rawToken=randomBytes(32).toString('base64url');
  const challenge={companyId:id(1),deviceId:id(2),challengeId:id(3),tokenHash:qrTokenHash(rawToken),action:'clock_out',sourceClockInId:id(4)};
  let state={actor:id(5),session:id(6),sessionActive:true,scannerAuthorized:true,deviceActive:true,subjectActive:true,qrEnabled:true,
    challenge,publicKeyDer:publicKey.export({type:'spki',format:'der'}),nowMs:1000,expiresMs:2000,consumed:false,receiptId:null,...overrides};
  let writes=0, tail=Promise.resolve(), failConsume=false;
  const adapter={runLockedTransaction:run=>{
    const result=tail.then(async()=>{
      const before=structuredClone(state), priorWrites=writes;
      // Synthetic serialized adapter: this is NOT proof of database atomicity.
      try{return await run({loadLockedScan:async()=>state,
        writeRegularAttendance:async()=>{writes++;return id(7);},
        consumeWithReceipt:async({receiptId})=>{if(failConsume)return false;state={...state,consumed:true,receiptId};return true;}});}
      catch(e){state={...before,publicKeyDer:Buffer.from(before.publicKeyDer)};writes=priorWrites;throw e;}
    });tail=result.catch(()=>{});return result;
  }};
  const args={adapter,actor:id(5),session:id(6),challengeId:id(3),rawToken,signature:sign(null,qrDeviceSigningBytes(challenge),privateKey)};
  return {args,set:change=>Object.assign(state,change),get state(){return state;},get writes(){return writes;},fail:()=>{failConsume=true;}};
}
test('concurrent duplicate scans write normal attendance once and return same receipt',async()=>{
  const f=fixture();const results=await Promise.all(Array.from({length:8},()=>acceptQrScan(f.args)));
  assert.equal(f.writes,1);assert.equal(results.filter(x=>!x.alreadyRecorded).length,1);
  assert.ok(results.every(x=>x.receiptId===id(7)));
  f.set({nowMs:3000});assert.deepEqual(await acceptQrScan(f.args),{receiptId:id(7),alreadyRecorded:true});assert.equal(f.writes,1);
});
test('failed consume rolls attendance and nonce back together',async()=>{
  const f=fixture();f.fail();await assert.rejects(acceptQrScan(f.args),/not_accepted/);
  assert.equal(f.writes,0);assert.equal(f.state.consumed,false);assert.equal(f.state.receiptId,null);
});
test('current session/device/subject/authorization and gate are required even for receipt retry',async()=>{
  for(const change of [{sessionActive:false},{scannerAuthorized:false},{deviceActive:false},{subjectActive:false},{qrEnabled:false},{actor:id(8)},{session:id(8)}]){
    const f=fixture();await acceptQrScan(f.args);f.set(change);await assert.rejects(acceptQrScan(f.args),/not_accepted/);assert.equal(f.writes,1);
  }
});
test('expired fresh challenge and substituted token, signature, scope or consumed state fail before write',async()=>{
  for(const mutation of [f=>f.set({nowMs:2000}),f=>{f.args.rawToken=randomBytes(32).toString('base64url');},
    f=>{f.args.signature=Buffer.alloc(64);},f=>f.set({challenge:{...f.state.challenge,companyId:id(8)}}),
    f=>f.set({consumed:null}),f=>f.set({consumed:true}),f=>f.set({receiptId:id(7)})]){
    const f=fixture();mutation(f);await assert.rejects(acceptQrScan(f.args));assert.equal(f.writes,0);
  }
});
test('signature is copied before asynchronous adapter work',async()=>{
  const f=fixture(), original=f.args.adapter;
  f.args.adapter={runLockedTransaction:async run=>{f.args.signature.fill(0);return original.runLockedTransaction(run);}};
  assert.equal((await acceptQrScan(f.args)).alreadyRecorded,false);
});
