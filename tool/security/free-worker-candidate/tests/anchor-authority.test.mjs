import test from 'node:test';import assert from 'node:assert/strict';
import {generateKeyPairSync,sign,randomUUID,createHash}from'node:crypto';
import {mkdtemp,rm,cp,mkdir,copyFile,access,readFile}from'node:fs/promises';
import{join,resolve}from'node:path';import{tmpdir}from'node:os';import{createRequire}from'node:module';
const here=import.meta.dirname;
let original;
for(const p of [resolve(here,'../src/security-audit.mjs'),resolve(here,'../../../security-free-worker-candidate/src/security-audit.mjs')]){try{await access(p);original=resolve(p,'..');break}catch{}}
if(!original)throw Error('reviewed source unavailable');
if(createHash('sha256').update(await readFile(join(original,'security-audit.mjs'))).digest('hex')!=='c52da32183a947cfac8e37470dd777e9c5de24acf224b9ee445376a82a3d5e58')throw Error('reviewed audit source drift');
const require=createRequire(join(original,'../package.json')),{Miniflare,Log,LogLevel}=require('miniflare');
const keys=()=>{const p=generateKeyPairSync('ed25519');return{key:p.privateKey,jwk:p.publicKey.export({format:'jwk'}),privateJwk:p.privateKey.export({format:'jwk'})}};
const signature=(k,d,p)=>sign(null,Buffer.from(d+'\n'+JSON.stringify(p)),k).toString('hex');
async function fixture(t){
 const dir=await mkdtemp(join(tmpdir(),'sko-independent-anchor-')),v=join(dir,'code');
 await mkdir(join(v,'tests'),{recursive:true});await cp(original,join(v,'src'),{recursive:true});
 await copyFile(resolve(here,'../src/anchor-authority.mjs'),join(v,'src/anchor-authority.mjs'));
 await copyFile(join(here,'anchor-authority-fixture.mjs'),join(v,'tests/anchor-authority-fixture.mjs'));
 await copyFile(resolve(original,'../tests/management-fixture.mjs'),join(v,'tests/management-fixture.mjs'));
 const manager=keys(),recovery=keys(),audit=keys(),anchor=keys();
 const config={deploymentId:'deployment_1',companyId:'company_1',ownerId:'owner_1',auditKeyId:'audit_1',anchorKeyId:'anchor_1',auditJwk:audit.jwk,anchorJwk:anchor.jwk};
 const options={modules:true,scriptPath:join(v,'tests/anchor-authority-fixture.mjs'),modulesRoot:v,modulesRules:[{type:'CompiledWasm',include:['**/*.wasm']}],compatibilityDate:'2026-07-30',durableObjects:{SOURCE:{className:'SourceFixture',useSQLite:true},ANCHOR:{className:'AnchorFixture',useSQLite:true}},durableObjectsPersist:join(dir,'state'),bindings:{FIXTURE_ANCHOR_PRIVATE:JSON.stringify(anchor.privateJwk),FIXTURE_AUDIT_PRIVATE:JSON.stringify(audit.privateJwk)},log:new Log(LogLevel.ERROR)};
 let mf=new Miniflare(options);t.after(async()=>{await mf.dispose();await rm(dir,{recursive:true,force:true})});
 const call=async(ns,p,b={})=>{const n=await mf.getDurableObjectNamespace(ns);return n.get(n.idFromName('fixture')).fetch('https://fixture.invalid'+p,{method:'POST',body:JSON.stringify(b)})};
 assert.equal((await call('ANCHOR','/initialize',config)).status,200);
 assert.equal((await call('SOURCE','/initialize',{...config,managerKeyId:'manager_1',recoveryKeyId:'recovery_1',managerJwk:manager.jwk,recoveryJwk:recovery.jwk})).status,200);
 const source=async()=>await(await call('SOURCE','/snapshot')).json(),snapshot=async()=>await(await call('ANCHOR','/snapshot')).json();
 const command=async()=>{const s=await source(),now=Date.now(),p={v:1,kind:'management',key_id:'manager_1',key_version:1,deployment_id:config.deploymentId,subject:config.ownerId,company_id:config.companyId,action:'quarantine',reason:'operator_review',expected_policy_revision:s.policy.revision,expected_trust_revision:s.security.trust_revision,nonce:randomUUID(),issued_at:now,expires_at:now+60000};assert.equal((await call('SOURCE','/command',{envelope:{payload:p,signature:signature(manager.key,'sko-decoy-management-v1',p)},now})).status,200)};
 const publication=async(expected=0,h='0'.repeat(64))=>({publication:{expected_sequence:expected,expected_hash:h,records:(await source()).signed.filter(r=>r.sequence>expected)},now:Date.now()});
 return{call,source,snapshot,command,publication,config,audit,anchor,restart:async()=>{await mf.dispose();mf=new Miniflare(options)}};
}
test('actual signed audit becomes durable compatible independent receipt across restart and lost ACK',async t=>{
 const f=await fixture(t);await f.command();const p=await f.publication(),r=await f.call('ANCHOR','/publish',p);assert.equal(r.status,200);const receipt=await r.json();
 assert.equal((await f.call('SOURCE','/anchor',{envelope:receipt,now:Date.now()})).status,200);
 await f.restart();assert.deepEqual(await(await f.call('ANCHOR','/latest')).json(),receipt);
 assert.deepEqual(await(await f.call('ANCHOR','/publish',p)).json(),receipt);
 assert.equal((await f.snapshot()).receipts.length,1);
 await f.command();const q=await f.publication(receipt.payload.sequence,receipt.payload.hash),r2=await f.call('ANCHOR','/publish',q);assert.equal(r2.status,200);assert.equal((await r2.json()).payload.sequence,2);
});
test('wrong deployment/company/key/tampered/gapped/forked audit refuses without storage changes',async t=>{
 const f=await fixture(t);await f.command();const p=await f.publication(),before=await f.snapshot();
 for(const mutate of [x=>x.publication.records[0].sequence++,x=>x.publication.records[0].hash='f'.repeat(64),x=>x.publication.records[0].key_id='other',x=>x.publication.expected_hash='a'.repeat(64),x=>x.publication.records[0].body=x.publication.records[0].body.replace('company_1','other_company'),x=>x.publication.extra=true]){const x=structuredClone(p);mutate(x);assert.equal((await f.call('ANCHOR','/publish',x)).status,409);assert.deepEqual(await f.snapshot(),before)}
 assert.equal((await f.call('ANCHOR','/initialize',{...f.config,companyId:'other'})).status,409);assert.deepEqual(await f.snapshot(),before);
});
test('competing publications accept one and insertion failure rolls back receipt and monotonic head',async t=>{
 const f=await fixture(t);await f.command();const p=await f.publication();const rs=await Promise.all([f.call('ANCHOR','/publish',p),f.call('ANCHOR','/publish',p)]);assert.ok(rs.some(r=>r.status===200));assert.equal((await f.snapshot()).receipts.length,1);
 const before=await f.snapshot();await f.command();const next=await f.publication(1,before.state[0].hash);await f.call('ANCHOR','/fail-insert');assert.equal((await f.call('ANCHOR','/publish',next)).status,409);assert.deepEqual(await f.snapshot(),before);
});
test('saved authority tampering fails closed after restart',async t=>{
 const f=await fixture(t);await f.command();assert.equal((await f.call('ANCHOR','/publish',await f.publication())).status,200);await f.call('ANCHOR','/tamper');await f.restart();assert.equal((await f.call('ANCHOR','/latest')).status,409);assert.equal((await f.call('ANCHOR','/publish',await f.publication())).status,409);
});

test('validly signed wrong company or actor cannot establish an anchor',async t=>{
 const f=await fixture(t);await f.command();const original=await f.publication(),before=await f.snapshot();
 for(const patch of [{company_id:'other_company'},{actor_id:'other_owner'},{deployment_id:'other_deployment'},{occurred_at:Date.now()+60000}]){
  const x=structuredClone(original),row=x.publication.records[0],b={...JSON.parse(row.body),...patch};row.body=JSON.stringify(b);row.hash=createHash('sha256').update(row.body).digest('hex');row.occurred_at=b.occurred_at;row.signature=signature(f.audit.key,'sko-decoy-audit-v1',b);
  assert.equal((await f.call('ANCHOR','/publish',x)).status,409);assert.deepEqual(await f.snapshot(),before);
 }
});
test('independent receipt rejects source rollback and old publication cannot lower the retained authority head',async t=>{
 const f=await fixture(t);await f.command();const old=await f.publication(),r=await f.call('ANCHOR','/publish',old),first=await r.json();await f.command();
 const second=await(await f.call('ANCHOR','/publish',await f.publication(1,first.payload.hash))).json();const before=await f.snapshot();
 assert.equal((await f.call('ANCHOR','/publish',old)).status,409);assert.deepEqual(await f.snapshot(),before);
 await f.call('SOURCE','/truncate',{sequence:0,hash:'0'.repeat(64)});await f.restart();
 assert.equal((await f.call('SOURCE','/verify',{minimumAnchor:second.payload})).status,409);
 assert.deepEqual(await(await f.call('ANCHOR','/latest')).json(),second);
});

test('cross-batch audit time is monotonic while delayed records before receipt issue time remain valid',async t=>{
 const f=await fixture(t);await f.command();const firstPub=await f.publication();firstPub.now+=10000;
 const receipt=await(await f.call('ANCHOR','/publish',firstPub)).json(),before=await f.snapshot();await f.command();
 const next=await f.publication(1,receipt.payload.hash);next.now=firstPub.now+100;
 const regressed=structuredClone(next),row=regressed.publication.records[0],b=JSON.parse(row.body);
 b.occurred_at=firstPub.publication.records[0].occurred_at-1;row.occurred_at=b.occurred_at;row.body=JSON.stringify(b);row.hash=createHash('sha256').update(row.body).digest('hex');row.signature=signature(f.audit.key,'sko-decoy-audit-v1',b);
 assert.equal((await f.call('ANCHOR','/publish',regressed)).status,409);assert.deepEqual(await f.snapshot(),before);
 assert.ok(next.publication.records[0].occurred_at<receipt.payload.issued_at);
 assert.equal((await f.call('ANCHOR','/publish',next)).status,200);
 const latest=await(await f.call('ANCHOR','/latest')).json();assert.equal(latest.payload.sequence,2);
 assert.deepEqual(await(await f.call('ANCHOR','/publish',next)).json(),latest);
});
