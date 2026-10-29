import {test} from 'node:test';
import assert from 'node:assert/strict';
import {performance} from 'node:perf_hooks';
import {createScannerRegistrationHttpsHandler} from './qr-scanner-registration-https.mjs';
import {createScannerTlsFixture} from './qr-scanner-registration-tls-fixture.mjs';
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const origin='https://qr-auth-fixture.invalid';
const payload={schema:1,requestId:id(1),operation:'result',challengeId:id(2),companyId:id(3),deviceId:id(4),publicKeyHex:'302a300506032b6570032100'+'ab'.repeat(32)};
const claims={sub:id(5),session_id:id(6),role:'authenticated',is_anonymous:false,aud:'authenticated',iss:origin+'/auth/v1',iat:Math.floor(Date.now()/1000),exp:4102444800};
const token=[{},claims,'synthetic-signature'].map(v=>Buffer.from(typeof v==='string'?v:JSON.stringify(v)).toString('base64url')).join('.');
function options(overrides={}){
 const calls={auth:0,pool:0,admission:[],sql:[]};
 const pool={connect:async()=>{calls.pool++;return {query:async(sql)=>{calls.sql.push(sql);
  if(sql.includes('auth.uid()'))return {rows:[{actor:id(5),session:id(6)}]};
  if(sql.includes('read_own_registration_proof_issuance'))return {rows:[{status:'committed_unrecoverable'}]};
  if(sql.includes('read_own_scanner_key_registration'))return {rows:[{receipt:null}]};
  return {rows:[]};},release(){}};}};
 const config={enabled:true,projectOrigin:origin,expectedIssuer:claims.iss,publicKey:'synthetic-public',pool,
  fetchImpl:async(url,request)=>{calls.auth++;assert.equal(String(url),origin+'/auth/v1/user');assert.equal(request.headers.Authorization,'Bearer '+token);
   return new Response(JSON.stringify({id:id(5),is_anonymous:false}),{headers:{'content-type':'application/json'}});},
  admitVerifiedRequest:async principal=>{calls.admission.push(principal);return true;},...overrides};
 return {calls,make:publicOrigin=>createScannerRegistrationHttpsHandler({...config,publicOrigin})};
}
test('default OFF sends no-store generic response without Auth, admission or database',async t=>{
 const o=options({enabled:false}),f=await createScannerTlsFixture(o.make);t.after(f.close);
 const result=await f.call(payload,{token});assert.equal(result.status,404);assert.equal(o.calls.auth,0);assert.equal(o.calls.pool,0);assert.match(result.headers['cache-control'],/no-store/);
});
test('real TLS exact-bearer result request binds minimal principal and read-only private pool',async t=>{
 const o=options(),f=await createScannerTlsFixture(o.make);t.after(f.close);
 const result=await f.call(payload,{token});assert.equal(result.status,200);
 assert.deepEqual(result.json,{schema:1,requestId:id(1),operation:'result',receipt:null});
 assert.deepEqual(o.calls.admission,[{actor:id(5),session:id(6),operation:'result',requestId:id(1)}]);
 assert.equal(Object.isFrozen(o.calls.admission[0]),true);assert.equal(o.calls.pool,1);
 assert.equal(o.calls.sql.some(s=>/issue_|complete_own|consume_/.test(s)),false);
 assert.equal(result.text.includes(token),false);assert.match(result.headers['cache-control'],/no-store/);
});
test('plaintext plus forwarded TLS, foreign Origin, missing/duplicate bearer and bad routes deny before pool',async t=>{
 const o=options(),plain=await createScannerTlsFixture(o.make,{plain:true});t.after(plain.close);
 assert.equal((await plain.call(payload,{token,headers:{'x-forwarded-proto':'https'}})).status,403);
 const f=await createScannerTlsFixture(o.make);t.after(f.close);
 assert.equal((await f.call(payload)).status,401);
 assert.equal((await f.call(payload,{token,headers:{authorization:['Bearer '+token,'Bearer '+token]}})).status,400);
 assert.equal((await f.call(payload,{token,headers:{origin:'https://foreign.invalid'}})).status,403);
 assert.equal((await f.call(payload,{token,path:'/other'})).status,404);
 assert.equal(o.calls.auth,0);assert.equal(o.calls.pool,0);
});
test('unknown fields, operations and caller-selected principal/project/pool are rejected before admission or SQL',async t=>{
 const o=options(),f=await createScannerTlsFixture(o.make);t.after(f.close);
 for(const input of [{...payload,actor:id(99)},{...payload,projectOrigin:'https://foreign.invalid'},
  {...payload,pool:{}},{schema:1,requestId:id(1),operation:'constructor'}]){
  const result=await f.call(input,{token});assert.equal(result.status,400);assert.equal(result.text.includes('foreign'),false);
 }
 assert.equal(o.calls.pool,0);assert.equal(o.calls.admission.length,0);
});
test('oversized declared/chunked body and invalid UTF-8 reject without SQL',async t=>{
 const o=options(),f=await createScannerTlsFixture(o.make);t.after(f.close);
 assert.equal((await f.call(payload,{token,raw:' '.repeat(8193)})).status,413);
 assert.equal((await f.call(payload,{token,chunks:[Buffer.alloc(8193,32)]})).status,413);
 assert.equal((await f.call(payload,{token,raw:Buffer.from([0xff])})).status,400);assert.equal(o.calls.pool,0);
});
test('verified admission failure/timeout has generic no-store error and never acquires pool',async t=>{
 const denied=options({admitVerifiedRequest:async()=>false}),f=await createScannerTlsFixture(denied.make);t.after(f.close);
 assert.equal((await f.call(payload,{token})).status,429);assert.equal(denied.calls.pool,0);
 const timed=options({admissionTimeoutMs:10,admitVerifiedRequest:()=>new Promise(()=>{})}),g=await createScannerTlsFixture(timed.make);t.after(g.close);
 const result=await g.call(payload,{token});assert.equal(result.status,503);assert.equal(timed.calls.pool,0);assert.equal(result.text.includes(token),false);
});
test('partial body and late admission cannot outlive request deadlines into SQL',async t=>{
 const slow=options({bodyTimeoutMs:20}),f=await createScannerTlsFixture(slow.make);t.after(f.close);
 const partial=await f.call(payload,{token,chunks:[Buffer.from('{"schema":'),Buffer.from('1}')],chunkPauseMs:60});
 assert.equal(partial.status,408);assert.equal(slow.calls.pool,0);
 let release;const pending=new Promise(resolve=>{release=resolve;});
 const late=options({requestTimeoutMs:30,admissionTimeoutMs:500,admitVerifiedRequest:()=>pending});
 const g=await createScannerTlsFixture(late.make);t.after(g.close);
 assert.equal((await g.call(payload,{token})).status,503);release(true);
 await new Promise(resolve=>setTimeout(resolve,10));assert.equal(late.calls.pool,0);
});
test('client abort during Auth wait is handled without a late pool acquisition or unhandled stream error',async t=>{
 let started;const authStarted=new Promise(resolve=>{started=resolve;});
 const o=options({authTimeoutMs:200,fetchImpl:()=>{started();return new Promise(()=>{});}});
 const f=await createScannerTlsFixture(o.make);t.after(f.close);
 await assert.rejects(f.call(payload,{token,chunks:[Buffer.from('{"schema":'),Buffer.from('1}')],chunkPauseMs:100,abortWhen:authStarted}));
 await new Promise(resolve=>setTimeout(resolve,220));assert.equal(o.calls.pool,0);
});
test('late private-pool lease after request timeout is released without BEGIN or any SQL',async t=>{
 let release;const lease=new Promise(resolve=>{release=resolve;});let queries=0,releases=0;
 const o=options({requestTimeoutMs:30,pool:{connect:()=>lease}}),f=await createScannerTlsFixture(o.make);t.after(f.close);
 assert.equal((await f.call(payload,{token})).status,503);
 release({query:async()=>{queries++;return {rows:[]};},release(){releases++;}});
 await new Promise(resolve=>setTimeout(resolve,10));assert.equal(queries,0);assert.equal(releases,1);
});
test('expired synchronous admission stage rejects before SQL even while overall budget remains',async t=>{
 const o=options({requestTimeoutMs:500,admissionTimeoutMs:10,admitVerifiedRequest:()=>{
  const until=performance.now()+100;while(performance.now()<until){}return true;
 }}),f=await createScannerTlsFixture(o.make);t.after(f.close);
 const result=await f.call(payload,{token});assert.equal(result.status,503);assert.equal(o.calls.pool,0);
});
test('expired overall request rejects a synchronous admission result inside its longer stage budget',async t=>{
 const o=options({requestTimeoutMs:50,admissionTimeoutMs:500,admitVerifiedRequest:()=>{
  const until=performance.now()+100;while(performance.now()<until){}return true;
 }}),f=await createScannerTlsFixture(o.make);t.after(f.close);
 const result=await f.call(payload,{token});assert.equal(result.status,503);assert.equal(o.calls.pool,0);
});
test('expired synchronous pool acquisition releases lease before any SQL despite pending timers',async t=>{
 let queries=0,releases=0;
 const o=options({requestTimeoutMs:50,pool:{connect:()=>{
  const until=performance.now()+100;while(performance.now()<until){}
  return {query:async sql=>{queries++;return {rows:[sql.includes('auth.uid()')?{actor:id(5),session:id(6)}:{receipt:null}]};},release(){releases++;}};
 }}}),f=await createScannerTlsFixture(o.make);t.after(f.close);
 const result=await f.call(payload,{token});assert.equal(result.status,503);assert.equal(queries,0);assert.equal(releases,1);
});

test('proof_result composes read-only exact challenge status and forbids caller credentials/principal/expiry',async t=>{
 const o=options(),f=await createScannerTlsFixture(o.make);t.after(f.close);
 const input={schema:1,requestId:id(1),operation:'proof_result',challengeId:id(2)};
 const result=await f.call(input,{token});assert.equal(result.status,200);
 assert.deepEqual(result.json,{schema:1,requestId:id(1),operation:'proof_result',issuance:{status:'committed_unrecoverable'}});
 assert.equal(o.calls.sql.some(sql=>/issue_registration_proof\(|complete_own|consume_/.test(sql)),false);
 const poolBefore=o.calls.pool;
 for(const extra of [{actor:id(99)},{session:id(99)},{password:'synthetic-secret'},{proof:'ab'.repeat(32)},{expiresAt:'2099-01-01'}]){
  const denied=await f.call({...input,...extra},{token});assert.equal(denied.status,400);assert.equal(denied.text.includes('synthetic-secret'),false);
 }
 assert.equal(o.calls.pool,poolBefore);
});
