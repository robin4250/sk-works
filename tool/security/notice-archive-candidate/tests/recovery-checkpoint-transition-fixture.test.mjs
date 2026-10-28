import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,randomBytes,sign} from 'node:crypto';
import {transitionBytes,transitionHash,validateTransition} from '../src/recovery-checkpoint-transition-fixture.mjs';
const token=()=>randomBytes(32).toString('hex');
test('signed transition binds the separately trusted exact previous checkpoint',()=>{
 const pair=generateKeyPairSync('ed25519'),checkpoint={sequence:3,hash:token()},challenge=token(),nonce=token(),proposalHash=token();
 const context={scope:'synthetic',checkpoint,challenge,nonce,proposalHash,now:1000,key:pair.publicKey.export({format:'jwk'})};
 const payload={v:1,scope:context.scope,challenge,nonce,proposal_hash:proposalHash,previous_sequence:3,previous_hash:checkpoint.hash,sequence:4,issued:1000};
 const signed=p=>({payload:p,signature:sign(null,transitionBytes(p),pair.privateKey).toString('hex')});
 assert.deepEqual(validateTransition(signed(payload),context),{sequence:4,hash:transitionHash(payload)});
 for(const p of [{...payload,previous_hash:token()},{...payload,previous_sequence:2},{...payload,sequence:5},{...payload,challenge:token()},{...payload,scope:'other'}])assert.throws(()=>validateTransition(signed(p),context),/unavailable/);
 assert.throws(()=>validateTransition(signed(payload),{...context,now:31001}),/unavailable/);
 assert.throws(()=>validateTransition(signed(payload),{...context,checkpoint:{sequence:3,hash:token()}}),/unavailable/);
 // Unknown fields must not be interpreted by a future consumer even if the
 // signature was produced over the known subset. Signatures are also scoped
 // to this protocol; a signature over bare canonical JSON is not accepted.
 assert.throws(()=>validateTransition(signed({...payload,role:'administrator'}),context),/unavailable/);
 const bare=Buffer.from(JSON.stringify(payload));
 assert.throws(()=>validateTransition({payload,signature:sign(null,bare,pair.privateKey).toString('hex')},context),/unavailable/);
});
test('stateless signed transition verification alone cannot prevent concurrent replay',()=>{
 const pair=generateKeyPairSync('ed25519'),checkpoint={sequence:0,hash:token()},challenge=token(),nonce=token(),proposalHash=token();
 const context={scope:'synthetic',checkpoint,challenge,nonce,proposalHash,now:1000,key:pair.publicKey.export({format:'jwk'})};
 const payload={v:1,scope:context.scope,challenge,nonce,proposal_hash:proposalHash,previous_sequence:0,previous_hash:checkpoint.hash,sequence:1,issued:1000};
 const receipt={payload,signature:sign(null,transitionBytes(payload),pair.privateKey).toString('hex')};
 // Two callers sharing the same stale trusted checkpoint both pass: atomic
 // compare-and-set of separately held checkpoint and nonce is mandatory.
 assert.deepEqual(validateTransition(receipt,context),validateTransition(receipt,context));
});
