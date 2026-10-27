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
});
