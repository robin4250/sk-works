import test from 'node:test';import assert from 'node:assert/strict';import {createDirectoryRefreshHandler} from './handler.mjs';
const env=n=>({SUPABASE_URL:'https://fixture.invalid',SUPABASE_ANON_KEY:'public',SUPABASE_SERVICE_ROLE_KEY:'service-secret',LINE_CHANNEL_ACCESS_TOKEN:'line-secret'})[n];
const request=()=>new Request('https://fixture.invalid',{method:'POST',headers:{Authorization:'Bearer user'},body:'{}'});
test('refresh requires verified user and master before service or LINE calls',async()=>{
 const calls=[];const handler=createDirectoryRefreshHandler({env,fetcher:async(url)=>{calls.push(url);return Response.json(url.includes('/auth/')?{id:'user'}:false);}});
 assert.equal((await handler(request())).status,403);assert.equal(calls.length,2);assert.ok(calls.every(url=>url.startsWith('https://fixture.invalid')));
 assert.equal((await handler(new Request('https://fixture.invalid',{method:'POST'}))).status,401);
});
test('current summary confirms known names; 404 marks nonparticipation, transient errors retain prior state',async()=>{
 for(const status of [200,400,401,403,404,429,500]) {const observations=[];const handler=createDirectoryRefreshHandler({env,now:()=>new Date('2026-10-13T00:00:00Z'),fetcher:async(url,options)=>{
 if(url.includes('/auth/'))return Response.json({id:'user'});if(url.includes('/is_current_user_master_admin'))return Response.json(true);if(url.includes('/line_joined_group_workspace'))return Response.json([]);if(url.includes('/line_known_group_ids'))return Response.json([{id:'00000000-0000-0000-0000-000000000001',line_group_id:'known'}]);
 if(url.startsWith('https://api.line.me/'))return Response.json({groupId:'known',groupName:'Sourced group'}, {status});
 if(url.includes('/observe_line_joined_group')) {observations.push(JSON.parse(options.body));return Response.json(true);}throw Error('unexpected');
 }});const response=await handler(request());assert.equal(response.status,200);const result=await response.json();assert.equal(result.checked,status===200||status===404?1:0);assert.equal(observations.length,result.checked);
 if(status===200)assert.equal(observations[0].p_display_name,'Sourced group');if(status===404)assert.equal(observations[0].p_joined,false);assert.ok(!JSON.stringify(result).includes('secret')); }
});

test('invalid bearer is 401 and never reads service catalog',async()=>{
 const handler=createDirectoryRefreshHandler({env,fetcher:async()=>new Response('',{status:401})});assert.equal((await handler(request())).status,401);
});

test('current and legacy injected keys preserve real bearer and server-only API headers',async()=>{
 for(const modern of [true,false]) {
  const config={SUPABASE_URL:'https://fixture.invalid',LINE_CHANNEL_ACCESS_TOKEN:'line-fixture',
   SUPABASE_ANON_KEY:'legacy-public',SUPABASE_SERVICE_ROLE_KEY:'legacy-service'};
  if(modern) {config.SUPABASE_PUBLISHABLE_KEYS=JSON.stringify({default:'sb_publishable_fixture'});config.SUPABASE_SECRET_KEYS=JSON.stringify({default:'sb_secret_fixture'});}
  const calls=[];
  const response=await createDirectoryRefreshHandler({env:n=>config[n],fetcher:async(url,options)=>{
   calls.push({url,headers:options.headers});
   if(url.includes('/auth/'))return Response.json({id:'user'});
   if(url.includes('/is_current_user_master_admin'))return Response.json(true);
   return Response.json([]);
  }})(request());
  assert.equal(response.status,200);
  for(const call of calls.slice(0,3)) {assert.equal(call.headers.apikey,modern?'sb_publishable_fixture':'legacy-public');assert.equal(call.headers.Authorization,'Bearer user');}
  const admin=calls[3];assert.ok(admin.url.endsWith('/line_known_group_ids'));
  assert.equal(admin.headers.apikey,modern?'sb_secret_fixture':'legacy-service');
  assert.equal(admin.headers.Authorization,modern?undefined:'Bearer legacy-service');
  assert.ok(!(await response.text()).includes('fixture'));
 }
});
test('malformed or unusable maps safely fall back; missing keys do not leak or call upstream',async()=>{
 for(const raw of ['{','null','[]',JSON.stringify({default:7}),JSON.stringify({default:' '})]) {
  const config={SUPABASE_URL:'https://fixture.invalid',LINE_CHANNEL_ACCESS_TOKEN:'line-fixture',SUPABASE_PUBLISHABLE_KEYS:raw,SUPABASE_SECRET_KEYS:raw};
  let calls=0;
  const response=await createDirectoryRefreshHandler({env:n=>config[n],fetcher:async()=>{calls++;throw Error('private-fixture');}})(request());
  assert.equal(response.status,503);assert.equal(calls,0);assert.equal(await response.text(),'Directory configuration unavailable');
  config.SUPABASE_ANON_KEY='legacy-public';config.SUPABASE_SERVICE_ROLE_KEY='legacy-service';
  const denied=await createDirectoryRefreshHandler({env:n=>config[n],fetcher:async()=>new Response('',{status:401})})(request());
  assert.equal(denied.status,401);
 }
});
