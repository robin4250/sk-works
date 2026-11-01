import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createReauthenticationHandler} from '../../supabase/functions/reauthenticate-operation/handler.mjs';
const actor='10000000-0000-0000-0000-000000000001';
const session='20000000-0000-0000-0000-000000000001';
const temporary='20000000-0000-0000-0000-000000000002';
const jwt=(sub=actor,sid=session,issuedAt=Date.now())=>'fixture.'+btoa(JSON.stringify({sub,session_id:sid,role:'authenticated',exp:Math.floor(issuedAt/1000)+600}))+'.synthetic';
const target={user_id:actor};
function fixture(overrides={}) {
 const calls=[]; let issued,temporaryAccessToken;
 const fetcher=async(url,options={})=>{
  const path=new URL(url).pathname+new URL(url).search; calls.push({path,options});
  if(overrides.throwAt===path)throw Error('synthetic sensitive upstream details');
  if(path==='/auth/v1/user')return Response.json(overrides.user??{id:actor,phone:'synthetic-phone'},{status:overrides.authStatus??200});
  if(path==='/rest/v1/rpc/reauthentication_capabilities')return Response.json({protocol:'sko-reauthentication-v1',secondary_password:overrides.enabled??true,master_feature:true,master_security:true,attendance_management:overrides.enabled??true},{status:overrides.capStatus??200});
  if(path==='/rest/v1/rpc/issue_secondary_reauthentication_proof'){
   if((overrides.secondaryStatus??200)!==200)return Response.json({error:'synthetic denied'},{status:overrides.secondaryStatus});
   if(overrides.secondaryResult===false)return Response.json(null);
   const body=JSON.parse(options.body);issued={...body,p_actor:actor,p_session:session};
   return Response.json(new Date(Date.now()+120000).toISOString());
  }
  if(path==='/auth/v1/token?grant_type=password'){
   // Mint earlier than assertion time: logout must use these exact issued bytes.
   temporaryAccessToken=jwt(overrides.verifiedActor??actor,overrides.tempSession??temporary,Date.now()-2000);
   return Response.json({user:{id:overrides.verifiedActor??actor},access_token:temporaryAccessToken,refresh_token:'NEVER_RETURN_THIS'},{status:overrides.passwordStatus??200});
  }
  if(path==='/auth/v1/logout?scope=local')return new Response(null,{status:overrides.logoutStatus??204});
  if(path==='/rest/v1/rpc/issue_reauthentication_proof') {issued=JSON.parse(options.body);return Response.json(new Date(Date.now()+120000).toISOString(),{status:overrides.issueStatus??200});}
  throw Error('Unexpected endpoint '+path);
 };
 const handler=createReauthenticationHandler({baseUrl:'https://fixture.invalid',publicKey:'public_fixture',serviceKey:'sb_'+'secret_'+'fixture-key',fetcher});
 return {calls,get temporaryAccessToken(){return temporaryAccessToken;},get issued(){return issued;},async invoke(body={operation:'secondary_password.replace',password:'synthetic-password',target},token=jwt()) {
  return handler(new Request('https://function.invalid',{method:'POST',headers:{Authorization:'Bearer '+token},body:JSON.stringify(body)}));
 }, handler};
}
test('verified credentials issue bound nonce only after distinct session logout; no returned auth credentials',async()=>{
 const f=fixture(); const r=await f.invoke(); assert.equal(r.status,200); const v=await r.json();
 assert.match(v.proof,/^[0-9a-f]{64}$/);assert.equal(v.operation,'secondary_password.replace');assert.deepEqual(v.target,target);
 assert.deepEqual(Object.keys(v).sort(),['expiresAt','operation','proof','protocol','target']);
 assert.equal(f.issued.p_actor,actor);assert.equal(f.issued.p_session,session);assert.notEqual(f.issued.p_proof_hash,v.proof);
 const passwordCall=f.calls.find(x=>x.path.includes('grant_type=password'));assert.equal(JSON.parse(passwordCall.options.body).phone,'synthetic-phone');
 const logout=f.calls.find(x=>x.path.includes('logout'));assert.equal(logout.options.headers.Authorization,'Bearer '+f.temporaryAccessToken);
 assert.ok(f.calls.findIndex(x=>x.path.includes('logout'))<f.calls.findIndex(x=>x.path.includes('issue_reauthentication')));
 const issue=f.calls.find(x=>x.path.includes('issue_reauthentication'));assert.equal(issue.options.headers.Authorization,undefined,'opaque key must not be JWT');
 assert.equal(JSON.stringify(v).includes('synthetic-password'),false);
});
for(const [label,changes,status] of [
 ['wrong password',{passwordStatus:400},403],['rate limit',{passwordStatus:429},429],['Auth unavailable',{authStatus:500},503],
 ['auth denied',{authStatus:401},401],['capability error',{capStatus:403},503],['rollout disabled',{enabled:false},403],
 ['different verified actor',{verifiedActor:'10000000-0000-0000-0000-000000000002'},403],
 ['temporary logout unconfirmed',{logoutStatus:500},503],['same session',{tempSession:session},503],['issuer error',{issueStatus:403},403],
 ['network error',{throwAt:'/auth/v1/token?grant_type=password'},503],
])test(label+' fails closed without proof',async()=>{
 const f=fixture(changes); const r=await f.invoke();assert.equal(r.status,status);assert.equal((await r.json()).proof,undefined);
 if(!changes.issueStatus)assert.equal(f.issued,undefined);
 if(changes.tempSession===session)assert.equal(f.calls.some(x=>x.path.includes('logout')),false);
});
test('client actor, target change, unknown operation, claimed biometric and refresh boolean rejected before password API',async()=>{
 for(const body of [
  {operation:'secondary_password.replace',password:'synthetic-password',target:{user_id:'10000000-0000-0000-0000-000000000002'}},
  {operation:'master.feature.set',password:'synthetic-password',target:{feature_key:'route_assignment',enabled:true,extra:true}},
  {operation:'master.feature.set',password:'synthetic-password',target:{feature_key:'unknown_feature',enabled:true}},
  {operation:'unknown',password:'synthetic-password',target},
  {operation:'secondary_password.replace',password:'synthetic-password',target,biometricVerified:true},
  {operation:'secondary_password.replace',password:'synthetic-password',target,refreshed:true},
 ]) {const f=fixture();assert.equal((await f.invoke(body)).status,400);assert.equal(f.calls.some(x=>x.path.includes('grant_type')),false);}
});
test('Master feature value and monitoring target passed unchanged to service issuer',async()=>{
 for(const [operation,t] of [['master.feature.set',{feature_key:'company_seal_image_tools',enabled:false}],['master.feature.set',{feature_key:'route_assignment',enabled:false}],['master.security_incidents.read',{scope:'platform'}]]) {
  const f=fixture();assert.equal((await f.invoke({operation,password:'synthetic-password',target:t})).status,200);assert.deepEqual(f.issued.p_target,t);
 }
});
test('JWT claims cannot replace Auth server identity',async()=>{
 const f=fixture();assert.equal((await f.invoke(undefined,jwt('10000000-0000-0000-0000-000000000002'))).status,401);assert.equal(f.issued,undefined);
});
test('chunked body without content length is cancelled at the byte limit before password verification',async()=>{
 const f=fixture();let cancelled=false;
 const body=new ReadableStream({pull(controller){controller.enqueue(new Uint8Array(1024).fill(65));},cancel(){cancelled=true;}});
 const r=await f.handler(new Request('https://function.invalid',{method:'POST',headers:{Authorization:'Bearer '+jwt()},body,duplex:'half'}));
 assert.equal(r.status,400);assert.equal(cancelled,true);assert.equal(f.calls.some(x=>x.path.includes('grant_type')),false);
});
test('UTF-8 byte limit rejects oversized multibyte JSON',async()=>{
 const f=fixture();const r=await f.invoke({operation:'secondary_password.replace',password:'あ'.repeat(1600),target});
 assert.equal(r.status,400);assert.equal(f.calls.some(x=>x.path.includes('grant_type')),false);
});
test('OAuth-only account without a password cannot be silently converted or issued proof',async()=>{
 const f=fixture({user:{id:actor,email:'synthetic@example.invalid'},passwordStatus:400});
 const r=await f.invoke();assert.equal(r.status,403);assert.equal(f.issued,undefined);
 assert.equal(f.calls.some(x=>x.path.includes('/admin/')||x.path.includes('issue_reauthentication')),false);
});

const attendanceTarget={company_id:'30000000-0000-0000-0000-000000000001',action:'upsert',items_sha256:'a'.repeat(64)};
test('attendance proof verifies actual secondary password with exact bearer, without primary Auth mutation',async()=>{
 const f=fixture();const r=await f.invoke({operation:'attendance.manage',password:'synthetic-secondary',target:attendanceTarget});
 assert.equal(r.status,200);assert.deepEqual(f.issued.p_target,attendanceTarget);assert.equal(f.issued.p_operation,'attendance.manage');
 const check=f.calls.find(x=>x.path.endsWith('/issue_secondary_reauthentication_proof'));
 assert.equal(check.options.headers.Authorization,'Bearer '+jwt());assert.equal(JSON.parse(check.options.body).p_password,'synthetic-secondary');
 assert.equal(JSON.parse(check.options.body).p_actor,undefined);assert.equal(JSON.parse(check.options.body).p_session,undefined);
 assert.equal(f.calls.some(x=>x.path.includes('/token')||x.path.includes('/logout')),false);
 assert.equal(f.calls.some(x=>x.path.endsWith('/issue_reauthentication_proof')),false);
 assert.equal(JSON.stringify(await r.json()).includes('synthetic-secondary'),false);
});
for(const [label,settings,status] of [['wrong secondary',{secondaryResult:false},403],['locked secondary',{secondaryStatus:403},403],['secondary unavailable',{secondaryStatus:500},503],['disabled attendance',{enabled:false},403]])test(label+' never issues proof',async()=>{
 const f=fixture(settings);assert.equal((await f.invoke({operation:'attendance.manage',password:'synthetic-secondary',target:attendanceTarget})).status,status);assert.equal(f.issued,undefined);
});
test('attendance malformed action/digest/company and extra target data fail before secondary verification',async()=>{
 for(const changed of [{action:'read'},{items_sha256:'bad'},{company_id:'bad'},{extra:true}]){
  const f=fixture();assert.equal((await f.invoke({operation:'attendance.manage',password:'synthetic-secondary',target:{...attendanceTarget,...changed}})).status,400);
  assert.equal(f.calls.some(x=>x.path.endsWith('/issue_secondary_reauthentication_proof')),false);assert.equal(f.issued,undefined);
 }
});
test('anonymous Auth user cannot obtain any proof',async()=>{
 const f=fixture({user:{id:actor,phone:'synthetic-phone',is_anonymous:true}});assert.equal((await f.invoke()).status,401);assert.equal(f.issued,undefined);
});

test('known secondary password change uses secondary verifier and exact existing user target',async()=>{
 const f=fixture();assert.equal((await f.invoke({operation:'secondary_password.change',password:'synthetic-secondary',target})).status,200);
 assert.equal(f.issued.p_operation,'secondary_password.change');assert.deepEqual(f.issued.p_target,target);
 assert.equal(f.calls.some(x=>x.path.endsWith('/issue_secondary_reauthentication_proof')),true);assert.equal(f.calls.some(x=>x.path.includes('/token')),false);
 const denied=fixture({secondaryResult:false});assert.equal((await denied.invoke({operation:'secondary_password.change',password:'synthetic-wrong',target})).status,403);assert.equal(denied.issued,undefined);
});


// The site control uses the same verified-actor/SID proof protocol as existing keys.
test('site document master proof binds both values and cleans the temporary session first',async()=>{
 for(const enabled of [true,false]) {
  const f=fixture();const target={feature_key:'site_order_documents',enabled};
  const response=await f.invoke({operation:'master.feature.set',password:'synthetic-password',target});
  assert.equal(response.status,200);const result=await response.json();
  assert.deepEqual(result.target,target);assert.deepEqual(f.issued.p_target,target);
  assert.equal(f.issued.p_actor,actor);assert.equal(f.issued.p_session,session);
  assert.equal(f.issued.p_operation,'master.feature.set');
  const cleanup=f.calls.findIndex(x=>x.path.includes('/auth/v1/logout'));
  const issue=f.calls.findIndex(x=>x.path.endsWith('/issue_reauthentication_proof'));
  assert.ok(cleanup>=0&&issue>cleanup);
  assert.equal(f.calls[cleanup].options.headers.Authorization,'Bearer '+f.temporaryAccessToken);
  assert.equal(response.headers.get('cache-control'),'no-store');
 }
});
test('site document master proof rejects malformed target before password authentication',async()=>{
 for(const target of [{feature_key:'site_order_documents',enabled:'true'},
  {feature_key:'site_order_documents',enabled:true,extra:true},
  {feature_key:'site_order_documents'}]) {
  const f=fixture();const response=await f.invoke({operation:'master.feature.set',password:'synthetic-password',target});
  assert.equal(response.status,400);assert.equal(f.issued,undefined);
  assert.equal(f.calls.some(x=>x.path.includes('grant_type')),false);
 }
});
