import test from 'node:test';import assert from 'node:assert/strict';
import {createNativeAppleSuccessorBroker} from './native_apple_successor_broker.mjs';
import {sha256Hex} from './existing_apple_login.mjs';
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const actor=id(1),originalSID=id(2),successorSID=id(3),request=id(4),now=1800000000;
const origin='https://ztktgquxvcxcjxtluspu.supabase.co',nonce='n'.repeat(43),subject='apple-fixture-subject';
const jwt=sid=>'eyJhbGciOiJSUzI1NiJ9.'+Buffer.from(JSON.stringify({sub:actor,session_id:sid,role:'authenticated',aud:'authenticated',iss:origin+'/auth/v1',exp:now+600})).toString('base64url')+'.fixture';
const original=jwt(originalSID),successor=jwt(successorSID);
const pair=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk={...await crypto.subtle.exportKey('jwk',pair.publicKey),kid:'fixture',alg:'RS256',use:'sig'};
const b=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
const unsigned=b({alg:'RS256',kid:'fixture'})+'.'+b({iss:'https://appleid.apple.com',aud:'com.skworks.skWorks',sub:subject,iat:now,exp:now+600,nonce:await sha256Hex(nonce)});
const idToken=unsigned+'.'+Buffer.from(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',pair.privateKey,new TextEncoder().encode(unsigned))).toString('base64url');
const json=x=>new Response(JSON.stringify(x),{status:200,headers:{'content-type':'application/json'}});
function fixture(mode){const calls=[];let linked=false;
 const db={query:async(sql,args)=>{calls.push(['sql',sql,args]);
  if(sql.includes('claim_successor_attempt'))return{rows:[{r:mode==='claim-denied'?null:{request_id:request,status:'reserved',actor_id:actor,session_id:originalSID,subject,token_sha256:null,snapshot_sha256:'a'.repeat(64)}}]};
  if(sql.includes('complete_with_successor'))return{rows:[{r:mode==='completion-denied'?null:{linked:true,request_id:request,actor_id:actor,session_id:successorSID}}]};
  if(sql.includes('hold_apple_native_subject'))return{rows:[{r:true}]};return{rows:[]};},release:()=>{}};
 const query=db.query;db.query=async(sql,args)=>{const r=await query(sql,args);if(sql.includes('claim_successor_attempt')&&r.rows[0].r)r.rows[0].r.token_sha256=await sha256Hex(idToken);return r;};
 const config={enabled:true,nativeOnlyReviewed:true,successorReviewed:true,databaseReviewed:true,deliveryReviewed:true,audiences:['com.skworks.skWorks'],baseUrl:origin,publicKey:'sb_publishable_fixture'};
 const dependencies={now:()=>now,pool:{connect:async()=>db},resolveKey:async()=>jwk,
  fetcher:async(url,init)=>{calls.push(['http',url]);
   if(url.endsWith('/user'))return json({id:actor,is_anonymous:false,identities:linked?[{provider:'apple',identity_data:{sub:subject}}]:[{provider:'google',identity_data:{sub:'google-fixture'}}]});
   if(url.endsWith('grant_type=id_token')){assert.equal(calls.filter(x=>x[0]==='sql'&&x[1]==='commit').length,1,'claim must commit before Auth link');linked=true;return json({access_token:successor,refresh_token:'fixture-private-refresh',token_type:'bearer'});}throw Error('unexpected request');},
  deliverVerifiedSuccessor:async value=>{calls.push(['delivery']);assert.equal(value.user_id,actor);assert.equal(value.session_id,successorSID);assert.equal(value.refresh_token,'fixture-private-refresh');if(mode==='delivery-unknown')throw Error('private token');return true;}};
 return{calls,config,dependencies,input:{requestId:request,exactBearer:original,idToken,rawNonce:nonce}};
}
test('Auth HTTP and DB adapter modules compose with synthetic services in commit-link-complete-deliver order',async()=>{const f=fixture(),broker=createNativeAppleSuccessorBroker(f.config,f.dependencies);const r=await broker(f.input);assert.deepEqual(r,{linked:true,user_id:actor,session_id:successorSID});assert.equal(f.calls.filter(x=>x[0]==='delivery').length,1);assert.equal(f.calls.some(x=>x[0]==='http'&&x[1].includes('logout')),false);assert.equal(JSON.stringify(f.calls).includes('fixture-private-refresh'),false);await assert.rejects(broker(f.input));});
test('OFF rejects before HTTP/DB and a denied claim never links',async()=>{for(const mode of ['off','claim-denied']){const f=fixture(mode);if(mode==='off')f.config.enabled=false;await assert.rejects(createNativeAppleSuccessorBroker(f.config,f.dependencies)(f.input));assert.equal(f.calls.some(x=>x[0]==='http'&&x[1].includes('grant_type')),false);if(mode==='off')assert.equal(f.calls.length,0);}});
test('failed completion holds exact reserved request; lost delivery never replays or holds a completed request',async()=>{for(const mode of ['completion-denied','delivery-unknown']){const f=fixture(mode),broker=createNativeAppleSuccessorBroker(f.config,f.dependencies);await assert.rejects(broker(f.input),{message:'apple_successor_handoff_unavailable'});const holds=f.calls.filter(x=>x[0]==='sql'&&x[1].includes('hold_apple_native_subject'));assert.equal(holds.length,mode==='completion-denied'?1:0);if(holds.length)assert.deepEqual(holds[0][2],[request,actor,originalSID]);await assert.rejects(broker(f.input));assert.equal(f.calls.filter(x=>x[0]==='http'&&x[1].includes('grant_type')).length,1);}});
