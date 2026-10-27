// Internal verifier PORT only. No HTTP endpoint, challenge/proof store or Auth mutation.
// challenge and access must come from trusted server adapters, never request JSON.
import {sha256Hex} from './existing_apple_login.mjs';
export class GooglePrimaryDenied extends Error {
  constructor(){super('google_primary_verification_unavailable');}
}
const deny=()=>{throw new GooglePrimaryDenied();};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const opaque=/^[A-Za-z0-9_-]{43,128}$/;
function bytes(s){if(typeof s!=='string'||!/^[A-Za-z0-9_-]+$/.test(s))deny();try{return Uint8Array.from(atob(s.replaceAll('-','+').replaceAll('_','/')),x=>x.charCodeAt(0));}catch{deny();}}
function json(s){try{const x=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes(s)));if(!x||typeof x!=='object'||Array.isArray(x))deny();return x;}catch{deny();}}
function same(a,b){return JSON.stringify(a)===JSON.stringify(b);}
function googleSubjects(user){
 if(!Array.isArray(user?.identities))deny();
 return user.identities.filter(i=>i.provider==='google'&&i.user_id===user.id)
  .map(i=>i.identity_data?.sub).filter(s=>typeof s==='string'&&/^[A-Za-z0-9._-]{1,255}$/.test(s)).sort();
}
function actor(access,now){
 if(!access||!uuid.test(access.user?.id??'')||access.user.is_anonymous===true||
  access.claims?.sub!==access.user.id||access.claims.role!=='authenticated'||
  !uuid.test(access.claims.session_id??'')||!Number.isSafeInteger(access.claims.exp)||access.claims.exp<=now)deny();
 return {actor:access.user.id,session:access.claims.session_id,subjects:googleSubjects(access.user)};
}
export async function verifyGooglePrimary(input,ports){
 if(ports.enabled!==true||typeof input?.exactBearer!=='string'||!input.exactBearer||input.exactBearer.length>16384||
  typeof input.idToken!=='string'||input.idToken.length>16384||!opaque.test(input.challengeId??''))deny();
 const now=ports.now();if(!Number.isSafeInteger(now))deny();
 // Adapter must call GoTrue getUser on this exact bearer before decoding claims.
 const before=actor(await ports.authenticateExactBearer(input.exactBearer),now);
 if(!before.subjects.length)deny();
 const challenge=await ports.loadChallenge(input.challengeId);
 if(!challenge||challenge.actor_id!==before.actor||challenge.session_id!==before.session||
  !opaque.test(challenge.nonce??'')||typeof challenge.operation!=='string'||!challenge.operation||
  !challenge.target||typeof challenge.target!=='object'||Array.isArray(challenge.target)||
  !Number.isSafeInteger(challenge.issued_at)||!Number.isSafeInteger(challenge.expires_at)||
  challenge.issued_at>now||challenge.expires_at<=now||challenge.expires_at>challenge.issued_at+120||
  challenge.consumed===true)deny();
 const audiences=ports.audiences,presenters=ports.authorizedPresenters;
 if(!Array.isArray(audiences)||!audiences.length||audiences.length>8||audiences.some(x=>typeof x!=='string'||!x||x.length>255)||
  !Array.isArray(presenters)||presenters.length>8||presenters.some(x=>typeof x!=='string'||!x||x.length>255))deny();
 const p=input.idToken.split('.');if(p.length!==3)deny();const h=json(p[0]),c=json(p[1]);
 if(h.alg!=='RS256'||!/^[A-Za-z0-9_-]{1,128}$/.test(h.kid??'')||h.jku||h.x5u||
  !['https://accounts.google.com','accounts.google.com'].includes(c.iss)||
  typeof c.aud!=='string'||!audiences.includes(c.aud)||
  (c.azp!==undefined&&(typeof c.azp!=='string'||!presenters.includes(c.azp)))||
  !before.subjects.includes(c.sub)||c.nonce!==challenge.nonce||
  !Number.isSafeInteger(c.iat)||!Number.isSafeInteger(c.exp)||!Number.isSafeInteger(c.auth_time)||
  c.iat>now+60||c.iat<challenge.issued_at-5||c.exp<=now||c.exp<=c.iat||c.exp>c.iat+86400||
  c.auth_time>now+60||c.auth_time<challenge.issued_at-5||c.auth_time>c.iat||now-c.auth_time>300)deny();
 let jwk;try{jwk=await ports.resolveGoogleKey(h.kid);}catch{deny();}
 if(!jwk||jwk.kid!==h.kid||jwk.kty!=='RSA'||jwk.alg!=='RS256'||jwk.use!=='sig'||jwk.d||jwk.p||jwk.q)deny();
 try{
  const key=await crypto.subtle.importKey('jwk',jwk,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']);
  if(!await crypto.subtle.verify('RSASSA-PKCS1-v1_5',key,bytes(p[2]),new TextEncoder().encode(p[0]+'.'+p[1])))deny();
 }catch{deny();}
 // Revalidate the SAME bearer and identity history before consuming anything.
 const after=actor(await ports.authenticateExactBearer(input.exactBearer),ports.now());
 if(!same(before,after))deny();
 const binding={challengeId:input.challengeId,actor:before.actor,session:before.session,
  operation:challenge.operation,target:challenge.target,nonce:challenge.nonce,
  issuedAt:challenge.issued_at,expiresAt:challenge.expires_at,tokenHash:await sha256Hex(input.idToken)};
 // Existing proof protocol's future adapter must atomically check all fields,
 // live session/deletion barrier and expiry and consume once; a boolean from a client is forbidden.
 if(await ports.consumeChallenge(binding)!==true)deny();
 return Object.freeze({actor:before.actor,session:before.session,operation:challenge.operation,
  target:structuredClone(challenge.target),provider:'google',subject:c.sub,authenticatedAt:c.auth_time});
}
