// In-memory protocol model only. No transport, persistent custody or recovery.
import {createPublicKey, verify} from 'node:crypto';
const hex = x => typeof x === 'string' && /^[a-f0-9]{64}$/.test(x);
const receiptBytes = p => Buffer.from(JSON.stringify({v:p.v,scope:p.scope,challenge:p.challenge,nonce:p.nonce,proposal_hash:p.proposal_hash,sequence:p.sequence,issued:p.issued}));
export {receiptBytes};

// The caller must obtain a fresh, signed response from an independently held
// witness *after* restoring local state. A receipt saved with that state is not
// independent and cannot prove freshness. Consuming is a remote atomic action;
// uncertain responses are held rather than retried as a new operation.
export function validateWitnessReceipt(receipt, {scope,challenge,nonce,proposalHash,key,now,minSequence}) {
  const p=receipt?.payload;
  if (!p || p.v!==1 || p.scope!==scope || p.challenge!==challenge || !hex(challenge) ||
      p.nonce!==nonce || !hex(nonce) || p.proposal_hash!==proposalHash || !hex(proposalHash) ||
      !Number.isSafeInteger(minSequence) || minSequence < 1 || !Number.isSafeInteger(p.sequence) || p.sequence < minSequence ||
      !Number.isSafeInteger(p.issued) || !Number.isSafeInteger(now) || p.issued>now || now-p.issued>30000 ||
      typeof receipt.signature!=='string' || !/^[a-f0-9]{128}$/.test(receipt.signature)) throw Error('witness unavailable');
  try {
    if (!key || key.kty!=='OKP' || key.crv!=='Ed25519' || 'd' in key ||
        !verify(null,receiptBytes(p),createPublicKey({key,format:'jwk'}),Buffer.from(receipt.signature,'hex'))) throw Error();
  } catch { throw Error('witness unavailable'); }
  return {sequence:p.sequence, proposalHash:p.proposal_hash};
}
