import test from 'node:test';import assert from 'node:assert/strict';
import{generateKeyPairSync,randomUUID,createHash}from'node:crypto';import{mkdtemp,mkdir,copyFile,rm}from'node:fs/promises';import{resolve,join}from'node:path';import{tmpdir}from'node:os';import{pathToFileURL}from'node:url';
const here=import.meta.dirname,dir=await mkdtemp(join(tmpdir(),'sko-issuer-transport-'));await mkdir(join(dir,'issuer'));await mkdir(join(dir,'src'));
let copied=false;for(const path of[resolve(here,'../src/security-audit.mjs'),resolve(here,'../../../security-free-worker-candidate/src/security-audit.mjs')]){try{await copyFile(path,join(dir,'src/security-audit.mjs'));copied=true;break}catch{}}
if(!copied)throw Error('reviewed audit source unavailable');for(const name of['management-issuer.mjs','management-issuer-transport.mjs'])await copyFile(join(here,name),join(dir,'issuer',name));
const{createManagementTransport,createManagementRequestHandler}=await import(pathToFileURL(join(dir,'issuer/management-issuer-transport.mjs')));test.after(()=>rm(dir,{recursive:true,force:true}));
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`,now=Date.now(),proof='a'.repeat(64),origin='https://fixture.invalid';
const jwt=(claims={})=>[Buffer.from(JSON.stringify({alg:'fixture'})).toString('base64url'),Buffer.from(JSON.stringify({sub:id(1),session_id:id(2),role:'authenticated',iat:Math.floor(now/1000),exp:Math.floor(now/1000)+3600,is_anonymous:false,...claims})).toString('base64url'),'fixture'].join('.');
const caller=jwt(),service=jwt({sub:null,role:'service_role'}),publicKey='fixture-publishable-key';
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
const request=(body,bearer=caller,headers={})=>new Request('https://issuer.invalid/',{method:'POST',headers:{Authorization:'Bearer '+bearer,'Content-Type':'application/json',...headers},body:JSON.stringify(body)});
async function fixture(){
 const pair=generateKeyPairSync('ed25519'),jwk=pair.publicKey.export({format:'jwk'}),key=await crypto.subtle.importKey('jwk',pair.privateKey.export({format:'jwk'}),'Ed25519',false,['sign']);
 const payload={v:1,kind:'management',key_id:'manager_1',key_version:1,deployment_id:'deployment_1',subject:id(1),company_id:id(3),action:'quarantine',reason:'operator_review',expected_policy_revision:1,expected_trust_revision:1,nonce:randomUUID(),issued_at:now,expires_at:now+60000};
 const claim={state:'claimed',operation:'master.security_decoy.manage',command_id:randomUUID(),actor_id:id(1),session_id:id(2),company_id:id(3),lease_id:randomUUID(),payload_hash:createHash('sha256').update(JSON.stringify(payload)).digest('hex'),payload_body:JSON.stringify(payload),payload,manager_jwk:jwk};
 const calls=[];let receipt=null,signs=0;
 const fetchImpl=async(url,options)=>{
  calls.push({url,options});assert.ok(url.startsWith(origin+'/'));assert.equal(options.redirect,'manual');
  const route=new URL(url).pathname;
  if(route==='/auth/v1/user'){assert.equal(options.headers.Authorization,'Bearer '+caller);assert.equal(options.headers.apikey,publicKey);return json({id:id(1),is_anonymous:false});}
  const body=JSON.parse(options.body);
  if(route==='/rest/v1/rpc/claim_decoy_management_command'){assert.equal(options.headers.Authorization,'Bearer '+caller);assert.equal(options.headers.apikey,publicKey);assert.deepEqual(body,{p_proof:proof});return json(receipt?{...claim,state:'signed',receipt}:claim);}
  if(route==='/rest/v1/rpc/complete_decoy_management_command'){assert.equal(options.headers.Authorization,'Bearer '+service);assert.equal(options.headers.apikey,service);assert.equal(body.p_payload_hash,claim.payload_hash);receipt={payload,signature:body.p_signature};return json(receipt);}
  if(route==='/rest/v1/rpc/fail_decoy_management_command')return json(null);
  if(route==='/rest/v1/rpc/prepare_decoy_management_proof')return json({verified:false,reason:'secondary_password_rejected'});
  throw Error('unexpected fixture request');
 };
 const config={enabled:true,url:origin,publicKey,serviceBearer:service,fetchImpl,now:()=>now,resolveSigningKey:async()=>{signs++;return{key,publicJwk:jwk}},limitAttempt:async()=>true};
 return{config,calls,claim,key,jwk,fetchImpl,getSigns:()=>signs,getReceipt:()=>receipt};
}
test('OFF handler does no body parsing, authentication, rate lookup or signing',async()=>{
 let calls=0;const h=createManagementRequestHandler({fetchImpl:()=>calls++,resolveSigningKey:()=>calls++,limitAttempt:()=>calls++});const r=await h(request({operation:'issue',proof}));assert.equal(r.status,503);assert.deepEqual(await r.json(),{state:'disabled'});assert.equal(calls,0);
});
test('authenticated request keeps original bearer for claim and server token only for completion',async()=>{
 const f=await fixture(),h=createManagementRequestHandler(f.config),r=await h(request({operation:'issue',proof})),body=await r.json();assert.equal(r.status,200);assert.equal(body.state,'signed');assert.match(body.receipt.signature,/^[a-f0-9]{128}$/);assert.equal(f.getSigns(),1);
 const repeat=await(await h(request({operation:'issue',proof}))).json();assert.deepEqual(repeat,body);assert.equal(f.getSigns(),1);assert.ok(!JSON.stringify(body).includes(service));assert.ok(!JSON.stringify(body).includes(caller));assert.equal(r.headers.get('Cache-Control'),'no-store');
});
test('wrong secondary password returns normal false response without rolling back or signing',async()=>{
 const f=await fixture(),h=createManagementRequestHandler(f.config),command={deployment_id:'deployment_1',action:'quarantine',reason:'operator_review',expected_policy_revision:1,expected_trust_revision:1};
 const r=await h(request({operation:'prepare',company_id:id(3),command,secondary_password:'fixture-wrong'}));assert.equal(r.status,200);assert.deepEqual(await r.json(),{verified:false,reason:'secondary_password_rejected'});assert.equal(f.getSigns(),0);assert.equal(f.calls.filter(x=>x.url.endsWith('prepare_decoy_management_proof')).length,1);
});
test('caller payload injection, unsupported origin, method and malformed body never reach Auth or DB',async()=>{
 const f=await fixture(),h=createManagementRequestHandler(f.config);
 for(const req of[request({operation:'issue',proof,payload:f.claim.payload}),request({operation:'issue',proof},'invalid-token'),request({operation:'issue',proof},caller,{origin:'https://other.invalid'}),new Request('https://issuer.invalid/',{method:'GET'})]){
  const r=await h(req);assert.ok([400,401,403,405].includes(r.status));
 }
 assert.equal(f.calls.length,0);assert.equal(f.getSigns(),0);
});
test('expired, anonymous or mismatched caller is rejected before management RPC',async()=>{
 const f=await fixture();
 for(const bearer of[jwt({exp:1}),jwt({is_anonymous:true}),jwt({role:'service_role'})]){const h=createManagementRequestHandler(f.config);assert.equal((await h(request({operation:'issue',proof},bearer))).status,503);}
 const h=createManagementRequestHandler({...f.config,fetchImpl:async()=>json({id:id(9),is_anonymous:false})});assert.equal((await h(request({operation:'issue',proof}))).status,503);assert.equal(f.getSigns(),0);
});
test('rate limiter denial and outage fail closed without requesting a proof or key',async()=>{
 const f=await fixture();for(const limitAttempt of[async()=>false,async()=>{throw Error('limiter unavailable')}]){
  const h=createManagementRequestHandler({...f.config,limitAttempt});const r=await h(request({operation:'issue',proof}));assert.ok([429,503].includes(r.status));
 }
 assert.ok(f.calls.every(x=>x.url.endsWith('/auth/v1/user')));assert.equal(f.getSigns(),0);
});
test('redirects, nonJSON, oversized and malformed responses are rejected without following a new origin',async()=>{
 for(const response of[new Response(null,{status:307,headers:{Location:'https://other.invalid/'}}),new Response('text',{headers:{'content-type':'text/plain'}}),json('x'.repeat(33000)),new Response('{',{headers:{'content-type':'application/json'}})]){
  let n=0;const t=createManagementTransport({url:origin,publicKey,serviceBearer:service,callerBearer:caller,now:()=>now,fetchImpl:async()=>{n++;return response;}});await assert.rejects(t.authenticate());assert.equal(n,1);
 }
});
test('transport deadline refuses a late ignored-abort Auth response and performs no later RPC',async()=>{
 let release;const f=await fixture(),h=createManagementRequestHandler({...f.config,timeoutMs:20,fetchImpl:()=>new Promise(resolve=>release=resolve)});
 const r=await h(request({operation:'issue',proof}));assert.equal(r.status,503);release(json({id:id(1),is_anonymous:false}));await Promise.resolve();assert.equal(f.getSigns(),0);assert.equal(f.getReceipt(),null);
});
test('whole-request deadline cancels a stalled limiter and discards its late allow result',async()=>{
 const f=await fixture();let release,aborted=false;
 const h=createManagementRequestHandler({...f.config,deadlineMs:50,limitAttempt:(_,options)=>new Promise(resolve=>{release=resolve;options.signal.addEventListener('abort',()=>aborted=true)})});const r=await h(request({operation:'issue',proof}));assert.equal(r.status,503);assert.deepEqual(await r.json(),{state:'pending'});assert.equal(aborted,true);release(true);await Promise.resolve();assert.equal(f.getSigns(),0);assert.equal(f.getReceipt(),null);
});
test('whole-request deadline invalidates a late resolver even if it ignores the combined abort signal',async()=>{
 const f=await fixture();let release,aborted=false;
 const h=createManagementRequestHandler({...f.config,deadlineMs:50,timeoutMs:200,resolveSigningKey:(_,options)=>new Promise(resolve=>{release=resolve;options.signal.addEventListener('abort',()=>aborted=true)})});
 const r=await h(request({operation:'issue',proof}));assert.equal(r.status,503);assert.equal(aborted,true);release({key:f.key,publicJwk:f.jwk});await new Promise(resolve=>setImmediate(resolve));assert.equal(f.getReceipt(),null);assert.ok(f.calls.every(x=>!x.url.endsWith('/complete_decoy_management_command')));
});
test('body byte limit and cancellation bound an incomplete request stream',async()=>{
 const f=await fixture(),h=createManagementRequestHandler({...f.config,deadlineMs:50});assert.equal((await h(request({operation:'issue',proof,extra:'x'.repeat(8200)}))).status,503);
 let cancelled=false;const stream=new ReadableStream({start(c){c.enqueue(new TextEncoder().encode('{'));},cancel(){cancelled=true;}});
 const req=new Request('https://issuer.invalid/',{method:'POST',headers:{Authorization:'Bearer '+caller},body:stream,duplex:'half'});const r=await h(req);assert.equal(r.status,503);assert.equal(cancelled,true);assert.equal(f.calls.length,0);
});
test('transport configuration cannot use caller-selected paths, credentials, plaintext or query routes',()=>{
 for(const url of['http://fixture.invalid','https://user:password@fixture.invalid','https://fixture.invalid/alternate','https://fixture.invalid/?url=other','https://fixture.invalid/#other'])assert.throws(()=>createManagementTransport({url,publicKey,serviceBearer:service,callerBearer:caller}),/configuration/);
 assert.throws(()=>createManagementRequestHandler({enabled:true,...{url:origin,publicKey,serviceBearer:service},resolveSigningKey:()=>{}}),/ports/);
});
