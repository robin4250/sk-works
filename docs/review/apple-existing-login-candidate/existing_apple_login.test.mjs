import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign} from 'node:crypto';
import {verifyAppleCredential,loginRegisteredApple,sha256Hex,AppleLoginDenied} from './existing_apple_login.mjs';
import {createHandler} from './handler.mjs';
const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});
const jwk={...publicKey.export({format:'jwk'}),kid:'fixture-key',alg:'RS256',use:'sig'};
const now=1800000000,nonce='a'.repeat(43),subject='registered.apple.subject',uid='30000000-0000-0000-0000-000000000001';
const origin='https://ztktgquxvcxcjxtluspu.supabase.co';
const before={user_id:uid,memberships:[{company_id:'synthetic-company',role:'owner'}],
 google_identities:[{id:'synthetic-google-id',provider_id:'original-google-subject'}]};
const user={id:uid,is_anonymous:false,identities:[{provider:'apple',user_id:uid,
 identity_data:{sub:subject}},{provider:'google',user_id:uid,identity_data:{sub:'original-google-subject'}}]};
const session={access_token:'synthetic-new-apple-access',refresh_token:'synthetic-refresh',expires_in:3600,token_type:'bearer',user};
const part=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
async function token(patch={},headerPatch={}){
 const h=part({alg:'RS256',kid:'fixture-key',...headerPatch});
 const p=part({iss:'https://appleid.apple.com',aud:'com.skworks.skWorks',sub:subject,
  iat:now,exp:now+3600,nonce:await sha256Hex(nonce),...patch});
 return h+'.'+p+'.'+sign('RSA-SHA256',Buffer.from(h+'.'+p),privateKey).toString('base64url');
}
function fixture(extra={}){
 const calls=[];const ports={enabled:true,audiences:['com.skworks.skWorks'],now:()=>now,
  resolveKey:async()=>jwk,consume:async()=>{calls.push('consume');return structuredClone(before);},
  exchange:async()=>{calls.push('exchange');return structuredClone(session);},
  verifyUser:async()=>{calls.push('verify');return structuredClone(user);},
  lookup:async()=>{calls.push('lookup');return structuredClone(before);},
  revokeLocal:async value=>calls.push('revoke-local:'+value),...extra};return {ports,calls};
}
const denied=p=>assert.rejects(p,AppleLoginDenied);

test('real RSA token resolves exact registered subject before exchange; preserves UID and memberships',async()=>{
 const {ports,calls}=fixture();const output=await loginRegisteredApple({idToken:await token(),rawNonce:nonce},ports);
 assert.equal(output.user.id,uid);assert.deepEqual(calls,['consume','exchange','verify','lookup']);
 assert.deepEqual(output.user.identities,user.identities);
});
test('tampered signed token never reaches identity resolution or Auth',async()=>{
 const {ports,calls}=fixture();let value=await token();const parts=value.split('.');parts[1]=part({iss:'https://appleid.apple.com',aud:'other'});
 await denied(loginRegisteredApple({idToken:parts.join('.'),rawNonce:nonce},ports));assert.deepEqual(calls,[]);
});
test('invalid issuer/audience/nonce/expiry/future or old issuance are rejected before any Auth operation',async()=>{
 for(const patch of [{iss:'https://attacker.invalid'},{aud:'another-app'},{nonce:'wrong'},
  {exp:now},{iat:now+61},{iat:now-301},{sub:''},{aud:['com.skworks.skWorks']}]){
  const {ports,calls}=fixture();await denied(loginRegisteredApple({idToken:await token(patch),rawNonce:nonce},ports));assert.deepEqual(calls,[]);
 }
});
test('unapproved algorithms or attacker-selected key URL cannot become valid credentials',async()=>{
 for(const patch of [{alg:'HS256'},{alg:'none'},{jku:'https://attacker.invalid/keys'},{x5u:'https://attacker.invalid/cert'}]){
  const {ports,calls}=fixture();await denied(loginRegisteredApple({idToken:await token({},patch),rawNonce:nonce},ports));assert.deepEqual(calls,[]);
 }
});
test('disabled broker cannot fetch keys, resolve identities or sign in',async()=>{
 const {ports,calls}=fixture({enabled:false,resolveKey:async()=>{throw Error('must not fetch');}});
 await denied(loginRegisteredApple({idToken:await token(),rawNonce:nonce},ports));assert.deepEqual(calls,[]);
});
test('an unregistered Apple subject is refused before GoTrue; no email lookup or signup fallback',async()=>{
 const {ports,calls}=fixture({consume:async()=>null});
 await denied(loginRegisteredApple({idToken:await token({email:'same-as-google@example.invalid'}),rawNonce:nonce},ports));assert.deepEqual(calls,[]);
});
test('a consumed token is never exchanged twice',async()=>{
 let consumed=false;const {ports,calls}=fixture({consume:async()=>{if(consumed)return null;consumed=true;return before;}});
 const input={idToken:await token(),rawNonce:nonce};await loginRegisteredApple(input,ports);
 await denied(loginRegisteredApple(input,ports));assert.equal(calls.filter(x=>x==='exchange').length,1);
});
test('wrong Auth UID revokes only its new Apple session and returns no credentials',async()=>{
 const {ports,calls}=fixture({exchange:async()=>({...session,user:{...user,id:'other-user'}})});
 await denied(loginRegisteredApple({idToken:await token(),rawNonce:nonce},ports));
 assert.deepEqual(calls,['consume','revoke-local:'+session.access_token]);
});
test('server getUser must confirm the exact Apple identity and non-anonymous actor',async()=>{
 for(const value of [{...user,id:'other-user'},{...user,is_anonymous:true},{...user,identities:[]}]){
  const {ports,calls}=fixture({verifyUser:async()=>value});
  await denied(loginRegisteredApple({idToken:await token(),rawNonce:nonce},ports));
  assert.equal(calls.at(-1),'revoke-local:'+session.access_token);
 }
});
test('changed company/role or Google identity aborts rather than transferring membership',async()=>{
 for(const after of [{...before,memberships:[{company_id:'another-company',role:'owner'}]},
  {...before,google_identities:[]}]){
  const {ports,calls}=fixture({lookup:async()=>after});
  await denied(loginRegisteredApple({idToken:await token(),rawNonce:nonce},ports));
  assert.equal(calls.at(-1),'revoke-local:'+session.access_token);
 }
});
test('missing configuration and malformed request fail closed without network calls',async()=>{
 let calls=0;const handler=createHandler({},async()=>{calls++;throw Error('no network');});
 assert.equal((await handler(new Request('https://local.invalid',{method:'POST'}))).status,503);assert.equal(calls,0);
});
test('HTTP adapter uses service credentials only for exact lookup/consume RPCs and returns same account',async()=>{
 const calls=[];const env={SKO_APPLE_EXISTING_LOGIN_ENABLED:'true',SUPABASE_URL:origin,
  SUPABASE_ANON_KEY:'synthetic-public',SUPABASE_SERVICE_ROLE_KEY:'synthetic.server.jwt',SKO_APPLE_AUDIENCES:'com.skworks.skWorks'};
 const network=async(url,options)=>{
  calls.push({url,options});let value;
  if(url==='https://appleid.apple.com/auth/keys'){assert.equal(options.headers,undefined);value={keys:[jwk]};}
  else if(url.includes('/rest/v1/rpc/')){
   assert.ok(url.endsWith('/consume_existing_apple_login')||url.endsWith('/resolve_existing_apple_login'));
   assert.equal(options.headers.apikey,env.SUPABASE_SERVICE_ROLE_KEY);value=before;
  }else if(url.endsWith('/token?grant_type=id_token')){
   assert.equal(options.headers.apikey,env.SUPABASE_ANON_KEY);assert.equal(options.headers.Authorization,undefined);
   assert.equal(JSON.parse(options.body).provider,'apple');value=session;
  }else if(url.endsWith('/user')){assert.equal(options.headers.Authorization,'Bearer '+session.access_token);value=user;}
  else throw Error('unexpected route');
  return new Response(JSON.stringify(value),{status:200,headers:{'content-type':'application/json'}});
 };
 const handler=createHandler(env,network,()=>now);
 const result=await handler(new Request('https://local.invalid',{method:'POST',headers:{'content-type':'application/json'},
  body:JSON.stringify({id_token:await token(),nonce})}));
 assert.equal(result.status,200);assert.equal(result.headers.get('cache-control'),'no-store');
 assert.equal((await result.json()).user.id,uid);assert.equal(calls.some(x=>/signup|admin|link|logout/.test(x.url)),false);
});
test('HTTP adapter rejects extra user fields before network rather than trusting client account IDs',async()=>{
 const env={SKO_APPLE_EXISTING_LOGIN_ENABLED:'true',SUPABASE_URL:origin,SUPABASE_ANON_KEY:'public',
  SUPABASE_SERVICE_ROLE_KEY:'synthetic.server.jwt',SKO_APPLE_AUDIENCES:'com.skworks.skWorks'};
 let calls=0;const handler=createHandler(env,async()=>{calls++;throw Error('no network');});
 const result=await handler(new Request('https://local.invalid',{method:'POST',headers:{'content-type':'application/json'},
  body:JSON.stringify({id_token:'irrelevant',nonce,user_id:uid})}));
 assert.equal(result.status,403);assert.equal(calls,0);
});
