// Synthetic Node-only experiment. Never use for production custody or recovery.
import {createPublicKey,verify} from 'node:crypto';
const hash=/^[a-f0-9]{64}$/;
function canonical(x){return Buffer.from(JSON.stringify({v:x.v,scope:x.scope,nonce:x.nonce,sequence:x.sequence,hash:x.hash,issued:x.issued,key_epoch:x.key_epoch}));}
function rotationBytes(x){return Buffer.from(JSON.stringify({v:x.v,scope:x.scope,from_epoch:x.from_epoch,to_epoch:x.to_epoch,checkpoint_sequence:x.checkpoint_sequence,checkpoint_hash:x.checkpoint_hash,new_key:x.new_key}));}
function pub(k){if(!k||k.kty!=='OKP'||k.crv!=='Ed25519'||typeof k.x!=='string'||Object.hasOwn(k,'d'))throw Error('bad key');return createPublicKey({key:k,format:'jwk'});}
function signature(k,b,s){try{return typeof s==='string'&&/^[a-f0-9]{128}$/.test(s)&&verify(null,b,pub(k),Buffer.from(s,'hex'));}catch{return false;}}
export function verifyHead(response,{scope,nonce,now,checkpoint,key,keyEpoch}){
 const p=response?.payload;
 if(!p||p.v!==1||p.scope!==scope||p.nonce!==nonce||!hash.test(nonce)||p.key_epoch!==keyEpoch||!Number.isSafeInteger(p.issued)||!Number.isSafeInteger(now)||p.issued>now||now-p.issued>30000||!Number.isSafeInteger(p.sequence)||p.sequence<checkpoint.sequence||!hash.test(p.hash)||!signature(key,canonical(p),response.signature))throw Error('head rejected');
 if(p.sequence===checkpoint.sequence&&p.hash!==checkpoint.hash)throw Error('fork');
 return {sequence:p.sequence,hash:p.hash};
}
export function verifyRotation(proposal,{scope,checkpoint,oldKey,oldEpoch}){
 const p=proposal?.payload;
 if(!p||p.v!==1||p.scope!==scope||p.from_epoch!==oldEpoch||p.to_epoch!==oldEpoch+1||p.checkpoint_sequence!==checkpoint.sequence||p.checkpoint_hash!==checkpoint.hash||!p.new_key||p.new_key.x===oldKey.x)throw Error('rotation rejected');
 const bytes=rotationBytes(p);
 if(!signature(oldKey,bytes,proposal.old_signature)||!signature(p.new_key,bytes,proposal.new_signature))throw Error('rotation rejected');
 return {key:p.new_key,keyEpoch:p.to_epoch};
}
export {canonical,rotationBytes};
