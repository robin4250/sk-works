import test from 'node:test';import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.SKO_PGLITE_PATH || '../../apple-enrollment-sql-runtime/node_modules/@electric-sql/pglite/dist/index.js');
import {readFile} from 'node:fs/promises';
import {createNativeAppleEnrollmentHandler} from './native_apple_enrollment_handler.mjs';
const actor='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',sid='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
test('atomic durable actor window, session recheck, fail-closed and expiry',async()=>{
 const db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema apple_native_enrollment_private;
 create function auth.jwt() returns jsonb language sql as $$select jsonb_build_object('role',current_setting('request.role',true))$$;
 create function apple_native_enrollment_private.ready() returns boolean language sql as $$select true$$;
 create function apple_native_enrollment_private.context(a uuid,s uuid) returns jsonb language sql as $$select case when a='${actor}' and s='${sid}' then '{}'::jsonb else null end$$;`);
 await db.exec(await readFile(new URL('../shared_rate.sql.review-only',import.meta.url),'utf8'));const acl=await db.query("select has_function_privilege('anon','public.take_apple_enrollment_attempt(uuid,uuid)','EXECUTE') as anon, has_function_privilege('authenticated','public.take_apple_enrollment_attempt(uuid,uuid)','EXECUTE') as employee, has_function_privilege('service_role','public.take_apple_enrollment_attempt(uuid,uuid)','EXECUTE') as service");assert.deepEqual(acl.rows[0],{anon:false,employee:false,service:true});await db.exec("select set_config('request.role','service_role',false)");
 const take=async(a=actor,s=sid)=>(await db.query('select public.take_apple_enrollment_attempt($1,$2) as v',[a,s])).rows[0].v;
 assert.equal((await take()).allowed,false);
 await db.exec('update apple_enrollment_rate_private.rollout set enabled=true');
 assert.equal((await take(actor,'cccccccc-cccc-cccc-cccc-cccccccccccc')).allowed,false);
 const results=await Promise.all(Array.from({length:7},()=>take()));assert.equal(results.filter(x=>x.allowed).length,5);
 assert.equal((await take()).allowed,false);await db.exec("update apple_enrollment_rate_private.windows set window_started=clock_timestamp()-interval '16 minutes'");assert.equal((await take()).allowed,true);
 await db.exec("select set_config('request.role','authenticated',false)");await assert.rejects(take());await db.close();
});
test('handler checks verified user and durable rate before password or Apple calls',async()=>{
 const base='https://ztktgquxvcxcjxtluspu.supabase.co', payload={sub:actor,session_id:sid,iss:base+'/auth/v1',aud:'authenticated',role:'authenticated',exp:Math.floor(Date.now()/1000)+60};
 const jwt='e30.'+Buffer.from(JSON.stringify(payload)).toString('base64url')+'.sig';let calls=[];
 const fetcher=async(url,init)=>{calls.push({url,body:init.body});if(url.endsWith('/auth/v1/user'))return Response.json({id:actor,is_anonymous:false});if(url.endsWith('/rpc/take_apple_enrollment_attempt'))return Response.json({version:1,allowed:false});throw Error('unexpected secret operation');};
 const config={enabled:true,nativeOnlyReviewed:true,passwordSessionIsolationReviewed:true,globalGoogleProtectionReviewed:true,sharedRateReviewed:true,baseUrl:base,publicKey:'sb_publishable_test',serviceKey:'sb_secret_test',audiences:['com.skworks.skWorks']};
 const handler=createNativeAppleEnrollmentHandler(config,{fetcher});const response=await handler(new Request('https://example.test',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+jwt},body:JSON.stringify({id_token:'fixture',nonce:'a'.repeat(43),password:'not-a-real-password'})}));
 assert.equal(response.status,403);assert.equal(calls.length,2);assert.ok(calls[1].url.endsWith('/rpc/take_apple_enrollment_attempt'));assert.deepEqual(JSON.parse(calls[1].body),{p_actor_id:actor,p_session_id:sid});
 const off=createNativeAppleEnrollmentHandler({...config,sharedRateReviewed:false},{fetcher});assert.equal((await off(new Request('https://example.test',{method:'POST'}))).status,503);
});
