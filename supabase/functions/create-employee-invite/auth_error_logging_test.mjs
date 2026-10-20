import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';

test('Auth failure logs only status and preserves response and account checks', async()=>{
 const originalFetch=globalThis.fetch, originalDeno=globalThis.Deno, originalError=console.error;
 const logs=[],calls=[];let handler,upstreamStatus=422,bodyReads=0;
 const markers=['synthetic-person@example.invalid','synthetic-private-phone','synthetic-token-value','synthetic-password-value'];
 globalThis.Deno={env:{get:name=>({SUPABASE_URL:'https://fixture.invalid',SUPABASE_SERVICE_ROLE_KEY:'fixture-service-key'}[name])},serve:value=>{handler=value;}};
 console.error=(...args)=>logs.push(args);
 globalThis.fetch=async(url,options={})=>{
  const u=new URL(url);calls.push({path:u.pathname,method:options.method??'GET'});
  if(u.pathname==='/auth/v1/settings')return Response.json({external:{phone:true}});
  if(u.pathname==='/auth/v1/user')return Response.json({id:'10000000-0000-0000-0000-000000000001'});
  if(u.pathname==='/rest/v1/rpc/account_server_access_allowed')return Response.json(true);
  if(u.pathname==='/rest/v1/rpc/begin_account_server_activity')return Response.json('20000000-0000-0000-0000-000000000001');
  if(u.pathname==='/rest/v1/company_members')return Response.json([{company_id:'30000000-0000-0000-0000-000000000001',role:'owner'}]);
  if(u.pathname==='/rest/v1/employee_registration_invites')return Response.json([]);
  if(u.pathname==='/auth/v1/admin/users') {
   const response=new Response(JSON.stringify({error:markers.join(' ')}),{status:upstreamStatus});
   const text=response.text.bind(response);response.text=async()=>{bodyReads++;return text();};return response;
  }
  throw Error('Unexpected fixture request '+u.pathname);
 };
 try {
  // Execute the actual handler with Node's built-in type erasure. The JSR import
  // contains only Deno type declarations; real account modules remain imported.
  const sourceUrl=new URL('./index.ts',import.meta.url);
  const source=fs.readFileSync(sourceUrl,'utf8')
   .replace('import "jsr:@supabase/functions-js/edge-runtime.d.ts";','')
   .replace(/from '([^']+\.mjs)'/g,(_,path)=>'from '+JSON.stringify(new URL(path,sourceUrl).href));
  const code=stripTypeScriptTypes(source,{mode:'strip'});
  await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
  assert.equal(typeof handler,'function');
  for(const status of [422,500]) {
   upstreamStatus=status;logs.length=0;calls.length=0;
   const response=await handler(new Request('https://fixture.invalid/invite',{method:'POST',headers:{authorization:'Bearer fixture-user'},body:JSON.stringify({name:'Synthetic Employee',phone:'07000000000'})}));
   assert.equal(response.status,status===422?409:500);
   assert.deepEqual(await response.json(),{error:status===422?'この電話番号はすでにSKOへ登録されています。':'ログイン情報を作成できませんでした。'});
   assert.deepEqual(logs,[['employee auth create failed',status]]);
   for(const marker of markers)assert.equal(JSON.stringify(logs).includes(marker),false);
   assert.equal(bodyReads,0,'upstream personal/error body is not read for logging');
   assert.equal(calls.filter(x=>x.path==='/rest/v1/rpc/account_server_access_allowed').length,2);
   assert.equal(calls.filter(x=>x.path==='/auth/v1/admin/users').length,1);
  }
  calls.length=0;logs.length=0;
  assert.equal((await handler(new Request('https://fixture.invalid/invite',{method:'POST',body:'{}'}))).status,401);
  assert.equal((await handler(new Request('https://fixture.invalid/invite'))).status,405);
  assert.deepEqual(logs,[]);assert.deepEqual(calls,[]);
 } finally {globalThis.fetch=originalFetch;globalThis.Deno=originalDeno;console.error=originalError;}
});
