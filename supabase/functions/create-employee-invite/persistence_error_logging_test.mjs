import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';

test('Persistence failures omit upstream details and retain each rollback contract', async()=>{
 const originalFetch=globalThis.fetch,originalDeno=globalThis.Deno,originalError=console.error;
 const actor='10000000-0000-0000-0000-000000000001',worker='40000000-0000-0000-0000-000000000001',authUser='50000000-0000-0000-0000-000000000001';
 const markers=['synthetic-person@example.invalid','synthetic-private-phone','synthetic-token-value','synthetic-password-value'];
 let handler,scenario,bodyReads=0;const logs=[],calls=[];
 globalThis.Deno={env:{get:name=>({SUPABASE_URL:'https://fixture.invalid',SUPABASE_SERVICE_ROLE_KEY:'fixture-service-key'}[name])},serve:value=>{handler=value;}};
 console.error=(...args)=>logs.push(args);
 function failure(){const response=new Response(JSON.stringify({code:'23505',details:markers.join(' ')}),{status:409});const text=response.text.bind(response);response.text=async()=>{bodyReads++;return text();};return response;}
 globalThis.fetch=async(url,options={})=>{
  const u=new URL(url),method=options.method??'GET';calls.push({path:u.pathname,method,body:options.body?JSON.parse(options.body):null});
  if(u.pathname==='/auth/v1/user')return Response.json({id:actor});
  if(u.pathname==='/rest/v1/rpc/account_server_access_allowed')return Response.json(true);
  if(u.pathname==='/rest/v1/rpc/begin_account_server_activity')return Response.json('20000000-0000-0000-0000-000000000001');
  if(u.pathname==='/rest/v1/company_members')return Response.json([{company_id:'30000000-0000-0000-0000-000000000001',role:'owner'}]);
  if(u.pathname==='/auth/v1/admin/users'&&method==='POST')return Response.json({id:authUser});
  if(u.pathname==='/auth/v1/admin/users/'+authUser&&method==='DELETE')return Response.json({});
  if(u.pathname==='/rest/v1/workers'){
   if(method==='GET')return Response.json([{id:worker,name:'Synthetic Employee',phone:'07000000000',user_id:null}]);
   if(method==='DELETE'||(method==='PATCH'&&JSON.parse(options.body).user_id===null))return Response.json({});
   if(scenario.stage==='worker')return failure();
   return Response.json([{id:worker}]);
  }
  if(u.pathname==='/rest/v1/employee_registration_invites'){
   if(method==='GET')return Response.json([]);
   if(scenario.stage==='invite')return failure();
   throw Error(markers.join(' '));
  }
  throw Error('Unexpected fixture request '+u.pathname);
 };
 try{
  const sourceUrl=new URL('./index.ts',import.meta.url),source=fs.readFileSync(sourceUrl,'utf8').replace('import "jsr:@supabase/functions-js/edge-runtime.d.ts";','').replace(/from '([^']+\.mjs)'/g,(_,path)=>'from '+JSON.stringify(new URL(path,sourceUrl).href));
  await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'strip'})).toString('base64'));
  for(scenario of [{stage:'worker',existing:false},{stage:'worker',existing:true},{stage:'invite',existing:false},{stage:'invite',existing:true},{stage:'exception',existing:false}]){
   logs.length=0;calls.length=0;
   const payload=scenario.existing?{workerId:worker}:{name:'Synthetic Employee',phone:'07000000000'};
   const response=await handler(new Request('https://fixture.invalid/invite',{method:'POST',headers:{authorization:'Bearer fixture-user'},body:JSON.stringify(payload)}));
   assert.equal(response.status,500);assert.deepEqual(await response.json(),{error:'従業員登録を保存できませんでした。'});
   assert.deepEqual(logs,[['employee invite persistence failed',scenario.stage==='worker'?'worker':'invite',scenario.stage==='exception'?null:409]]);
   for(const marker of markers)assert.equal(JSON.stringify(logs).includes(marker),false);
   assert.equal(bodyReads,0,'PostgREST error details are never read');
   const cleanup=calls.filter(x=>x.method==='DELETE'||(x.method==='PATCH'&&x.body?.user_id===null));
   const expected=[];
   if(scenario.existing)expected.push({path:'/rest/v1/workers',method:scenario.stage==='worker'?'DELETE':'PATCH',body:scenario.stage==='worker'?null:{user_id:null}});
   else if(scenario.stage!=='worker')expected.push({path:'/rest/v1/workers',method:'DELETE',body:null});
   expected.push({path:'/auth/v1/admin/users/'+authUser,method:'DELETE',body:null});
   assert.deepEqual(cleanup,expected,'existing rollback order and payload remain unchanged');
   assert.equal(calls.filter(x=>x.path==='/rest/v1/rpc/account_server_access_allowed').length,2);
  }
 }finally{globalThis.fetch=originalFetch;globalThis.Deno=originalDeno;console.error=originalError;}
});
