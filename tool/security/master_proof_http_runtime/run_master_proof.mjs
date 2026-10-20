import fs from 'node:fs';
import {createReauthenticationHandler} from './handler.mjs';

const failureCodes=new Set(['config_keys','synthetic_credentials_only','distinct_actors_required','fixture_key_invalid','gateway_origin','route_not_allowed','gotrue_login_failed','gotrue_token_missing','wrong_password_accepted','wrong_scope_accepted','proof_issuance_failed','other_actor_accepted','collector_read_failed','reused_proof_accepted','platform_proof_issue_failed','platform_proof_reused_for_collector','original_session_lost','gotrue_session_missing']);
export class FixtureFailure extends Error {constructor(code){super(failureCodes.has(code)?code:'master_proof_http_failed');this.code=failureCodes.has(code)?code:'master_proof_http_failed';}}
export function safeFailure(error){return {verified:false,failure_code:error instanceof FixtureFailure&&failureCodes.has(error.code)?error.code:'master_proof_http_failed'};}
const check=(ok,code)=>{if(!ok)throw new FixtureFailure(code);};
export function configuration(value){
 check(value&&Object.keys(value).sort().join(',')==='admin,other,publicKey,serviceKey','config_keys');
 for(const name of ['admin','other'])check(value[name]&&Object.keys(value[name]).sort().join(',')==='email,password'&&/^sko-http-[a-z_]+-[a-f0-9]{12}@example\.invalid$/.test(value[name].email)&&/^Synthetic-[a-f0-9]{48}!A1$/.test(value[name].password),'synthetic_credentials_only');
 check(value.admin.email!==value.other.email,'distinct_actors_required');
 for(const name of ['publicKey','serviceKey'])check(typeof value[name]==='string'&&/^[A-Za-z0-9_.-]{20,4096}$/.test(value[name]),'fixture_key_invalid');
 return value;
}
export function route(url){
 const u=new URL(url);check(u.origin==='http://gateway.invalid'&&!u.hash&&!u.username&&!u.password,'gateway_origin');
 const allowedAuth=new Set(['/auth/v1/user','/auth/v1/token?grant_type=password','/auth/v1/logout?scope=local']);
 const path=u.pathname+u.search;
 if(allowedAuth.has(path))return 'http://auth:9999'+path.slice('/auth/v1'.length);
 if(['/rest/v1/rpc/reauthentication_capabilities','/rest/v1/rpc/issue_reauthentication_proof'].includes(path))return 'http://rest:3000'+path.slice('/rest/v1'.length);
 throw new FixtureFailure('route_not_allowed');
}
export async function run(value){
 const c=configuration(value);
 const http=async(url,options)=>fetch(url,{...options,redirect:'error',signal:AbortSignal.timeout(10000)});
 const login=async identity=>{
  const r=await http('http://auth:9999/token?grant_type=password',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(identity)});
  check(r.status===200,'gotrue_login_failed');const v=await r.json();check(typeof v.access_token==='string'&&v.user?.id,'gotrue_token_missing');return v.access_token;
 };
 const admin=await login(c.admin),other=await login(c.other);
 const handler=createReauthenticationHandler({baseUrl:'http://gateway.invalid',publicKey:c.publicKey,serviceKey:c.serviceKey,fetcher:(url,options)=>http(route(url),options)});
 const proof=async(operation,target,password=c.admin.password)=>{
  const r=await handler(new Request('http://function.invalid',{method:'POST',headers:{Authorization:'Bearer '+admin},body:JSON.stringify({operation,target,password})}));
  const v=await r.json();return {status:r.status,value:v};
 };
 const read=async(token,p)=>{
  const r=await http('http://rest:3000/rpc/sko_fixture_read_collector',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({p_proof:p})});
  const v=await r.json();return {status:r.status,value:v};
 };
 const target={scope:'decoy_collector'};
 const bad=await proof('master.security_collector.read',target,'Synthetic-wrong-password');check(bad.status===403&&!bad.value.proof,'wrong_password_accepted');
 const mismatch=await proof('master.security_collector.read',{scope:'platform'});check(mismatch.status===400&&!mismatch.value.proof,'wrong_scope_accepted');
 const first=await proof('master.security_collector.read',target);check(first.status===200&&/^[0-9a-f]{64}$/.test(first.value.proof),'proof_issuance_failed');
 const denied=await read(other,first.value.proof);check([401,403].includes(denied.status),'other_actor_accepted');
 const result=await read(admin,first.value.proof);check(result.status===200&&result.value.version===1&&Array.isArray(result.value.events),'collector_read_failed');
 const repeated=await read(admin,first.value.proof);check([401,403].includes(repeated.status),'reused_proof_accepted');
 const platform=await proof('master.security_incidents.read',{scope:'platform'});check(platform.status===200,'platform_proof_issue_failed');
 check([401,403].includes((await read(admin,platform.value.proof)).status),'platform_proof_reused_for_collector');
 const live=await http('http://auth:9999/user',{headers:{Authorization:'Bearer '+admin}});check(live.status===200,'original_session_lost');
 const session=JSON.parse(Buffer.from(admin.split('.')[1],'base64url').toString('utf8')).session_id;
 check(/^[a-f0-9-]{36}$/.test(session),'gotrue_session_missing');
 return {fixture_session_id:session,verified:true,real_gotrue_fixture_password:true,handler_to_issuer:true,one_time_consumer:true,wrong_password_denied:true,other_actor_denied:true,scope_bound:true,original_session_preserved:true,owner_google_verified:false};
}
if(process.argv[1]&&new URL(import.meta.url).pathname===process.argv[1]){
 try{const value=JSON.parse(fs.readFileSync(0,'utf8'));console.log(JSON.stringify(await run(value)));}
 // The wrapper reads verified/failure_code; returning JSON with exit 0 preserves
 // this fixed diagnostic without letting arbitrary exception text escape.
 catch(error){console.log(JSON.stringify(safeFailure(error)));}
}
