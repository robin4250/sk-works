import test from'node:test';import assert from'node:assert/strict';import{generateKeyPairSync,randomUUID,createHash}from'node:crypto';
import{mkdtemp,copyFile,mkdir,rm}from'node:fs/promises';import{join,resolve,dirname}from'node:path';import{createRequire}from'node:module';import{tmpdir}from'node:os';import{pathToFileURL}from'node:url';
const here=import.meta.dirname;
const dir=await mkdtemp(join(tmpdir(),'sko-management-issuer-code-'));await mkdir(join(dir,'src'));await mkdir(join(dir,'issuer'));
let auditSource;for(const p of [resolve(here,'../src/security-audit.mjs'),resolve(here,'../../../security-free-worker-candidate/src/security-audit.mjs')]){try{await copyFile(p,join(dir,'src/security-audit.mjs'));auditSource=p;break}catch{}}
if(!auditSource)throw Error('reviewed audit source unavailable');await copyFile(join(here,'management-issuer.mjs'),join(dir,'issuer/management-issuer.mjs'));
const{createManagementIssuer}=await import(pathToFileURL(join(dir,'issuer/management-issuer.mjs')));process.on('exit',()=>{});test.after(async()=>rm(dir,{recursive:true,force:true}));
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`,proof='a'.repeat(64),hash=x=>createHash('sha256').update(x).digest('hex');
async function setup(){
 const p=generateKeyPairSync('ed25519'),jwk=p.publicKey.export({format:'jwk'}),privateJwk=p.privateKey.export({format:'jwk'}),key=await crypto.subtle.importKey('jwk',privateJwk,'Ed25519',false,['sign']),now=Date.now();
 const payload={v:1,kind:'management',key_id:'manager_1',key_version:1,deployment_id:'deployment_1',subject:id(1),company_id:id(3),action:'quarantine',reason:'operator_review',expected_policy_revision:1,expected_trust_revision:1,nonce:randomUUID(),issued_at:now,expires_at:now+60000};
 const claim={state:'claimed',operation:'master.security_decoy.manage',command_id:randomUUID(),actor_id:id(1),session_id:id(2),company_id:id(3),lease_id:randomUUID(),payload_hash:hash(JSON.stringify(payload)),payload_body:JSON.stringify(payload),payload,manager_jwk:jwk};
 let receipt=null,claimMode='normal',unknownAck=false,signs=0;const failures=[];
 const database={claim:async token=>{assert.equal(token,proof);if(claimMode==='pending')return{state:'pending',command_id:claim.command_id};return receipt?{...claim,state:'signed',receipt}:structuredClone(claim)},complete:async r=>{assert.equal(r.command_id,claim.command_id);assert.equal(r.lease_id,claim.lease_id);assert.equal(r.payload_hash,claim.payload_hash);receipt={payload:claim.payload,signature:r.signature};if(unknownAck)throw Error('ACK lost after commit');return receipt},fail:async r=>failures.push(r)};
 const issuer=createManagementIssuer({enabled:true,database,resolveSigningKey:async config=>{assert.deepEqual(config,{deploymentId:'deployment_1',keyId:'manager_1',keyVersion:1});signs++;return{key,publicJwk:jwk}},now:()=>now});
 return{issuer,claim,database,key,jwk,now,failures,getReceipt:()=>receipt,getSigns:()=>signs,ackLost:()=>unknownAck=true,pending:()=>claimMode='pending'};
}
test('default OFF never calls a database or resolver',async()=>{let n=0;const i=createManagementIssuer({database:{claim(){n++}},resolveSigningKey(){n++}});assert.deepEqual(await i.issue({proof}),{state:'disabled'});assert.equal(n,0)});
test('canonical claim signs one authorization and durable retry does not sign again',async()=>{const f=await setup(),r=await f.issuer.issue({proof});assert.equal(r.state,'signed');assert.equal(r.receipt.payload.nonce,f.claim.payload.nonce);assert.equal(f.getSigns(),1);assert.deepEqual(await f.issuer.issue({proof}),r);assert.equal(f.getSigns(),1)});
test('completion ACK loss never exposes the envelope and same proof recovers the committed receipt',async()=>{const f=await setup();f.ackLost();assert.equal((await f.issuer.issue({proof})).state,'pending');assert.ok(f.getReceipt());assert.equal((await f.issuer.issue({proof})).state,'signed');assert.equal(f.getSigns(),1)});
test('pending competing claim has no key access or signing',async()=>{const f=await setup();f.pending();assert.equal((await f.issuer.issue({proof})).state,'pending');assert.equal(f.getSigns(),0)});
test('read proof, changed actor/scope/body/revision and malformed claim refuse before key access',async()=>{
 const f=await setup();await assert.rejects(f.issuer.issue({proof:'existing_read_proof'}),/Dedicated/);
 for(const patch of [{operation:'master.security_collector.read'},{actor_id:id(9)},{company_id:id(9)},{payload_hash:'f'.repeat(64)},{payload_body:f.claim.payload_body+' '},{payload:{...f.claim.payload,action:'recover_manager'}},{payload:{...f.claim.payload,expected_policy_revision:0}}]){
  const i=createManagementIssuer({enabled:true,database:{...f.database,claim:async()=>({...f.claim,...patch})},resolveSigningKey:async()=>{throw Error('must not resolve')},now:()=>f.now});await assert.rejects(i.issue({proof}),/binding/);
 }
 assert.equal(f.getSigns(),0);
});
test('resolver failure or extractable/wrong signing key stays pending with same immutable command',async()=>{
 const f=await setup();for(const resolveSigningKey of [async()=>{throw Error('unavailable')},async()=>({key:(await crypto.subtle.generateKey('Ed25519',true,['sign','verify'])).privateKey,publicJwk:f.jwk}),async()=>({key:await crypto.subtle.importKey('jwk',generateKeyPairSync('ed25519').privateKey.export({format:'jwk'}),'Ed25519',false,['sign']),publicJwk:f.jwk})]){
  const i=createManagementIssuer({enabled:true,database:f.database,resolveSigningKey,now:()=>f.now});assert.equal((await i.issue({proof})).state,'pending');assert.equal(f.getReceipt(),null);
 }
 assert.deepEqual(f.failures.map(x=>x.failure),['key_unavailable','signing_failed','signing_failed']);assert.ok(f.failures.every(x=>x.command_id===f.claim.command_id&&x.lease_id===f.claim.lease_id));
});

test('issuer envelope is consumed once by the unchanged actual-workerd management core',async t=>{
 const f=await setup(),root=resolve(dirname(auditSource),'..'),require=createRequire(join(root,'package.json')),{Miniflare,Log,LogLevel}=require('miniflare');
 const make=()=>{const p=generateKeyPairSync('ed25519');return{jwk:p.publicKey.export({format:'jwk'}),privateJwk:p.privateKey.export({format:'jwk'})}},audit=make(),recovery=make(),anchor=make();
 const mf=new Miniflare({modules:true,scriptPath:join(root,'tests/management-fixture.mjs'),modulesRoot:root,modulesRules:[{type:'CompiledWasm',include:['**/*.wasm']}],compatibilityDate:'2026-07-30',durableObjects:{DECOY:{className:'ManagementFixture',useSQLite:true}},bindings:{FIXTURE_AUDIT_PRIVATE:JSON.stringify(audit.privateJwk)},log:new Log(LogLevel.ERROR)});t.after(()=>mf.dispose());
 const ns=await mf.getDurableObjectNamespace('DECOY'),stub=ns.get(ns.idFromName('issuer-compatible'));const call=(p,b)=>stub.fetch('https://fixture.invalid'+p,{method:'POST',body:JSON.stringify(b)});
 assert.equal((await call('/initialize',{deploymentId:'deployment_1',ownerId:id(1),companyId:id(3),managerKeyId:'manager_1',recoveryKeyId:'recovery_1',auditKeyId:'audit_1',anchorKeyId:'anchor_1',managerJwk:f.jwk,recoveryJwk:recovery.jwk,auditJwk:audit.jwk,anchorJwk:anchor.jwk})).status,200);
 const r=await f.issuer.issue({proof});assert.equal(r.state,'signed');assert.equal((await call('/command',{envelope:r.receipt,now:f.now})).status,200);assert.equal((await call('/command',{envelope:r.receipt,now:f.now})).status,409);
 const snap=await(await call('/snapshot',{})).json();assert.equal(snap.nonces.length,1);assert.equal(snap.signed.length,1);assert.equal(snap.policy.quarantined,1);
});

test('malformed completion ACK also retains pending state and same-proof lookup recovers',async()=>{
 const f=await setup(),complete=f.database.complete;f.database.complete=async r=>{await complete(r);return {unexpected:true}};
 assert.equal((await f.issuer.issue({proof})).state,'pending');assert.ok(f.getReceipt());assert.equal((await f.issuer.issue({proof})).state,'signed');assert.equal(f.getSigns(),1);
});
