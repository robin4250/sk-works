import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign,randomUUID} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {Miniflare,Log,LogLevel} from 'miniflare';
const root=resolve(import.meta.dirname,'..'),zero='0'.repeat(64);
function keys(){const p=generateKeyPairSync('ed25519'),j=p.publicKey.export({format:'jwk'});return {private:p.privateKey,jwk:{kty:j.kty,crv:j.crv,x:j.x},privateJwk:p.privateKey.export({format:'jwk'})};}
function signature(key,domain,payload){return sign(null,Buffer.from(domain+'\n'+JSON.stringify(payload)),key).toString('hex');}
async function fixture(t){
 const manager=keys(),recovery=keys(),audit=keys(),anchor=keys(),dir=await mkdtemp(join(tmpdir(),'sko-management-'));
 const options={modules:true,scriptPath:join(root,'tests/management-fixture.mjs'),modulesRoot:root,modulesRules:[{type:'CompiledWasm',include:['**/*.wasm']}],compatibilityDate:'2026-07-30',durableObjects:{DECOY:{className:'ManagementFixture',useSQLite:true}},durableObjectsPersist:dir,bindings:{FIXTURE_AUDIT_PRIVATE:JSON.stringify(audit.privateJwk)},log:new Log(LogLevel.ERROR)};
 let mf=new Miniflare(options);t.after(async()=>{await mf.dispose();await rm(dir,{recursive:true,force:true});});
 const call=async(path,data)=>{const ns=await mf.getDurableObjectNamespace('DECOY');return ns.get(ns.idFromName('security-management')).fetch('https://fixture.invalid'+path,data===undefined?{}:{method:'POST',body:JSON.stringify(data)});};
 const config={deploymentId:'deployment_1',ownerId:'owner_1',companyId:'company_1',managerKeyId:'manager_1',recoveryKeyId:'recovery_1',auditKeyId:'audit_1',anchorKeyId:'anchor_1',managerJwk:manager.jwk,recoveryJwk:recovery.jwk,auditJwk:audit.jwk,anchorJwk:anchor.jwk};
 assert.equal((await call('/initialize',config)).status,200);
 const snapshot=async()=> (await call('/snapshot')).json();
 async function command(action='quarantine',patch={},key=manager.private){const s=await snapshot(),now=Date.now(),p={v:1,kind:'management',key_id:s.security.manager_key_id,key_version:s.security.manager_version,deployment_id:config.deploymentId,subject:config.ownerId,company_id:config.companyId,action,reason:'operator_review',expected_policy_revision:s.policy.revision,expected_trust_revision:s.security.trust_revision,nonce:randomUUID(),issued_at:now,expires_at:now+60000,...patch};return {envelope:{payload:p,signature:signature(key,'sko-decoy-management-v1',p)},now};}
 async function pin(){const state=await snapshot(),now=Date.now(),head={deployment_id:config.deploymentId,sequence:state.security.audit_seq,hash:state.security.audit_hash};const p={v:1,...head,issued_at:now,key_id:config.anchorKeyId};assert.equal((await call('/anchor',{envelope:{payload:p,signature:signature(anchor.private,'sko-decoy-anchor-v1',p)},now})).status,200);return head;}
 return {call,snapshot,command,pin,manager,recovery,audit,anchor,config,restart:async()=>{await mf.dispose();mf=new Miniflare(options);}};
}
test('signed exact owner/company/deployment/action capability changes policy with one nonce and signed audit',async t=>{
 const f=await fixture(t),c=await f.command('quarantine');assert.equal((await f.call('/command',c)).status,200);const s=await f.snapshot();assert.equal(s.policy.quarantined,1);assert.equal(s.nonces.length,1);assert.equal(s.signed.length,1);assert.equal((await f.call('/verify',{})).status,200);assert.equal((await f.call('/command',c)).status,409);
});
test('other owner/company/deployment, expired/future, extra fields and wrong signing key are refused without writes',async t=>{
 const f=await fixture(t),before=await f.snapshot();
 for(const patch of [{subject:'other'},{company_id:'other'},{deployment_id:'other'},{action:'grant_database_admin'},{issued_at:Date.now()+60000},{expires_at:Date.now()-1},{unexpected:true}])assert.equal((await f.call('/command',await f.command('quarantine',patch))).status,409);
 assert.equal((await f.call('/command',await f.command('quarantine',{},keys().private))).status,409);assert.deepEqual(await f.snapshot(),before);
});
test('concurrent verified commands CAS once and actual signed-audit SQL failure rolls back nonce and policy',async t=>{
 const f=await fixture(t),a=await f.command('quarantine'),b=await f.command('rotate'),rs=await Promise.all([f.call('/command',a),f.call('/command',b)]);assert.deepEqual(rs.map(x=>x.status).sort(),[200,409]);assert.equal((await f.snapshot()).signed.length,1);
 const before=await f.snapshot();await f.call('/fail-signed-audit',{});assert.equal((await f.call('/command',await f.command('release',{reason:'false_positive'}))).status,409);assert.deepEqual(await f.snapshot(),before);
});
test('false-positive release uses a newer epoch instead of restoring an old policy',async t=>{
 const f=await fixture(t);await f.call('/command',await f.command('quarantine'));const a=await f.snapshot();assert.equal((await f.call('/command',await f.command('release',{reason:'false_positive'}))).status,200);const b=await f.snapshot();assert.equal(b.policy.quarantined,0);assert.equal(b.policy.epoch,a.policy.epoch+1);assert.equal(b.signed.length,2);assert.equal((await f.call('/verify',{})).status,200);
});
test('signed audit tampering is detected by real Workers Ed25519 verification',async t=>{
 const f=await fixture(t);await f.call('/command',await f.command());const s=await f.snapshot();await f.call('/tamper-body',{sequence:1,body:s.signed[0].body.replace('quarantine','release')});assert.equal((await f.call('/verify',{})).status,409);assert.equal((await f.call('/command',await f.command())).status,409);
});
test('independently signed anchor detects durable rollback after workerd restart',async t=>{
 const f=await fixture(t);await f.call('/command',await f.command());const anchor=await f.pin();await f.restart();assert.equal((await f.call('/verify',{minimumAnchor:anchor})).status,200);await f.call('/truncate',{sequence:0,hash:zero});assert.equal((await f.call('/verify',{minimumAnchor:anchor})).status,409);
});
test('independent recovery key rotates manager key only while leaving admission OFF and old key rejected',async t=>{
 const f=await fixture(t),old=await f.command('release'),next=keys();
 // Sign only the protocol's canonical JWK order; raw Node export bytes differ.
 const rawOrder={crv:next.jwk.crv,x:next.jwk.x,kty:next.jwk.kty};
 const noncanonical=await f.command('recover_manager',{kind:'recovery',key_id:f.config.recoveryKeyId,key_version:1,reason:'recovery_lost_key',new_manager:{key_id:'manager_2',version:2,jwk:rawOrder}},f.recovery.private);
 const before=await f.snapshot();
 assert.equal((await f.call('/command',noncanonical)).status,409);
 assert.deepEqual(await f.snapshot(),before);
 const recovery=await f.command('recover_manager',{kind:'recovery',key_id:f.config.recoveryKeyId,key_version:1,reason:'recovery_lost_key',new_manager:{key_id:'manager_2',version:2,jwk:next.jwk}},f.recovery.private);
 assert.equal((await f.call('/command',recovery)).status,200);let s=await f.snapshot();assert.equal(s.policy.enabled,0);assert.equal(s.security.manager_version,2);assert.equal(s.security.trust_revision,2);
 assert.equal((await f.call('/command',old)).status,409);assert.equal((await f.call('/command',await f.command('quarantine',{},f.manager.private))).status,409);
 assert.equal((await f.call('/command',await f.command('quarantine',{},next.private))).status,200);assert.equal((await f.call('/verify',{})).status,200);
});
test('retention removes only expired independently anchored prefix and keeps a signed prune proof',async t=>{
 const f=await fixture(t);await f.call('/command',await f.command('quarantine'));await f.call('/command',await f.command('release',{reason:'false_positive'}));const head=await f.pin(),before=await f.snapshot(),future=Date.now()+31*86400000;
 const result=await f.call('/prune',{now:future});assert.equal(result.status,200);assert.equal((await result.json()).pruned,2);const after=await f.snapshot();assert.equal(after.security.pruned_seq,2);assert.equal(after.signed.length,1);assert.equal(JSON.parse(after.signed[0].body).kind,'retention');assert.equal((await f.call('/verify',{minimumAnchor:head})).status,200);assert.equal(after.security.anchor_hash,before.security.anchor_hash);
});
