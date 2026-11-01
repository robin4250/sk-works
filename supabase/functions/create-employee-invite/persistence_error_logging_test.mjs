import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';

test('Invite failures preserve existing employees and omit raw upstream/cleanup details', async()=>{
 const originalFetch=globalThis.fetch,originalDeno=globalThis.Deno,originalError=console.error;
 const actor='10000000-0000-0000-0000-000000000001',worker='40000000-0000-0000-0000-000000000001',authUser='50000000-0000-0000-0000-000000000001',company='30000000-0000-0000-0000-000000000001';
 const markers=['synthetic-person@example.invalid','synthetic-private-phone','synthetic-token-value','synthetic-password-value'];
 let handler,scenario,existingRow,newRow,bodyReads=0;const logs=[],calls=[];
 const initialRow={id:worker,name:'Synthetic Employee',phone:'07000000000',user_id:null,company_id:company,status:'inactive',unrelated_field:'preserve'};
 globalThis.Deno={env:{get:name=>({SUPABASE_URL:'https://fixture.invalid',SUPABASE_SERVICE_ROLE_KEY:'fixture-service-key',SKO_EMPLOYEE_INVITE_SMS_WEBHOOK:'https://sms.fixture.invalid/deliver'}[name])},serve:value=>{handler=value;}};
 console.error=(...args)=>logs.push(args);
 function failure(status=409){const response=new Response(JSON.stringify({code:'23505',details:markers.join(' ')}),{status});const text=response.text.bind(response);response.text=async()=>{bodyReads++;return text();};return response;}
 function invalidJson(){const response=Response.json({});response.json=async()=>{throw Error(markers.join(' '));};return response;}
 globalThis.fetch=async(url,options={})=>{
  const u=new URL(url),method=options.method??'GET',body=options.body?JSON.parse(options.body):null;calls.push({path:u.pathname,query:u.searchParams,method,body});
  if(u.hostname==='sms.fixture.invalid')throw Error(markers.join(' ')+JSON.stringify(body));
  if(u.pathname==='/auth/v1/settings')return Response.json({external:{phone:true}});
  if(u.pathname==='/auth/v1/user')return Response.json({id:actor});
  if(u.pathname==='/rest/v1/rpc/account_server_access_allowed')return Response.json(true);
  if(u.pathname==='/rest/v1/rpc/finish_account_server_activity')return Response.json(true);
  if(u.pathname==='/rest/v1/companies')return Response.json([{employee_testflight_url:'https://fixture.invalid/testflight'}]);
  if(u.pathname==='/rest/v1/rpc/begin_account_server_activity')return Response.json('20000000-0000-0000-0000-000000000001');
  if(u.pathname==='/rest/v1/company_members')return Response.json([{company_id:company,role:'owner'}]);
  if(u.pathname==='/auth/v1/admin/users'&&method==='POST')return Response.json({id:authUser});
  if(u.pathname==='/auth/v1/admin/users/'+authUser&&method==='DELETE'){
   if(scenario.cleanup==='auth-http')return failure(503);
   if(scenario.cleanup==='auth-throw')throw Error(markers.join(' '));
   return Response.json({});
  }
  if(u.pathname==='/rest/v1/workers'){
   if(method==='GET')return Response.json([existingRow]);
   const isCleanup=method==='DELETE'||(method==='PATCH'&&body.user_id===null);
   if(isCleanup){
    assert.equal(u.searchParams.get('user_id'),'eq.'+authUser,'cleanup is scoped to this attempt’s expected linkage');
    if(scenario.cleanup==='worker-http')return failure(503);
    if(scenario.cleanup==='worker-throw')throw Error(markers.join(' '));
    if(method==='DELETE'){assert.equal(scenario.existing,false,'existing employee may never be deleted');newRow=null;}
    else if(existingRow.user_id===authUser)Object.assign(existingRow,body);
    return Response.json({});
   }
   if(scenario.fail==='worker-http')return failure();
   if(scenario.fail==='worker-throw')throw Error(markers.join(' '));
   if(method==='POST'){
    newRow={id:worker,...body};
    if(scenario.fail==='worker-json')return invalidJson();
    return Response.json([{id:worker}]);
   }
   assert.equal(u.searchParams.get('company_id'),'eq.'+company);
   assert.equal(u.searchParams.get('user_id'),'is.null');
   assert.equal(options.headers.Prefer,'return=representation');
   if(scenario.fail==='worker-zero')return Response.json([]);
   if(scenario.fail==='worker-reassigned'){existingRow.user_id='60000000-0000-0000-0000-000000000001';return Response.json([]);}
   Object.assign(existingRow,body);
   if(scenario.fail==='worker-json')return invalidJson();
   return Response.json([{id:worker}]);
  }
  if(u.pathname==='/rest/v1/employee_registration_invites'){
   if(method==='GET')return Response.json([]);
   if(scenario.concurrent)existingRow.user_id='60000000-0000-0000-0000-000000000001';
   if(scenario.fail==='invite-http')return failure();
   if(scenario.fail==='invite-throw')throw Error(markers.join(' '));
   if(scenario.fail==='invite-json')return invalidJson();
   return Response.json([{id:'70000000-0000-0000-0000-000000000001'}]);
  }
  throw Error('Unexpected fixture request '+u.pathname);
 };
 try{
  const sourceUrl=new URL('./index.ts',import.meta.url),source=fs.readFileSync(sourceUrl,'utf8').replace('import "jsr:@supabase/functions-js/edge-runtime.d.ts";','').replace(/from '([^']+\.mjs)'/g,(_,path)=>'from '+JSON.stringify(new URL(path,sourceUrl).href));
  await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'strip'})).toString('base64'));
  const scenarios=[];
  for(const existing of [false,true])for(const fail of ['worker-http','worker-throw','invite-http','invite-throw','invite-json'])scenarios.push({existing,fail});
  for(const existing of [false,true])scenarios.push({existing,fail:'worker-json'});
  scenarios.push({existing:true,fail:'worker-zero'},{existing:true,fail:'worker-reassigned'});
  for(const cleanup of ['worker-http','worker-throw','auth-http','auth-throw'])for(const existing of [false,true])scenarios.push({existing,fail:'invite-http',cleanup});
  scenarios.push({existing:true,fail:'invite-http',concurrent:true});
  for(scenario of scenarios){
   logs.length=0;calls.length=0;existingRow=structuredClone(initialRow);newRow=null;
   const payload=scenario.existing?{workerId:worker}:{name:'Synthetic Employee',phone:'07000000000'};
   const response=await handler(new Request('https://fixture.invalid/invite',{method:'POST',headers:{authorization:'Bearer fixture-user'},body:JSON.stringify(payload)}));
   assert.equal(response.headers.get('cache-control'),'no-store');
   assert.equal(response.headers.get('x-content-type-options'),'nosniff');
   assert.equal(response.headers.get('referrer-policy'),'no-referrer');
   assert.equal(response.status,500,JSON.stringify(scenario));assert.deepEqual(await response.json(),{error:'従業員登録を保存できませんでした。'});
   assert.deepEqual(logs[0],['employee invite persistence failed',scenario.fail.startsWith('worker')?'worker':'invite',scenario.fail.endsWith('http')?409:null]);
   for(const marker of markers)assert.equal(JSON.stringify(logs).includes(marker),false);
   assert.equal(bodyReads,0,'PostgREST error details are never read');
   const cleanup=calls.filter(x=>x.method==='DELETE'||(x.method==='PATCH'&&x.body?.user_id===null));
   const expected=[];
   const workerCreatedOrLinked=!['worker-http','worker-throw'].includes(scenario.fail);
   if(workerCreatedOrLinked)expected.push({path:'/rest/v1/workers',method:scenario.existing?'PATCH':'DELETE',body:scenario.existing?{user_id:null,status:initialRow.status}:null});
   expected.push({path:'/auth/v1/admin/users/'+authUser,method:'DELETE',body:null});
   assert.deepEqual(cleanup.map(({path,method,body})=>({path,method,body})),expected,'worker cleanup then created Auth user cleanup');
   assert.equal(calls.filter(x=>x.path==='/rest/v1/rpc/account_server_access_allowed').length,2);
   const expectedExisting=structuredClone(initialRow);
   const successfulLink=calls.find(x=>x.path==='/rest/v1/workers'&&x.method==='PATCH'&&x.body?.user_id===authUser);
   if(scenario.existing&&successfulLink&&!['worker-http','worker-throw','worker-zero','worker-reassigned'].includes(scenario.fail))Object.assign(expectedExisting,successfulLink.body,{user_id:null,status:initialRow.status});
   if(scenario.concurrent){Object.assign(expectedExisting,successfulLink.body);expectedExisting.user_id='60000000-0000-0000-0000-000000000001';}
   else if(scenario.fail==='worker-reassigned')expectedExisting.user_id='60000000-0000-0000-0000-000000000001';
   else if(scenario.existing&&scenario.cleanup?.startsWith('worker'))Object.assign(expectedExisting,successfulLink.body);
   assert.deepEqual(existingRow,expectedExisting,'existing employee fields and unrelated concurrent linkage are preserved');
   if(!scenario.existing&&workerCreatedOrLinked&&!scenario.cleanup?.startsWith('worker'))assert.equal(newRow,null);
   if(scenario.cleanup){assert.equal(logs.length,2);assert.equal(logs[1][0],'employee invite '+(scenario.cleanup.startsWith('worker')?'worker':'auth')+' cleanup failed');}
   else assert.equal(logs.length,1);
  }
  for(const existing of [false,true])for(const sms of [false,true]){
   scenario={existing,fail:'none',sms};logs.length=0;calls.length=0;existingRow=structuredClone(initialRow);newRow=null;
   const payload=existing?{workerId:worker,deliverSms:sms}:{name:'Synthetic Employee',phone:'07000000000',deliverSms:sms};
   const response=await handler(new Request('https://fixture.invalid/invite',{method:'POST',headers:{authorization:'Bearer fixture-user'},body:JSON.stringify(payload)}));
   assert.equal(response.headers.get('cache-control'),'no-store');
   assert.equal(response.status,200);const result=await response.json();
   assert.equal(result.smsSent,false);
   if(sms)assert.equal(result.deliveryMessage,'SMS送信サービスへ接続できませんでした。');
   assert.equal(result.phone,'+817000000000');
   assert.equal(JSON.parse(result.qrPayload).type,'sko_employee_invite');
   assert.equal(JSON.parse(result.qrPayload).inviteId,result.inviteId);
   assert.deepEqual(logs,sms?[['employee invite sms delivery failed']]:[]);
   for(const marker of markers)assert.equal(JSON.stringify(logs).includes(marker),false);
   assert.equal(JSON.stringify(logs).includes(result.temporaryPassword),false);
   assert.equal(JSON.stringify(logs).includes(result.qrPayload),false);
   assert.equal(calls.some(x=>x.method==='DELETE'),false);
   assert.equal(calls.filter(x=>x.path==='/rest/v1/rpc/finish_account_server_activity').length,1);
   if(existing)assert.equal(existingRow.user_id,authUser);else assert.equal(newRow.user_id,authUser);
  }
 }finally{globalThis.fetch=originalFetch;globalThis.Deno=originalDeno;console.error=originalError;}
});
