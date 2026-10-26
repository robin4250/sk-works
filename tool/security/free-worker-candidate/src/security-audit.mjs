const te=new TextEncoder();
export const ZERO='0'.repeat(64);
export const exact=(o,fields)=>o&&typeof o==='object'&&!Array.isArray(o)&&Object.keys(o).sort().join(',')===fields;
export const hex=bytes=>Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('');
export const unhex=s=>Uint8Array.from(s.match(/../g),x=>parseInt(x,16));
export const hash=async text=>hex(await crypto.subtle.digest('SHA-256',te.encode(text)));
export function publicJwk(j){if(!exact(j,'crv,kty,x')||j.kty!=='OKP'||j.crv!=='Ed25519'||!/^[A-Za-z0-9_-]{43}$/.test(j.x))throw Error('Public key rejected');return {kty:'OKP',crv:'Ed25519',x:j.x};}
export const verifyKey=j=>crypto.subtle.importKey('jwk',publicJwk(j),'Ed25519',false,['verify']);
export const signBytes=async(key,domain,body)=>hex(await crypto.subtle.sign('Ed25519',key,te.encode(domain+'\n'+body)));
export async function verified(j,domain,body,signature){if(typeof signature!=='string'||!/^[a-f0-9]{128}$/.test(signature))return false;return crypto.subtle.verify('Ed25519',await verifyKey(j),unhex(signature),te.encode(domain+'\n'+body));}
const one=(s,q,...a)=>s.sql.exec(q,...a).toArray()[0];
export const securityState=s=>one(s,'SELECT * FROM security_state WHERE id=1');
export function initializeSecurity(s,c){
 const p=publicJwk(c.managerJwk),r=publicJwk(c.recoveryJwk),a=publicJwk(c.auditJwk),anchor=publicJwk(c.anchorJwk);
 for(const id of [c.deploymentId,c.ownerId,c.companyId,c.managerKeyId,c.recoveryKeyId,c.auditKeyId,c.anchorKeyId])if(typeof id!=='string'||!/^[a-zA-Z0-9_-]{1,64}$/.test(id))throw Error('Trust identity rejected');
 if(new Set([p.x,r.x,a.x,anchor.x]).size!==4)throw Error('Independent trust keys required');
 return s.transactionSync(()=>{
  s.sql.exec('CREATE TABLE IF NOT EXISTS security_state(id INTEGER PRIMARY KEY CHECK(id=1),deployment_id TEXT NOT NULL,owner_id TEXT NOT NULL,company_id TEXT NOT NULL,manager_key_id TEXT NOT NULL,manager_version INTEGER NOT NULL,manager_jwk TEXT NOT NULL,recovery_key_id TEXT NOT NULL,recovery_jwk TEXT NOT NULL,audit_key_id TEXT NOT NULL,audit_jwk TEXT NOT NULL,anchor_key_id TEXT NOT NULL,anchor_jwk TEXT NOT NULL,trust_revision INTEGER NOT NULL,audit_seq INTEGER NOT NULL,audit_hash TEXT NOT NULL,anchor_seq INTEGER NOT NULL,anchor_hash TEXT NOT NULL,pruned_seq INTEGER NOT NULL,pruned_hash TEXT NOT NULL,prune_body TEXT,prune_signature TEXT,anchor_body TEXT,anchor_signature TEXT,clock INTEGER NOT NULL)');
  s.sql.exec('CREATE TABLE IF NOT EXISTS signed_audit(sequence INTEGER PRIMARY KEY,previous_hash TEXT NOT NULL,hash TEXT NOT NULL,body TEXT NOT NULL,signature TEXT NOT NULL,key_id TEXT NOT NULL,occurred_at INTEGER NOT NULL)');
  s.sql.exec('CREATE TABLE IF NOT EXISTS management_nonces(nonce TEXT PRIMARY KEY,expires INTEGER NOT NULL)');
  const old=securityState(s);if(old){if(old.deployment_id!==c.deploymentId||old.owner_id!==c.ownerId||old.company_id!==c.companyId||old.recovery_key_id!==c.recoveryKeyId||old.audit_key_id!==c.auditKeyId||old.anchor_key_id!==c.anchorKeyId||old.recovery_jwk!==JSON.stringify(r)||old.audit_jwk!==JSON.stringify(a)||old.anchor_jwk!==JSON.stringify(anchor)||(old.manager_version===1&&(old.manager_key_id!==c.managerKeyId||old.manager_jwk!==JSON.stringify(p))))throw Error('Existing trust differs');return old;}
  s.sql.exec('INSERT INTO security_state VALUES(1,?,?,?,?,1,?,?,?,?,?,?,?,1,0,?,0,?,0,?,NULL,NULL,NULL,NULL,0)',c.deploymentId,c.ownerId,c.companyId,c.managerKeyId,JSON.stringify(p),c.recoveryKeyId,JSON.stringify(r),c.auditKeyId,JSON.stringify(a),c.anchorKeyId,JSON.stringify(anchor),ZERO,ZERO,ZERO);return securityState(s);
 });
}
export async function prepareAudit(state,{kind,action,reason,actorId,at,before,after},auditKey){
 if(!Number.isSafeInteger(at)||at<state.clock||!['management','recovery','retention'].includes(kind)||typeof reason!=='string'||reason.length>64)throw Error('Audit input rejected');
 const body=JSON.stringify({v:1,deployment_id:state.deployment_id,sequence:state.audit_seq+1,previous_hash:state.audit_hash,kind,action,reason,actor_id:actorId,company_id:state.company_id,occurred_at:at,before,after});
 if(te.encode(body).length>4096)throw Error('Audit bound');
 const digest=await hash(body),signature=await signBytes(auditKey,'sko-decoy-audit-v1',body);
 if(!await verified(JSON.parse(state.audit_jwk),'sko-decoy-audit-v1',body,signature))throw Error('Audit key differs');
 return {sequence:state.audit_seq+1,previous_hash:state.audit_hash,hash:digest,body,signature,key_id:state.audit_key_id,occurred_at:at};
}
export function appendAuditWithinTransaction(s,expected,row){
 const q=securityState(s);if(q.audit_seq!==expected.audit_seq||q.audit_hash!==expected.audit_hash||q.trust_revision!==expected.trust_revision||row.sequence!==q.audit_seq+1||row.previous_hash!==q.audit_hash)throw Error('Audit CAS rejected');
 if(one(s,'SELECT count(*) AS n FROM signed_audit').n>=1000)throw Error('Audit capacity unavailable');
 s.sql.exec('INSERT INTO signed_audit VALUES(?,?,?,?,?,?,?)',row.sequence,row.previous_hash,row.hash,row.body,row.signature,row.key_id,row.occurred_at);
 s.sql.exec('UPDATE security_state SET audit_seq=?,audit_hash=?,clock=? WHERE id=1',row.sequence,row.hash,row.occurred_at);
}
export async function verifyAuditChain(s,minimumAnchor=null){
 const state=securityState(s);if(!state)throw Error('Audit trust unavailable');
 let seq=state.pruned_seq,previous=state.pruned_hash;
 if(state.audit_seq<state.anchor_seq)throw Error('Anchored audit rollback');
 if(state.anchor_seq>0){if(!state.anchor_body||!await verified(JSON.parse(state.anchor_jwk),'sko-decoy-anchor-v1',state.anchor_body,state.anchor_signature))throw Error('Stored anchor rejected');const a=JSON.parse(state.anchor_body);if(a.sequence!==state.anchor_seq||a.hash!==state.anchor_hash||a.deployment_id!==state.deployment_id)throw Error('Stored anchor differs');}
 if(seq>0){if(!state.prune_body||!await verified(JSON.parse(state.audit_jwk),'sko-decoy-retention-v1',state.prune_body,state.prune_signature))throw Error('Prune proof rejected');const p=JSON.parse(state.prune_body);if(p.deployment_id!==state.deployment_id||p.sequence!==seq||p.hash!==previous||p.sequence>state.anchor_seq)throw Error('Prune marker differs');}
 if(minimumAnchor&&(minimumAnchor.deployment_id!==state.deployment_id||state.audit_seq<minimumAnchor.sequence))throw Error('Independent anchor rollback');
 let anchorFound=!minimumAnchor||minimumAnchor.sequence===seq&&minimumAnchor.hash===previous;
 let storedAnchorFound=state.anchor_seq===seq&&state.anchor_hash===previous;
 const rows=s.sql.exec('SELECT * FROM signed_audit ORDER BY sequence').toArray();
 for(const row of rows){if(row.sequence!==++seq||row.previous_hash!==previous||row.key_id!==state.audit_key_id||await hash(row.body)!==row.hash||!await verified(JSON.parse(state.audit_jwk),'sko-decoy-audit-v1',row.body,row.signature))throw Error('Audit chain rejected');const b=JSON.parse(row.body);if(b.sequence!==row.sequence||b.previous_hash!==previous||b.deployment_id!==state.deployment_id)throw Error('Audit payload differs');previous=row.hash;if(seq===state.anchor_seq)storedAnchorFound=row.hash===state.anchor_hash;if(minimumAnchor&&seq===minimumAnchor.sequence)anchorFound=row.hash===minimumAnchor.hash;}
 if(seq!==state.audit_seq||previous!==state.audit_hash||!anchorFound||!storedAnchorFound)throw Error('Audit head/anchor rejected');return {deployment_id:state.deployment_id,sequence:seq,hash:previous};
}
export async function acceptIndependentAnchor(s,envelope,now){
 const state=securityState(s),p=envelope?.payload;
 if(!exact(envelope,'payload,signature')||!exact(p,'deployment_id,hash,issued_at,key_id,sequence,v')||p.v!==1||p.deployment_id!==state.deployment_id||p.key_id!==state.anchor_key_id||!Number.isSafeInteger(p.sequence)||p.sequence<state.anchor_seq||p.sequence>state.audit_seq||!Number.isSafeInteger(p.issued_at)||p.issued_at>now+30000||!/^[a-f0-9]{64}$/.test(p.hash))throw Error('Anchor rejected');
 const body=JSON.stringify({v:1,deployment_id:p.deployment_id,sequence:p.sequence,hash:p.hash,issued_at:p.issued_at,key_id:p.key_id});
 if(!await verified(JSON.parse(state.anchor_jwk),'sko-decoy-anchor-v1',body,envelope.signature))throw Error('Anchor signature rejected');
 await verifyAuditChain(s);return s.transactionSync(()=>{const q=securityState(s),row=one(s,'SELECT hash FROM signed_audit WHERE sequence=?',p.sequence);const observed=p.sequence===q.pruned_seq?q.pruned_hash:row?.hash;if(q.audit_seq!==state.audit_seq||q.audit_hash!==state.audit_hash||p.sequence<q.anchor_seq||observed!==p.hash)throw Error('Anchor CAS rejected');s.sql.exec('UPDATE security_state SET anchor_seq=?,anchor_hash=?,anchor_body=?,anchor_signature=? WHERE id=1',p.sequence,p.hash,body,envelope.signature);return true;});
}
export async function pruneAnchoredAudit(s,{now,retentionMs=30*86400000,auditKey}){
 if(!Number.isSafeInteger(now)||!Number.isSafeInteger(retentionMs)||retentionMs<86400000||retentionMs>90*86400000)throw Error('Retention rejected');
 await verifyAuditChain(s);const state=securityState(s),row=one(s,'SELECT * FROM signed_audit WHERE occurred_at<? AND sequence<=? ORDER BY sequence DESC LIMIT 1',now-retentionMs,state.anchor_seq);if(!row)return {pruned:0};
 const body=JSON.stringify({v:1,deployment_id:state.deployment_id,sequence:row.sequence,hash:row.hash,cutoff:now-retentionMs,anchored_sequence:state.anchor_seq}),signature=await signBytes(auditKey,'sko-decoy-retention-v1',body);
 if(!await verified(JSON.parse(state.audit_jwk),'sko-decoy-retention-v1',body,signature))throw Error('Retention key differs');
 const audit=await prepareAudit(state,{kind:'retention',action:'prune_anchored_prefix',reason:'retention_expired',actorId:'system_retention',at:now,before:{pruned_sequence:state.pruned_seq},after:{pruned_sequence:row.sequence,anchor_sequence:state.anchor_seq}},auditKey);
 return s.transactionSync(()=>{appendAuditWithinTransaction(s,state,audit);const count=one(s,'SELECT count(*) AS n FROM signed_audit WHERE sequence<=?',row.sequence).n;s.sql.exec('DELETE FROM signed_audit WHERE sequence<=?',row.sequence);s.sql.exec('UPDATE security_state SET pruned_seq=?,pruned_hash=?,prune_body=?,prune_signature=? WHERE id=1',row.sequence,row.hash,body,signature);return {pruned:count};});
}
