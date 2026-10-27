// Isolated recovery PROPOSAL ledger. No authority key or production data changed.
// Two independently held recovery and witness keys MUST be provisioned safely
// before a key loss; neither independence nor actual owner identity is proven.
import {latestIndependentAnchor} from './anchor-authority.mjs';
import {publicJwk,exact,verified} from './security-audit.mjs';
const one=(s,q,...a)=>s.sql.exec(q,...a).toArray()[0];
const id=x=>typeof x==='string'&&/^[A-Za-z0-9_-]{1,64}$/.test(x);
const hex=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const domain='sko-anchor-recovery-proposal-fixture-v1';
export function initializeRecoveryProposalFixture(s,{recoveryKeyId,recoveryJwk,witnessKeyId,witnessJwk}){
 const q=one(s,'SELECT * FROM anchor_authority WHERE id=1');if(!q||!id(recoveryKeyId)||!id(witnessKeyId))throw Error('recovery unavailable');
 const recovery=publicJwk(recoveryJwk),witness=publicJwk(witnessJwk),known=[JSON.parse(q.anchor_jwk).x,JSON.parse(q.audit_jwk).x,recovery.x,witness.x];
 if(new Set(known).size!==4||new Set([q.anchor_key_id,q.audit_key_id,recoveryKeyId,witnessKeyId]).size!==4)throw Error('independent keys required');
 return s.transactionSync(()=>{s.sql.exec('CREATE TABLE IF NOT EXISTS recovery_proposal_config(id INTEGER PRIMARY KEY CHECK(id=1),recovery_key_id TEXT NOT NULL,recovery_jwk TEXT NOT NULL,witness_key_id TEXT NOT NULL,witness_jwk TEXT NOT NULL)');s.sql.exec('CREATE TABLE IF NOT EXISTS recovery_proposals(nonce TEXT PRIMARY KEY,proposal TEXT NOT NULL,recovery_signature TEXT NOT NULL,witness_signature TEXT NOT NULL,new_signature TEXT NOT NULL)');
  const old=one(s,'SELECT * FROM recovery_proposal_config WHERE id=1'),r=JSON.stringify(recovery),w=JSON.stringify(witness);if(old){if(old.recovery_key_id!==recoveryKeyId||old.recovery_jwk!==r||old.witness_key_id!==witnessKeyId||old.witness_jwk!==w)throw Error('existing trust differs');return true;}
  s.sql.exec('INSERT INTO recovery_proposal_config VALUES(1,?,?,?,?)',recoveryKeyId,r,witnessKeyId,w);return true;});
}
export async function stageRecoveryProposalFixture(s,{proposal,recoverySignature,witnessSignature,newSignature,now}){
 const q=one(s,'SELECT * FROM anchor_authority WHERE id=1'),trust=one(s,'SELECT * FROM recovery_proposal_config WHERE id=1');if(!q||!trust)throw Error('recovery unavailable');await latestIndependentAnchor(s);
 if(!exact(proposal,'checkpoint_hash,checkpoint_sequence,company_id,deployment_id,expires,issued,new_jwk,new_key_id,nonce,old_key_id,v')||proposal.v!==1||proposal.company_id!==q.company_id||proposal.deployment_id!==q.deployment_id||proposal.old_key_id!==q.anchor_key_id||proposal.checkpoint_sequence!==q.sequence||proposal.checkpoint_hash!==q.hash||q.sequence<1||!id(proposal.new_key_id)||!hex(proposal.nonce)||!Number.isSafeInteger(now)||!Number.isSafeInteger(proposal.issued)||!Number.isSafeInteger(proposal.expires)||proposal.issued>now||proposal.expires<now||proposal.expires-proposal.issued>30000||proposal.issued<q.clock)throw Error('recovery proposal rejected');
 const key=publicJwk(proposal.new_jwk),known=[JSON.parse(q.anchor_jwk).x,JSON.parse(q.audit_jwk).x,JSON.parse(trust.recovery_jwk).x,JSON.parse(trust.witness_jwk).x,key.x];
 if(new Set(known).size!==5||[q.anchor_key_id,q.audit_key_id,trust.recovery_key_id,trust.witness_key_id].includes(proposal.new_key_id))throw Error('recovery proposal rejected');
 const body=JSON.stringify(proposal);
 if(!await verified(JSON.parse(trust.recovery_jwk),domain,body,recoverySignature)||!await verified(JSON.parse(trust.witness_jwk),domain,body,witnessSignature)||!await verified(key,domain,body,newSignature))throw Error('recovery proof rejected');
 return s.transactionSync(()=>{const current=one(s,'SELECT * FROM anchor_authority WHERE id=1'),t=one(s,'SELECT * FROM recovery_proposal_config WHERE id=1');if(JSON.stringify(current)!==JSON.stringify(q)||JSON.stringify(t)!==JSON.stringify(trust))throw Error('authority changed');if(one(s,'SELECT count(*) AS n FROM recovery_proposals').n>=100)throw Error('proposal capacity');
  s.sql.exec('INSERT INTO recovery_proposals VALUES(?,?,?,?,?)',proposal.nonce,body,recoverySignature,witnessSignature,newSignature);return {staged:true,applied:false};});
}
