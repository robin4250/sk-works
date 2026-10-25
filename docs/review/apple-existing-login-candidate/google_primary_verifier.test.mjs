import test from 'node:test';
import assert from 'node:assert/strict';
import {verifyGooglePrimary,GooglePrimaryDenied} from './google_primary_verifier.mjs';
import {createGooglePrimaryPorts} from './google_primary_ports.mjs';
const now=1800000000,actor='00000000-0000-0000-0000-000000000001',sid='00000000-0000-0000-0000-000000000002';
const pair=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk={...await crypto.subtle.exportKey('jwk',pair.publicKey),kid:'fixture-google',alg:'RS256',use:'sig'};
const b=x=>Buffer.from(typeof x==='string'?x:JSON.stringify(x)).toString('base64url');
async function token(changes={},header={}){const c={iss:'https://accounts.google.com',aud:'web-client',azp:'ios-client',sub:'existing-google-subject',nonce:'n'.repeat(43),iat:now,exp:now+3600,auth_time:now,...changes};const s=b({alg:'RS256',kid:jwk.kid,...header})+'.'+b(c);return s+'.'+Buffer.from(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',pair.privateKey,new TextEncoder().encode(s))).toString('base64url');}
const access=()=>({user:{id:actor,is_anonymous:false,identities:[{provider:'google',user_id:actor,identity_data:{sub:'existing-google-subject'}}]},claims:{sub:actor,role:'authenticated',session_id:sid,exp:now+600}});
function fixture(){let consumed=false;const calls=[];const challenge={actor_id:actor,session_id:sid,nonce:'n'.repeat(43),operation:'secondary_password.replace',target:{user_id:actor},issued_at:now,expires_at:now+120};return{calls,challenge,ports:{enabled:true,now:()=>now,audiences:['web-client'],authorizedPresenters:['ios-client'],authenticateExactBearer:async bearer=>{calls.push(['getUser',bearer]);return access();},loadChallenge:async id=>{calls.push(['load',id]);return structuredClone(challenge);},resolveGoogleKey:async()=>jwk,consumeChallenge:async binding=>{calls.push(['consume',binding]);if(consumed)return false;consumed=true;return true;}}};}
const input=async changes=>({exactBearer:'original-exact-bearer',challengeId:'c'.repeat(43),idToken:await token(changes)});
test('real Google RSA credential returns server-only evidence for exact existing actor/session/op, no Auth exchange',async()=>{const f=fixture();const r=await verifyGooglePrimary(await input(),f.ports);assert.deepEqual(r,{actor,session:sid,operation:'secondary_password.replace',target:{user_id:actor},provider:'google',subject:'existing-google-subject',authenticatedAt:now});assert.deepEqual(f.calls.map(x=>x[0]),['getUser','load','getUser','consume']);assert.match(f.calls.at(-1)[1].tokenHash,/^[a-f0-9]{64}$/);assert.equal('proof' in r,false);});
test('wrong Google subject with same email is denied without consuming challenge',async()=>{const f=fixture();await assert.rejects(verifyGooglePrimary(await input({sub:'different-google',email:'same@example.test'}),f.ports),GooglePrimaryDenied);assert.equal(f.calls.some(x=>x[0]==='consume'),false);});
test('nonce, audience, presenter, issuer and fresh auth_time are mandatory',async()=>{for(const changes of[{nonce:'wrong'},{aud:'other'},{azp:'other'},{iss:'https://attacker.test'},{auth_time:undefined},{auth_time:now-10},{auth_time:now+61},{exp:now},{iat:now-10},{aud:['web-client']}]){const f=fixture();await assert.rejects(verifyGooglePrimary(await input(changes),f.ports),GooglePrimaryDenied);assert.equal(f.calls.some(x=>x[0]==='consume'),false);}});
test('a newly issued token cannot substitute for old Google authentication',async()=>{const f=fixture();await assert.rejects(verifyGooglePrimary(await input({iat:now,auth_time:now-3600}),f.ports),GooglePrimaryDenied);});
test('tampered RSA signature and attacker key URLs are rejected',async()=>{let f=fixture();let i=await input();i.idToken=i.idToken.slice(0,-8)+'aaaaaaaa';await assert.rejects(verifyGooglePrimary(i,f.ports),GooglePrimaryDenied);for(const h of[{alg:'none'},{alg:'HS256'},{jku:'https://attacker.test/keys'},{x5u:'https://attacker.test/key'}]){f=fixture();await assert.rejects(verifyGooglePrimary({...await input(),idToken:await token({},h)},f.ports),GooglePrimaryDenied);}});
test('missing, expired, consumed or other-session challenge never yields proof',async()=>{for(const changes of[{actor_id:'other'},{session_id:'other'},{expires_at:now},{expires_at:now+121},{issued_at:now+1},{consumed:true},{nonce:'bad'}]){const f=fixture();Object.assign(f.challenge,changes);await assert.rejects(verifyGooglePrimary(await input(),f.ports),GooglePrimaryDenied);assert.equal(f.calls.some(x=>x[0]==='consume'),false);}});
test('challenge is consumed once even for a still-valid Google token',async()=>{const f=fixture(),i=await input();await verifyGooglePrimary(i,f.ports);await assert.rejects(verifyGooglePrimary(i,f.ports),GooglePrimaryDenied);});
test('server actor/session/Google identity change during verification aborts consumption',async()=>{for(const change of[a=>{a.user.id='00000000-0000-0000-0000-000000000003';},a=>{a.claims.session_id='00000000-0000-0000-0000-000000000004';},a=>{a.user.identities=[];}]){const f=fixture();let n=0;f.ports.authenticateExactBearer=async()=>{const a=access();if(++n===2)change(a);return a;};await assert.rejects(verifyGooglePrimary(await input(),f.ports),GooglePrimaryDenied);assert.equal(f.calls.some(x=>x[0]==='consume'),false);}});
test('atomic challenge/session/deletion failure returns no evidence',async()=>{const f=fixture();f.ports.consumeChallenge=async()=>false;await assert.rejects(verifyGooglePrimary(await input(),f.ports),GooglePrimaryDenied);});
test('OFF port performs no credential, session or challenge operation',async()=>{const f=fixture();f.ports.enabled=false;await assert.rejects(verifyGooglePrimary(await input(),f.ports),GooglePrimaryDenied);assert.deepEqual(f.calls,[]);});
test('real server adapters pin Google JWKS and send original bearer only to exact GoTrue user endpoint',async()=>{
 const f=fixture(),calls=[];const bearer=b({alg:'fixture'})+'.'+b(access().claims)+'.fixture';
 const ports=createGooglePrimaryPorts({enabled:true,baseUrl:'https://ztktgquxvcxcjxtluspu.supabase.co',publicKey:'synthetic-public',
  audiences:['web-client'],authorizedPresenters:['ios-client'],loadChallenge:f.ports.loadChallenge,consumeChallenge:f.ports.consumeChallenge,now:()=>now,
  fetcher:async(url,init)=>{calls.push({url,init});if(url==='https://www.googleapis.com/oauth2/v3/certs')return Response.json({keys:[jwk]});
   assert.equal(url,'https://ztktgquxvcxcjxtluspu.supabase.co/auth/v1/user');assert.equal(init.headers.Authorization,'Bearer '+bearer);return Response.json(access().user);}});
 await verifyGooglePrimary({...await input(),exactBearer:bearer},ports);
 assert.equal(calls.filter(x=>x.url.includes('googleapis')).length,1);
 assert.equal(calls.filter(x=>x.url.endsWith('/user')).length,2);
 assert.equal(calls.every(x=>x.init.method==='GET'&&x.init.redirect==='error'),true);
 assert.equal(calls.find(x=>x.url.includes('googleapis')).init.headers.Authorization,undefined);
});
test('missing challenge adapters or another project keeps server adapter OFF without network',async()=>{
 let calls=0;
 for(const cfg of[{baseUrl:'https://attacker.test'},{baseUrl:'https://ztktgquxvcxcjxtluspu.supabase.co'}]){
  const p=createGooglePrimaryPorts({enabled:true,publicKey:'synthetic-public',...cfg,fetcher:async()=>{calls++;throw Error('forbidden');}});
  await assert.rejects(verifyGooglePrimary(await input(),p),GooglePrimaryDenied);
 }assert.equal(calls,0);
});
