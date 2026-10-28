// Synthetic protocol experiment only: no trusted anchor, transport or recovery.
import {createHash,createPublicKey,verify} from 'node:crypto';
const hex=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const keys='challenge,issued,nonce,previous_hash,previous_sequence,proposal_hash,scope,sequence,v';
const exact=p=>p&&typeof p==='object'&&!Array.isArray(p)&&Object.keys(p).sort().join(',')===keys;
export const transitionBytes=p=>Buffer.from('SKO witness transition fixture v1\0'+JSON.stringify({v:p.v,scope:p.scope,challenge:p.challenge,nonce:p.nonce,proposal_hash:p.proposal_hash,previous_sequence:p.previous_sequence,previous_hash:p.previous_hash,sequence:p.sequence,issued:p.issued}));
export const transitionHash=p=>createHash('sha256').update(transitionBytes(p)).digest('hex');
export function validateTransition(receipt,{scope,challenge,nonce,proposalHash,checkpoint,key,now}){
 const p=receipt?.payload;
 if(!exact(p)||p.v!==1||typeof scope!=='string'||!scope||p.scope!==scope||p.challenge!==challenge||!hex(challenge)||p.nonce!==nonce||!hex(nonce)||p.proposal_hash!==proposalHash||!hex(proposalHash)||!checkpoint||!Number.isSafeInteger(checkpoint.sequence)||checkpoint.sequence<0||checkpoint.sequence>=Number.MAX_SAFE_INTEGER||!hex(checkpoint.hash)||p.previous_sequence!==checkpoint.sequence||p.previous_hash!==checkpoint.hash||p.sequence!==checkpoint.sequence+1||!Number.isSafeInteger(p.issued)||!Number.isSafeInteger(now)||p.issued>now||now-p.issued>30000||typeof receipt.signature!=='string'||!/^[a-f0-9]{128}$/.test(receipt.signature))throw Error('transition unavailable');
 try{if(!key||key.kty!=='OKP'||key.crv!=='Ed25519'||'d' in key||!verify(null,transitionBytes(p),createPublicKey({key,format:'jwk'}),Buffer.from(receipt.signature,'hex')))throw Error();}catch{throw Error('transition unavailable');}
 return {sequence:p.sequence,hash:transitionHash(p)};
}
