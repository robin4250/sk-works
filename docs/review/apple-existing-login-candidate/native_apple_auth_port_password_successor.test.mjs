import test from 'node:test';
import assert from 'node:assert/strict';
import {createNativeAppleAuthPorts} from './native_apple_auth_port.mjs';
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const origin='https://ztktgquxvcxcjxtluspu.supabase.co',now=1800000000;
const jwt=(actor,sid)=>'eyJhbGciOiJSUzI1NiJ9.'+Buffer.from(JSON.stringify({sub:actor,session_id:sid,role:'authenticated',aud:'authenticated',iss:origin+'/auth/v1',exp:now+60})).toString('base64url')+'.fixture';
const original=jwt(id(1),id(2)),next=jwt(id(1),id(3)),foreign=jwt(id(4),id(5));
const json=(value,status=200)=>new Response(JSON.stringify(value),{status});
function fixture(mode){const calls=[];
 const p=createNativeAppleAuthPorts({enabled:true,nativeOnlyReviewed:true,successorReviewed:true,
  passwordSuccessorReviewed:mode!=='off',baseUrl:origin,publicKey:'sb_publishable_fixture',now:()=>now,
  fetcher:async(url,init)=>{calls.push({url,body:init.body});
   if(url.endsWith('/user')){const access=init.headers.Authorization.slice(7);return json({id:access===foreign?id(4):id(1),email:'server-owned@example.invalid',is_anonymous:false,identities:[{provider:'google',provider_id:'fixture'}]});}
   if(url.includes('grant_type=password')){
    if(mode==='wrong-password')return json({error:'bad credential'},400);
    return json({access_token:mode==='foreign'?foreign:mode==='same-session'?original:next,
     refresh_token:mode==='missing-refresh'?null:'fixture-refresh',token_type:'bearer',user:{id:mode==='foreign'?id(4):id(1)}});
   }throw Error('unexpected HTTP');}});
 return {p,calls};}
test('password successor keeps same UID and preserves new credential without logout or relinking',async()=>{
 const {p,calls}=fixture();await p.bindOriginal(original);
 const result=await p.authenticatePrimaryPasswordSuccessor({exactBearer:original,password:'fixture-password',email:'ignored@example.invalid'});
 assert.equal(result.actor_id,id(1));assert.equal(result.original_session_id,id(2));assert.equal(result.session_id,id(3));
 assert.equal(result.refresh_token,'fixture-refresh');
 assert.deepEqual(JSON.parse(calls.find(x=>x.url.includes('grant_type=password')).body),{email:'server-owned@example.invalid',password:'fixture-password'});
 assert.equal(calls.some(x=>/logout|link_identity/.test(x.url)),false);
 await assert.rejects(p.authenticatePrimaryPasswordSuccessor({exactBearer:original,password:'fixture-password'}));
 assert.equal(calls.filter(x=>x.url.includes('grant_type=password')).length,1);
});
test('review OFF and bearer substitution never send password',async()=>{
 for(const mode of ['off','bearer']){const {p,calls}=fixture(mode);await p.bindOriginal(original);
 await assert.rejects(p.authenticatePrimaryPasswordSuccessor({exactBearer:mode==='bearer'?next:original,password:'fixture-password'}));
 assert.equal(calls.some(x=>x.url.includes('grant_type=password')),false);}
});
test('wrong UID, unchanged SID and absent refresh are rejected without automatic retry',async()=>{
 for(const mode of ['foreign','same-session','missing-refresh','wrong-password']){const {p,calls}=fixture(mode);await p.bindOriginal(original);
 await assert.rejects(p.authenticatePrimaryPasswordSuccessor({exactBearer:original,password:'fixture-password'}));
 await assert.rejects(p.authenticatePrimaryPasswordSuccessor({exactBearer:original,password:'fixture-password'}));
 assert.equal(calls.filter(x=>x.url.includes('grant_type=password')).length,1);
 assert.equal(calls.some(x=>x.url.includes('logout')),false);}
});
