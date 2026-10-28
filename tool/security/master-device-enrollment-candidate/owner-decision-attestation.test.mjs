import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign} from 'node:crypto';
import {ownerDecisionPayload,verifyOwnerDecisionAttestation} from './owner-decision-attestation.mjs';
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
function fixture(){
 const {privateKey,publicKey}=generateKeyPairSync('ed25519');
 const request={id:id(1),actor:id(2),requesterSession:id(3),deviceId:id(4),pendingId:id(5),challengeId:id(6),keySha256:'a'.repeat(64),reviewNonce:'b'.repeat(64),createdMs:1000,expiresMs:121000,status:'awaiting_independent_owner',cancelled:false};
 const receipt={version:1,issuerKeyId:'synthetic-owner-issuer',decision:'approved',requestId:request.id,actor:request.actor,requesterSession:request.requesterSession,deviceId:request.deviceId,pendingId:request.pendingId,challengeId:request.challengeId,keySha256:request.keySha256,reviewNonce:request.reviewNonce,issuedMs:2000,expiresMs:62000};
 const signed=value=>({...value,signature:sign(null,ownerDecisionPayload(value),privateKey).toString('base64url')});
 const args={receipt:signed(receipt),request,databaseNowMs:3000,pinnedIssuer:{purpose:'sko-master-independent-owner-decision-v1',keyId:receipt.issuerKeyId,publicKeyJwk:publicKey.export({format:'jwk'})}};
 return {args,receipt,signed,privateKey};
}
test('pinned independent signature binds the exact pending request and decision',()=>{
 const {args,receipt,signed}=fixture(),before=structuredClone(args.request);
 const evidence=verifyOwnerDecisionAttestation(args);assert.equal(evidence.decision,'approved');assert.ok(Object.isFrozen(evidence));assert.match(evidence.attestationSha256,/^[a-f0-9]{64}$/);
 assert.deepEqual(args.request,before,'verification must not approve or activate anything');
 assert.equal(verifyOwnerDecisionAttestation({...args,receipt:signed({...receipt,decision:'denied'})}).decision,'denied');
 for(const key of ['requestId','actor','requesterSession','deviceId','pendingId','challengeId'])assert.equal(verifyOwnerDecisionAttestation({...args,receipt:signed({...receipt,[key]:id(99)})}),null);
 for(const key of ['keySha256','reviewNonce'])assert.equal(verifyOwnerDecisionAttestation({...args,receipt:signed({...receipt,[key]:'c'.repeat(64)})}),null);
 assert.equal(verifyOwnerDecisionAttestation({...args,receipt:{...args.receipt,decision:'denied'}}),null);
});
test('request cancellation, terminal state and expired or future decisions are refused',()=>{
 const {args,receipt,signed}=fixture();
 for(const patch of [{cancelled:true},{status:'cancelled'},{status:'approved'},{expiresMs:2000},{createdMs:2500}])assert.equal(verifyOwnerDecisionAttestation({...args,request:{...args.request,...patch}}),null);
 for(const now of [1999,62000,NaN,-1])assert.equal(verifyOwnerDecisionAttestation({...args,databaseNowMs:now}),null);
 assert.equal(verifyOwnerDecisionAttestation({...args,receipt:signed({...receipt,expiresMs:122000})}),null);
});
test('client-selected signer, private-key input, unknown fields and wrong-purpose trust are refused',()=>{
 const {args,receipt}=fixture(),attacker=generateKeyPairSync('ed25519');
 const forged={...receipt,signature:sign(null,ownerDecisionPayload(receipt),attacker.privateKey).toString('base64url')};
 assert.equal(verifyOwnerDecisionAttestation({...args,receipt:forged}),null);
 assert.equal(verifyOwnerDecisionAttestation({...args,receipt:{...args.receipt,approved:true}}),null);
 let getterCalls=0;const accessor={...args.receipt};Object.defineProperty(accessor,'decision',{enumerable:true,get(){getterCalls++;return 'approved';}});
 assert.equal(verifyOwnerDecisionAttestation({...args,receipt:accessor}),null);assert.equal(getterCalls,0);
 for(const patch of [{purpose:'other'},{keyId:'other'},{publicKeyJwk:attacker.privateKey.export({format:'jwk'})},{publicKeyJwk:{...args.pinnedIssuer.publicKeyJwk,extra:true}}])assert.equal(verifyOwnerDecisionAttestation({...args,pinnedIssuer:{...args.pinnedIssuer,...patch}}),null);
 assert.equal(verifyOwnerDecisionAttestation({...args,receipt:{...args.receipt,signature:args.receipt.signature+'='}}),null);
});
