import test from 'node:test';
import assert from 'node:assert/strict';
import {handoffNativeAppleSuccessor} from './native_apple_successor_handoff.mjs';
import {sha256Hex} from './existing_apple_login.mjs';
const uid='00000000-0000-0000-0000-000000000001',sid='00000000-0000-0000-0000-000000000002',newSid='00000000-0000-0000-0000-000000000003',requestId='00000000-0000-0000-0000-000000000004';
const now=1800000000,nonce='n'.repeat(43),subject='verified-apple-subject';
const pair=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk={...await crypto.subtle.exportKey('jwk',pair.publicKey),kid:'synthetic-apple',use:'sig',alg:'RS256'};
const b=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
async function token(changes={}){const claims={iss:'https://appleid.apple.com',aud:'com.skworks.skWorks',sub:subject,iat:now,exp:now+600,nonce:await sha256Hex(nonce),...changes};const unsigned=b({alg:'RS256',kid:jwk.kid})+'.'+b(claims);return unsigned+'.'+Buffer.from(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',pair.privateKey,new TextEncoder().encode(unsigned))).toString('base64url');}

async function fixture(){const idToken=await token(),calls=[];const r={request_id:requestId,status:'reserved',actor_id:uid,session_id:sid,subject,token_sha256:await sha256Hex(idToken),snapshot_sha256:'a'.repeat(64)};
 const input={requestId,exactBearer:'original',idToken,rawNonce:nonce};
 const ports={enabled:true,successorReviewed:true,audiences:['com.skworks.skWorks'],now:()=>now,resolveKey:async()=>jwk,
 claimReservedForBearer:async()=>r,linkNativeIdentitySuccessor:async()=>{calls.push('link');return{access_token:'new-access',refresh_token:'private-refresh',token_type:'bearer'};},
 authenticateIssuedSession:async()=>({actor_id:uid,session_id:newSid,apple_subjects:[subject]}),
 completeWithSuccessor:async info=>{calls.push('complete');assert.equal(info.original_session_id,sid);assert.equal(info.successor_session_id,newSid);return{linked:true,request_id:requestId,actor_id:uid,session_id:newSid};},
 deliverVerifiedSuccessor:async c=>{calls.push('deliver');assert.equal(c.refresh_token,'private-refresh');return true;},holdSubject:async()=>calls.push('hold')};
 return {input,ports,calls,r};}
test('successor is delivered exactly once after verified atomic receipt; normal result has no credential',async()=>{const f=await fixture();assert.deepEqual(await handoffNativeAppleSuccessor(f.input,f.ports),{linked:true,user_id:uid,session_id:newSid});assert.deepEqual(f.calls,['link','complete','deliver']);});
test('OFF, foreign reservation or mismatched credential never links',async()=>{for(const mode of ['off','foreign','token']){const f=await fixture();if(mode==='off')f.ports.successorReviewed=false;if(mode==='foreign')f.r.request_id=sid;if(mode==='token')f.r.token_sha256='b'.repeat(64);await assert.rejects(handoffNativeAppleSuccessor(f.input,f.ports));assert.deepEqual(f.calls,[]);}});
test('foreign successor, wrong SID receipt or unknown completion never delivers and retains hold',async()=>{for(const mode of ['foreign','receipt','unknown']){const f=await fixture();if(mode==='foreign')f.ports.authenticateIssuedSession=async()=>({actor_id:sid,session_id:newSid,apple_subjects:[subject]});if(mode==='receipt')f.ports.completeWithSuccessor=async()=>({linked:true,request_id:requestId,actor_id:uid,session_id:sid});if(mode==='unknown')f.ports.completeWithSuccessor=async()=>{throw Error('private detail');};await assert.rejects(handoffNativeAppleSuccessor(f.input,f.ports),e=>e.message==='apple_successor_handoff_unavailable');assert.equal(f.calls.includes('deliver'),false);assert.equal(f.calls.at(-1),'hold');}});
test('lost delivery is never retried, revoked or rewritten as a held completed request',async()=>{const f=await fixture();f.ports.deliverVerifiedSuccessor=async()=>{f.calls.push('deliver');throw Error('credential must not appear');};await assert.rejects(handoffNativeAppleSuccessor(f.input,f.ports),e=>e.message==='apple_successor_handoff_unavailable');assert.deepEqual(f.calls,['link','complete','deliver']);});
