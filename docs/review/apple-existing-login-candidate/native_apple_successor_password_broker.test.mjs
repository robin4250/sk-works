import test from 'node:test';import assert from 'node:assert/strict';
import {createNativeApplePasswordSuccessorBroker} from './native_apple_successor_broker.mjs';
import {sha256Hex} from './existing_apple_login.mjs';
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const actor=id(1),oldSid=id(2),pwSid=id(3),appleSid=id(4),intent=id(5),request=id(6),now=1800000000;
const origin='https://ztktgquxvcxcjxtluspu.supabase.co',nonce='n'.repeat(43),subject='apple-fixture';
const jwt=sid=>'eyJhbGciOiJSUzI1NiJ9.'+Buffer.from(JSON.stringify({sub:actor,session_id:sid,role:'authenticated',aud:'authenticated',iss:origin+'/auth/v1',exp:now+600})).toString('base64url')+'.fixture';
const old=jwt(oldSid),pw=jwt(pwSid),apple=jwt(appleSid);
const pair=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk={...await crypto.subtle.exportKey('jwk',pair.publicKey),kid:'fixture',alg:'RS256',use:'sig'};
const b=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
const unsigned=b({alg:'RS256',kid:'fixture'})+'.'+b({iss:'https://appleid.apple.com',aud:'com.skworks.skWorks',sub:subject,iat:now,exp:now+600,nonce:await sha256Hex(nonce)});
const idToken=unsigned+'.'+Buffer.from(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',pair.privateKey,new TextEncoder().encode(unsigned))).toString('base64url');
const hash=await sha256Hex(idToken),json=(x,status=200)=>new Response(JSON.stringify(x),{status});
function fixture(mode){const calls=[];let linked=false,clock=now;
 const db={query:async(sql,args)=>{calls.push(['sql',sql,args]);
  if(sql.includes('begin_password_successor')){if(mode==='late-intent')clock=now+121;return {rows:[{r:{intent_id:intent,actor_id:actor,original_session_id:oldSid,subject,token_sha256:hash}}]};}
  if(sql.includes('reserve_password_successor')){assert.deepEqual(args,[intent,actor,oldSid,pwSid]);return {rows:[{r:mode==='changed-snapshot'?null:{intent_id:intent,request_id:request,status:'reserved',actor_id:actor,original_session_id:oldSid,session_id:pwSid,subject,token_sha256:hash}}]};}
  if(sql.includes('claim_successor_attempt')){assert.deepEqual(args,[request,actor,pwSid]);return {rows:[{r:{request_id:request,status:'reserved',actor_id:actor,session_id:pwSid,subject,token_sha256:hash,snapshot_sha256:'a'.repeat(64)}}]};}
  if(sql.includes('complete_with_successor')){assert.equal(args[2],pwSid);assert.equal(args[3],appleSid);return {rows:[{r:{linked:true,request_id:request,actor_id:actor,session_id:appleSid}}]};}
  return {rows:[]};},release:()=>{}};
 const config={enabled:true,nativeOnlyReviewed:true,successorReviewed:true,passwordSuccessorReviewed:true,databaseReviewed:true,deliveryReviewed:true,audiences:['com.skworks.skWorks'],baseUrl:origin,publicKey:'sb_publishable_fixture'};
 const dependencies={now:()=>clock,pool:{connect:async()=>db},resolveKey:async()=>jwk,
  fetcher:async(url,init)=>{calls.push(['http',url]);
   if(url.endsWith('/user'))return json({id:actor,email:'server-owned@example.invalid',is_anonymous:false,identities:linked?[{provider:'apple',identity_data:{sub:subject}}]:[{provider:'google',provider_id:'google-fixture'}]});
   if(url.endsWith('grant_type=password')){
    assert.equal(calls.filter(x=>x[0]==='sql'&&x[1]==='commit').length,1,'intent must commit before password session');
    assert.deepEqual(JSON.parse(init.body),{email:'server-owned@example.invalid',password:'fixture-password'});
    if(mode==='late-password')clock=now+121;
    return mode==='wrong-password'?json({error:'bad password'},400):json({access_token:pw,refresh_token:'fixture-pw-refresh',token_type:'bearer',user:{id:actor}});
   }
   if(url.endsWith('grant_type=id_token')){assert.equal(calls.filter(x=>x[0]==='sql'&&x[1]==='commit').length,3,'intent, snapshot reservation and durable claim precede link');
    assert.equal(init.headers.Authorization,'Bearer '+pw);linked=true;return json({access_token:apple,refresh_token:'fixture-apple-refresh',token_type:'bearer'});}
   throw Error('unexpected request');},
  deliverVerifiedSuccessor:async credential=>{calls.push(['deliver']);assert.equal(credential.user_id,actor);assert.equal(credential.session_id,appleSid);assert.equal(credential.refresh_token,'fixture-apple-refresh');return true;}};
 return {calls,config,dependencies,input:{exactBearer:old,password:'fixture-password',idToken,rawNonce:nonce}};
}
test('PW successor composes pre-password snapshot, atomic reservation, durable link and same-UID handoff',async()=>{
 const f=fixture(),broker=createNativeApplePasswordSuccessorBroker(f.config,f.dependencies);assert.deepEqual(await broker(f.input),{linked:true,user_id:actor,session_id:appleSid});
 assert.equal(f.calls.filter(x=>x[0]==='deliver').length,1);assert.equal(f.calls.some(x=>x[0]==='http'&&x[1].includes('logout')),false);
 assert.equal(JSON.stringify(f.calls).includes('fixture-password'),false);assert.equal(JSON.stringify(f.calls).includes('fixture-pw-refresh'),false);
 await assert.rejects(broker(f.input));
});
test('wrong password or rejected snapshot never links, delivers or retries',async()=>{
 for(const mode of ['wrong-password','changed-snapshot']){const f=fixture(mode),broker=createNativeApplePasswordSuccessorBroker(f.config,f.dependencies);
 await assert.rejects(broker(f.input),{message:'apple_successor_handoff_unavailable'});await assert.rejects(broker(f.input));
 assert.equal(f.calls.filter(x=>x[0]==='http'&&x[1].includes('grant_type=password')).length,1);
 assert.equal(f.calls.some(x=>x[0]==='http'&&x[1].includes('grant_type=id_token')),false);assert.equal(f.calls.some(x=>x[0]==='deliver'),false);}
});
test('OFF or invalid Apple credential rejects before any password or database operation',async()=>{
 for(const mode of ['off','invalid-token']){const f=fixture();if(mode==='off')f.config.passwordSuccessorReviewed=false;
 await assert.rejects(createNativeApplePasswordSuccessorBroker(f.config,f.dependencies)({...f.input,idToken:mode==='invalid-token'?'invalid':idToken}));assert.equal(f.calls.length,0);}
});
test('expired orchestration window never advances to password or reservation after a slow boundary',async()=>{
 for(const mode of ['late-intent','late-password']){const f=fixture(mode);
 await assert.rejects(createNativeApplePasswordSuccessorBroker(f.config,f.dependencies)(f.input));
 assert.equal(f.calls.filter(x=>x[0]==='http'&&x[1].includes('grant_type=password')).length,mode==='late-intent'?0:1);
 assert.equal(f.calls.some(x=>x[0]==='sql'&&x[1].includes('reserve_password_successor')),false);
 assert.equal(f.calls.some(x=>x[0]==='http'&&x[1].includes('grant_type=id_token')),false);}
});
