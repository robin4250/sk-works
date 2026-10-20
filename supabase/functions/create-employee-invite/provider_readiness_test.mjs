import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';

test('actual issuer refuses disabled or unknown phone before creating any credential or QR', async()=>{
 const originalFetch=globalThis.fetch, originalDeno=globalThis.Deno, originalError=console.error;
 const actor='10000000-0000-0000-0000-000000000001',company='30000000-0000-0000-0000-000000000001',worker='40000000-0000-0000-0000-000000000001';
 let handler,scenario,streamCancelled=false,linked=false;
 const calls=[],logs=[];
 const marker='synthetic-private-upstream-value';
 globalThis.Deno={env:{get:name=>({SUPABASE_URL:'https://fixture.invalid',SUPABASE_SERVICE_ROLE_KEY:'fixture-service-key'}[name])},serve:value=>{handler=value;}};
 console.error=(...args)=>logs.push(args);
 globalThis.fetch=async(url,options={})=>{
  const u=new URL(url);calls.push({path:u.pathname,method:options.method??'GET'});
  if(u.pathname==='/auth/v1/user')return Response.json({id:actor});
  if(u.pathname==='/rest/v1/rpc/account_server_access_allowed')return Response.json(true);
  if(u.pathname==='/rest/v1/company_members')return Response.json([{company_id:company,role:'owner'}]);
  if(u.pathname==='/rest/v1/workers')return Response.json([{id:worker,name:'Synthetic',phone:'07000000000',user_id:linked?actor:null,status:'active'}]);
  if(u.pathname==='/rest/v1/employee_registration_invites')return Response.json([]);
  if(u.pathname==='/auth/v1/settings') {
   assert.equal(options.method,'GET');assert.equal(options.redirect,'error');assert.ok(options.signal);
   if(scenario==='error')throw Error(marker);
   if(scenario==='http')return new Response(marker,{status:503});
   if(scenario==='redirect')return new Response(null,{status:302,headers:{location:'https://other.invalid'}});
   if(scenario==='invalid')return new Response(marker);
   if(scenario==='enabled-length') {
    const body=JSON.stringify({external:{phone:true}});
    return new Response(body,{headers:{'content-length':String(Buffer.byteLength(body)),'content-type':'application/json'}});
   }
   if(scenario==='oversize-declared')return new Response(' ',{headers:{'content-length':'16385'}});
   if(scenario==='oversize-stream')return new Response(new ReadableStream({start(c){c.enqueue(new Uint8Array(16384));c.enqueue(new Uint8Array(1));},cancel(){streamCancelled=true;}}));
   if(scenario==='invalid-utf8')return new Response(new Uint8Array([0xff]));
   return Response.json(scenario==='enabled'?{external:{phone:true}}:
    scenario==='disabled'?{external:{phone:false}}:
    scenario==='string'?{external:{phone:'true'}}:
    scenario==='missing'?{external:{google:true,email:true}}:null);
  }
  if(u.pathname==='/rest/v1/rpc/begin_account_server_activity')return Response.json('20000000-0000-0000-0000-000000000001');
  if(u.pathname==='/auth/v1/admin/users')return new Response(marker,{status:422});
  throw Error('Unexpected fixture request');
 };
 try {
  const sourceUrl=new URL('./index.ts',import.meta.url);
  const source=fs.readFileSync(sourceUrl,'utf8').replace('import "jsr:@supabase/functions-js/edge-runtime.d.ts";','').replace(/from '([^']+\.mjs)'/g,(_,p)=>'from '+JSON.stringify(new URL(p,sourceUrl).href));
  await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'strip'})).toString('base64'));
  for(const existing of [false,true])for(scenario of ['disabled','missing','string','null','invalid','error','http','redirect','oversize-declared','oversize-stream','invalid-utf8']) {
   calls.length=0;logs.length=0;streamCancelled=false;linked=false;
   const response=await handler(new Request('https://fixture.invalid/invite',{method:'POST',headers:{authorization:'Bearer fixture-user'},body:JSON.stringify(existing?{workerId:worker}:{name:'Synthetic',phone:'07000000000'})}));
   assert.equal(response.status,503,scenario);
   const body=await response.json();assert.equal(typeof body.error,'string');
   assert.equal('temporaryPassword' in body,false);assert.equal('qrPayload' in body,false);
   assert.equal(calls.filter(x=>x.path==='/auth/v1/settings').length,1);
   assert.equal(calls.some(x=>x.path==='/auth/v1/admin/users'||x.path==='/rest/v1/rpc/begin_account_server_activity'),false);
   assert.equal(calls.some(x=>['PATCH','DELETE'].includes(x.method)),false);
   assert.deepEqual(logs,[]);
   if(scenario==='oversize-stream')assert.equal(streamCancelled,true);
  }
  // Existing linked/approved workers are never recreated or reassigned.
  linked=true;calls.length=0;logs.length=0;scenario='disabled';
  let response=await handler(new Request('https://fixture.invalid/invite',{method:'POST',headers:{authorization:'Bearer fixture-user'},body:JSON.stringify({workerId:worker})}));
  assert.equal(response.status,409);assert.equal(calls.some(x=>x.path==='/auth/v1/settings'),false);
  assert.equal(calls.some(x=>x.path==='/auth/v1/admin/users'),false);
  // A real Boolean true preserves the former authenticated issuer path.
  for(scenario of ['enabled','enabled-length']) {
  linked=false;calls.length=0;logs.length=0;
  response=await handler(new Request('https://fixture.invalid/invite',{method:'POST',headers:{authorization:'Bearer fixture-user'},body:JSON.stringify({name:'Synthetic',phone:'07000000000'})}));
  assert.equal(response.status,409);assert.equal(calls.filter(x=>x.path==='/auth/v1/admin/users').length,1);
  assert.equal(JSON.stringify(logs).includes(marker),false);
  }
 } finally {globalThis.fetch=originalFetch;globalThis.Deno=originalDeno;console.error=originalError;}
});
