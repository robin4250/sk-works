import {test} from 'node:test';
import assert from 'node:assert/strict';
import {verifyScannerRegistrationBearer} from './qr-scanner-verified-session.mjs';
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const now=Math.floor(Date.now()/1000),origin='https://scanner-fixture.invalid',issuer=origin+'/auth/v1';
const claims={sub:id(1),session_id:id(2),role:'authenticated',aud:'authenticated',is_anonymous:false,exp:now+3600,iat:now,iss:issuer};
const token=c=>[{},c,'synthetic-signature'].map(x=>Buffer.from(typeof x==='string'?x:JSON.stringify(x)).toString('base64url')).join('.');
const options={enabled:true,projectOrigin:origin,expectedIssuer:issuer,publicKey:'synthetic-public',bearer:token(claims)};
const response=(body={id:id(1),is_anonymous:false})=>new Response(JSON.stringify(body),{headers:{'content-type':'application/json'}});
test('default OFF never verifies or binds database claims',async()=>{
 let calls=0;await assert.rejects(verifyScannerRegistrationBearer({...options,enabled:false,fetchImpl:async()=>{calls++;return response();}}));assert.equal(calls,0);
});
test('exact origin/bearer verifies before one-use minimal transaction binding',async()=>{
 const initialize=await verifyScannerRegistrationBearer({...options,fetchImpl:async(url,request)=>{
  assert.equal(String(url),origin+'/auth/v1/user');assert.equal(request.redirect,'error');
  assert.equal(request.headers.Authorization,'Bearer '+options.bearer);return response({id:id(1),is_anonymous:false,user_metadata:{role:'owner'}});
 }});
 const calls=[];const client={async query(sql,args){calls.push({sql,args});return {rows:[{actor:id(1),session:id(2)}]};}};
 assert.deepEqual(await initialize(client),{actor:id(1),session:id(2)});
 assert.equal(JSON.parse(calls[0].args[0]).user_metadata,undefined);assert.ok(calls[0].sql.includes(',true)'));
 await assert.rejects(initialize(client));assert.equal(calls.length,2);
});
test('mismatched user, anonymous, role, session, audience, issuer and expiry fail closed',async()=>{
 for(const change of [{sub:id(3)},{session_id:'invalid'},{role:'service_role'},{aud:['authenticated','other']},{iss:'https://other.invalid/auth/v1'},{exp:now-1},{is_anonymous:true}]){
  await assert.rejects(verifyScannerRegistrationBearer({...options,bearer:token({...claims,...change}),fetchImpl:async()=>response()}));
 }
 await assert.rejects(verifyScannerRegistrationBearer({...options,fetchImpl:async()=>response({id:id(1),is_anonymous:true})}));
});
test('Auth rejection cannot create a database initializer; responses are generic',async()=>{
 for(const status of [301,401,500])await assert.rejects(verifyScannerRegistrationBearer({...options,fetchImpl:async()=>new Response('private detail',{status})}),e=>e.message==='scanner authentication unavailable');
 const initialize=await verifyScannerRegistrationBearer({...options,fetchImpl:async()=>response()});
 await assert.rejects(initialize({query:async()=>({rows:[{actor:id(1),session:id(3)}]})}));
});
test('oversized streamed user body is cancelled and ignored',async()=>{
 for(const headers of [{'content-type':'application/json'},{'content-type':'application/json','content-length':'32769'}]){
  let cancelled=false;
  const body=new ReadableStream({start(c){c.enqueue(new Uint8Array(32769));},cancel(){cancelled=true;}});
  await assert.rejects(verifyScannerRegistrationBearer({...options,fetchImpl:async()=>new Response(body,{headers})}));assert.equal(cancelled,true);
 }
});
test('hard deadline rejects a transport which ignores AbortSignal',async()=>{
 const start=Date.now();await assert.rejects(verifyScannerRegistrationBearer({...options,timeoutMs:10,fetchImpl:()=>new Promise(()=>{})}));assert.ok(Date.now()-start<1000);
});
test('late transport response is cancelled after deadline and never binds a principal',async()=>{
 let resolve,cancelled=false;
 const late=new Promise(r=>{resolve=r;});
 await assert.rejects(verifyScannerRegistrationBearer({...options,timeoutMs:10,fetchImpl:()=>late}));
 resolve(new Response(new ReadableStream({cancel(){cancelled=true;}}),{headers:{'content-type':'application/json'}}));
 await new Promise(r=>setTimeout(r,0));assert.equal(cancelled,true);
});
