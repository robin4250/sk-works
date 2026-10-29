import test from 'node:test';
import assert from 'node:assert/strict';
import {createReauthenticationHandler} from '../../supabase/functions/reauthenticate-operation/handler.mjs';
const actor='10000000-0000-0000-0000-000000000001',sid='20000000-0000-0000-0000-000000000001',temporary='20000000-0000-0000-0000-000000000002';
const company='30000000-0000-0000-0000-000000000001',worker='40000000-0000-0000-0000-000000000001';
const jwt=session=>['e30',Buffer.from(JSON.stringify({sub:actor,role:'authenticated',session_id:session,exp:Math.floor(Date.now()/1000)+3600})).toString('base64url'),'synthetic'].join('.');
const original=jwt(sid),temp=jwt(temporary),target={company_id:company,worker_id:worker,input_sha256:'a'.repeat(64)};
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
function fixture({enabled=true,registered=false,wrongCompany=false,missing=false}={}) {
 const calls=[];const handler=createReauthenticationHandler({baseUrl:'https://bank-reauth-fixture.invalid',publicKey:'public_fixture',serviceKey:'service_fixture',fetcher:async(url,options)=>{
  const route=new URL(url);calls.push({path:route.pathname,options});
  if(route.pathname==='/auth/v1/user')return json({id:actor,email:'synthetic-bank@example.invalid',is_anonymous:false});
  if(route.pathname==='/rest/v1/rpc/employee_bank_initial_capability') {
   assert.deepEqual(JSON.parse(options.body),{p_company_id:company,p_worker_id:worker});assert.equal(options.headers.Authorization,`Bearer ${original}`);
   return missing?json({},404):json({protocol:'sko-employee-bank-initial-v1',enabled,registered,company_id:wrongCompany?'other':company,worker_id:worker,updated_at:null});
  }
  if(route.pathname==='/auth/v1/token') {assert.equal(JSON.parse(options.body).password,'synthetic-primary');return json({user:{id:actor},access_token:temp});}
  if(route.pathname==='/auth/v1/logout') {assert.equal(options.headers.Authorization,`Bearer ${temp}`);assert.equal(route.search,'?scope=local');return json({});}
  if(route.pathname==='/rest/v1/rpc/issue_reauthentication_proof') {
   const body=JSON.parse(options.body);assert.equal(body.p_actor,actor);assert.equal(body.p_session,sid);
   assert.equal(body.p_operation,'employee.bank.initial');assert.deepEqual(body.p_target,target);assert.match(body.p_proof_hash,/^[0-9a-f]{64}$/);
   assert.equal(options.headers.Authorization,'Bearer service_fixture');return json(new Date(Date.now()+120000).toISOString());
  }
  throw Error('Unexpected synthetic endpoint');
 }});
 const request=(override=target)=>handler(new Request('https://bank-reauth-fixture.invalid/reauthenticate-operation',{method:'POST',headers:{Authorization:`Bearer ${original}`,'Content-Type':'application/json'},body:JSON.stringify({password:'synthetic-primary',operation:'employee.bank.initial',target:override})}));
 return {calls,request};
}
test('manager bank uses genuine broker original SID and standard proof ledger route; no bank values sent to issuer',async()=>{
 const f=fixture(),response=await f.request();assert.equal(response.status,200);const proof=await response.json();
 assert.equal(proof.operation,'employee.bank.initial');assert.deepEqual(proof.target,target);assert.match(proof.proof,/^[0-9a-f]{64}$/);
 assert.deepEqual(f.calls.map(c=>c.path),['/auth/v1/user','/rest/v1/rpc/employee_bank_initial_capability','/auth/v1/token','/auth/v1/logout','/rest/v1/rpc/issue_reauthentication_proof']);
 assert.equal(f.calls.some(c=>/bank_name|account_number|account_holder/.test(c.options.body??'')),false);
});
for(const [label,options,status] of [['OFF',{enabled:false},403],['existing',{registered:true},403],['wrongscope',{wrongCompany:true},403],['absent',{missing:true},503]]) {
 test(`${label} capability denies before password verification without legacy fallback`,async()=>{
  const f=fixture(options);assert.equal((await f.request()).status,status);assert.equal(f.calls.length,2);
 });
}
for(const bad of [{...target,worker_id:'ABCDEF00-0000-0000-0000-000000000001'}, {...target,input_sha256:'A'.repeat(64)}, {...target,account_number:'synthetic-secret'}, {...target,worker_id:null}]) {
 test('malformed exact bank target denied before capability or password',async()=>{
  const f=fixture();assert.equal((await f.request(bad)).status,400);assert.equal(f.calls.length,1);
 });
}
