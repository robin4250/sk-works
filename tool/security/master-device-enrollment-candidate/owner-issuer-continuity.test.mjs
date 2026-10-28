import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash,createPublicKey,generateKeyPairSync,sign,verify} from 'node:crypto';
import {ownerIssuerContinuityPayload,verifyOwnerIssuerContinuity} from './owner-issuer-continuity.mjs';
import {ownerDecisionPayload,verifyOwnerDecisionAttestation} from './owner-decision-attestation.mjs';
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const pair=()=>{const k=generateKeyPairSync('ed25519');return {...k,jwk:k.publicKey.export({format:'jwk'})};};
const checkpoint=pin=>({authorityId:pin.authorityId,epoch:pin.epoch,headSha256:pin.headSha256,keyId:pin.keyId,
 publicKeySha256:createHash('sha256').update(createPublicKey({key:pin.publicKeyJwk,format:'jwk'}).export({type:'spki',format:'der'})).digest('hex')});
function fixture(){
 const old=pair(),next=pair();
 const trusted={purpose:'sko-master-independent-owner-decision-v1',authorityId:id(1),epoch:1,keyId:'issuer_1',publicKeyJwk:old.jwk,headSha256:'a'.repeat(64),retiredKeys:[]};
 const proposal={version:1,authorityId:id(1),fromEpoch:1,toEpoch:2,previousSha256:trusted.headSha256,oldKeyId:'issuer_1',newKeyId:'issuer_2',newPublicKeyJwk:next.jwk,issuedMs:1000,expiresMs:61000,oldSignature:'',newSignature:''};
 const signed=(p=proposal,a=old,b=next)=>{const bytes=ownerIssuerContinuityPayload(p);return {...p,oldSignature:sign(null,bytes,a.privateKey).toString('base64url'),newSignature:sign(null,bytes,b.privateKey).toString('base64url')};};
 return {old,next,trusted,proposal,signed,args:{enabled:true,trusted,authorityCheckpoint:checkpoint(trusted),proposal:signed(),databaseNowMs:2000}};
}
test('default OFF examines no proposed transition and establishes no trust',()=>{
 let calls=0;const proposal={get version(){calls++;return 1;}};
 assert.equal(verifyOwnerIssuerContinuity({proposal}),null);assert.equal(calls,0);
});
test('both external keys authorize exact issuer continuity and preserve signed evidence',()=>{
 const f=fixture(),before=structuredClone(f.args),result=verifyOwnerIssuerContinuity(f.args);
 assert.equal(result.next.epoch,2);assert.deepEqual(result.next.publicKeyJwk,f.next.jwk);
 assert.deepEqual(result.next.retiredKeys,[{epoch:1,keyId:'issuer_1',publicKeyJwk:f.old.jwk}]);
 const payload=Buffer.from(result.evidence.payloadBase64,'base64');
 const oldSig=Buffer.from(result.evidence.oldSignature,'base64url'),newSig=Buffer.from(result.evidence.newSignature,'base64url');
 assert.equal(verify(null,payload,f.old.publicKey,oldSig),true);assert.equal(verify(null,payload,f.next.publicKey,newSig),true);
 assert.equal(createHash('sha256').update(payload).update(oldSig).update(newSig).digest('hex'),result.next.headSha256);
 assert.deepEqual(f.args,before);assert.ok(Object.isFrozen(result.next.retiredKeys[0].publicKeyJwk));
});
test('a missing old key or new possession signature cannot substitute app-owner evidence',()=>{
 const f=fixture(),attacker=pair();
 for(const p of [f.signed(f.proposal,attacker,f.next),f.signed(f.proposal,f.old,attacker),
  {...f.args.proposal,newSignature:f.args.proposal.oldSignature},
  {...f.args.proposal,oldSignature:'x'.repeat(86)},
  {...f.args.proposal,approved:true}])assert.equal(verifyOwnerIssuerContinuity({...f.args,proposal:p}),null);
});
test('authority, monotonic epoch, previous checkpoint and exact key identity are bound',()=>{
 const f=fixture();
 for(const patch of [{authorityId:id(9)},{fromEpoch:2,toEpoch:3},{previousSha256:'b'.repeat(64)},{oldKeyId:'wrong_issuer'}]){
  assert.equal(verifyOwnerIssuerContinuity({...f.args,proposal:f.signed({...f.proposal,...patch})}),null);
 }
 for(const patch of [{toEpoch:3},{fromEpoch:1.5,toEpoch:2.5},{newKeyId:'issuer_1'}])assert.throws(()=>f.signed({...f.proposal,...patch}));
 assert.equal(verifyOwnerIssuerContinuity({...f.args,trusted:{...f.trusted,purpose:'app-owner-evidence'}}),null);
});
test('future, expired, excessive-lifetime and noninteger time proposals are refused',()=>{
 const f=fixture();
 for(const now of [999,61000,NaN,-1,2000.5])assert.equal(verifyOwnerIssuerContinuity({...f.args,databaseNowMs:now}),null);
 for(const patch of [{expiresMs:121001},{issuedMs:-1},{issuedMs:1.5},{expiresMs:1000}])assert.throws(()=>f.signed({...f.proposal,...patch}));
});
test('plain public-only inputs exclude private keys, getters, extra fields and noncanonical signatures',()=>{
 const f=fixture();let called=0;
 const accessor={...f.args.proposal};Object.defineProperty(accessor,'authorityId',{enumerable:true,get(){called++;return id(1);}});
 assert.equal(verifyOwnerIssuerContinuity({...f.args,proposal:accessor}),null);assert.equal(called,0);
 for(const p of [{...f.args.proposal,newPublicKeyJwk:f.next.privateKey.export({format:'jwk'})},
  {...f.args.proposal,newSignature:f.args.proposal.newSignature+'='},
  {...f.args.proposal,newPublicKeyJwk:{...f.next.jwk,extra:true}}])assert.equal(verifyOwnerIssuerContinuity({...f.args,proposal:p}),null);
});
test('subsequent caller metadata mutation cannot rewrite the prepared pin or preserved evidence',()=>{
 const f=fixture(),result=verifyOwnerIssuerContinuity(f.args),before=structuredClone(result);
 f.trusted.publicKeyJwk.x='x'.repeat(43);f.trusted.retiredKeys.push({epoch:99});
 f.args.proposal.newPublicKeyJwk.x='y'.repeat(43);f.args.proposal.newKeyId='attacker';f.args.proposal.oldSignature='z'.repeat(86);
 assert.deepEqual(result,before);
 assert.ok(Object.isFrozen(result.next));assert.ok(Object.isFrozen(result.next.publicKeyJwk));
 assert.ok(Object.isFrozen(result.evidence));
});
test('two verified transitions retain prior keys and reject replay and old-key reuse',()=>{
 const f=fixture(),first=verifyOwnerIssuerContinuity(f.args),third=pair();
 // Serialization preserves key history, but is not proof of durable custody or
 // independent trust. The separate checkpoint still has to be authenticated.
 const nextArgs={...f.args,trusted:JSON.parse(JSON.stringify(first.next)),authorityCheckpoint:checkpoint(first.next)};
 assert.equal(verifyOwnerIssuerContinuity(nextArgs),null,'old transition cannot replay at new head');
 const p={...f.proposal,fromEpoch:2,toEpoch:3,previousSha256:first.next.headSha256,oldKeyId:'issuer_2',newKeyId:'issuer_3',newPublicKeyJwk:third.jwk};
 const second=verifyOwnerIssuerContinuity({...nextArgs,proposal:f.signed(p,f.next,third)});
 assert.equal(second.next.epoch,3);assert.deepEqual(second.next.retiredKeys.map(k=>k.keyId),['issuer_1','issuer_2']);
 for(const patch of [{newKeyId:'issuer_1'},{newPublicKeyJwk:f.old.jwk}])assert.equal(verifyOwnerIssuerContinuity({...nextArgs,proposal:f.signed({...p,...patch},f.next,third)}),null);
 const getterHistory=[...first.next.retiredKeys];Object.defineProperty(getterHistory,'0',{enumerable:true,get(){throw Error('must not execute');}});
 assert.equal(verifyOwnerIssuerContinuity({...nextArgs,trusted:{...first.next,retiredKeys:getterHistory},proposal:f.signed(p,f.next,third)}),null);
});
test('missing or newer authenticated external checkpoint rejects a rolled-back local pin',()=>{
 const f=fixture(),first=verifyOwnerIssuerContinuity(f.args);
 assert.equal(verifyOwnerIssuerContinuity({...f.args,authorityCheckpoint:undefined}),null);
 assert.equal(verifyOwnerIssuerContinuity({...f.args,authorityCheckpoint:checkpoint(first.next)}),null);
 for(const patch of [{authorityId:id(9)},{epoch:2},{headSha256:'b'.repeat(64)},{keyId:'other_issuer'},{publicKeySha256:'b'.repeat(64)}])assert.equal(verifyOwnerIssuerContinuity({...f.args,authorityCheckpoint:{...f.args.authorityCheckpoint,...patch}}),null);
 // Two copies of a stale local snapshot would still satisfy this contract.
 // Only the future authority adapter can prove checkpoint freshness/independence.
});
test('authenticated checkpoint also binds current key bytes despite unchanged local epoch and head',()=>{
 const f=fixture(),attacker=pair();
 const substituted={...f.trusted,publicKeyJwk:attacker.jwk};
 // Both signatures are cryptographically valid under the substituted local pin,
 // but the independently authenticated current-key fingerprint must refuse it.
 assert.equal(verifyOwnerIssuerContinuity({...f.args,trusted:substituted,proposal:f.signed(f.proposal,attacker,f.next)}),null);
});
test('retired keys permit historical cryptographic audit but never current owner-evidence ingestion',()=>{
 const f=fixture(),rotation=verifyOwnerIssuerContinuity(f.args);
 const request={id:id(2),actor:id(3),requesterSession:id(4),deviceId:id(5),pendingId:id(6),challengeId:id(7),keySha256:'c'.repeat(64),reviewNonce:'d'.repeat(64),createdMs:500,expiresMs:61000,status:'awaiting_independent_owner',cancelled:false};
 const r={version:1,issuerKeyId:'issuer_1',decision:'approved',requestId:request.id,actor:request.actor,requesterSession:request.requesterSession,deviceId:request.deviceId,pendingId:request.pendingId,challengeId:request.challengeId,keySha256:request.keySha256,reviewNonce:request.reviewNonce,issuedMs:1000,expiresMs:60000};
 const payload=ownerDecisionPayload(r),signature=sign(null,payload,f.old.privateKey),receipt={...r,signature:signature.toString('base64url')};
 const retired=rotation.next.retiredKeys[0];assert.equal(verify(null,payload,createPublicKey({key:retired.publicKeyJwk,format:'jwk'}),signature),true);
 assert.equal(verifyOwnerDecisionAttestation({receipt,request,databaseNowMs:2000,pinnedIssuer:{purpose:rotation.next.purpose,keyId:rotation.next.keyId,publicKeyJwk:rotation.next.publicKeyJwk}}),null);
});
