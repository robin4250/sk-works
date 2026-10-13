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
