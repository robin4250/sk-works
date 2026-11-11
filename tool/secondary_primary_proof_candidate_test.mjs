import test from 'node:test';
import assert from 'node:assert/strict';
import {createSecondaryPrimaryProofCandidate,primaryAuthCandidateTransport} from '../supabase/tests/fixtures/secondary_primary_proof_handler.mjs';
const actor='10000000-0000-0000-0000-000000000001',other='10000000-0000-0000-0000-000000000002',session='20000000-0000-0000-0000-000000000001';
const token=claims=>['synthetic-header',Buffer.from(JSON.stringify(claims)).toString('base64url'),'synthetic-signature'].join('.');
const bearer=token({sub:actor,session_id:session});
const marker='synthetic-private-password-token-email';
const request=(body={password:marker},auth=bearer)=>new Request('https://fixture.invalid/primary',{method:'POST',headers:{Authorization:'Bearer '+auth},body:JSON.stringify(body)});
test('primary proof uses verified identity, same origin session, temporary-only cleanup and private logs',async()=>{
 for(const mode of ['normal','caller-denied','wrong-sub','missing-session','origin-denied','wrong-password','auth-http','auth-throw','auth-json','user-mismatch','no-temp-token','cleanup-http','cleanup-throw','origin-changed','issuer-throw','issuer-invalid','finish-throw','email']){
  const calls=[],logs=[];let errorReads=0,originChecks=0;
  const fetcher=async(url,options)=>{
   const u=new URL(url);calls.push({step:u.pathname.split('/').at(-1),url:u,options});
   assert.equal(options.headers.apikey,'synthetic-public');assert.equal(options.redirect,'error');assert.ok(options.signal);
   if(u.pathname.endsWith('/user')){assert.equal(options.headers.Authorization,'Bearer '+(mode==='wrong-sub'?token({sub:other,session_id:session}):mode==='missing-session'?token({sub:actor}):bearer));return mode==='caller-denied'?new Response(marker,{status:401}):Response.json({id:actor,...(mode==='email'?{email:'synthetic@example.invalid'}:{phone:'+817000000000'})});}
   if(u.pathname.endsWith('/token')){
    assert.equal(u.searchParams.get('grant_type'),'password');assert.equal(options.headers.Authorization,'Bearer synthetic-public');
    assert.deepEqual(JSON.parse(options.body),{...(mode==='email'?{email:'synthetic@example.invalid'}:{phone:'+817000000000'}),password:marker});
    if(mode==='auth-throw')throw Error(marker);
    if(['wrong-password','auth-http'].includes(mode)){const r=new Response(marker,{status:mode==='wrong-password'?400:500});r.text=async()=>{errorReads++;return marker;};r.json=async()=>{errorReads++;throw Error(marker);};return r;}
    if(mode==='auth-json'){const r=Response.json({});r.json=async()=>{throw Error(marker);};return r;}
    return Response.json({user:{id:mode==='user-mismatch'?other:actor},...(mode==='no-temp-token'?{}:{access_token:'synthetic-temp-token'})});
   }
   if(u.pathname.endsWith('/logout')){assert.equal(u.searchParams.get('scope'),'local');assert.equal(options.headers.Authorization,'Bearer synthetic-temp-token');if(mode==='cleanup-throw')throw Error(marker);return new Response(null,{status:mode==='cleanup-http'?503:204});}
   throw Error('unexpected fixture path');
  };
  const transport=primaryAuthCandidateTransport({base:'https://fixture.invalid',publicKey:'synthetic-public',fetcher});
  const handler=createSecondaryPrimaryProofCandidate({...transport,log:(...args)=>logs.push(args),
   checkOriginSession:async(id,sid)=>{calls.push({step:'origin'});assert.equal(id,actor);assert.equal(sid,session);originChecks++;return mode!=='origin-denied'&&!(mode==='origin-changed'&&originChecks===2);},
   beginActivity:async(id,sid)=>{calls.push({step:'begin'});assert.equal(id,actor);assert.equal(sid,session);return 'synthetic-activity';},
   finishActivity:async(id,activity)=>{calls.push({step:'finish'});assert.equal(id,actor);assert.equal(activity,'synthetic-activity');if(mode==='finish-throw')throw Error(marker);},
   mintTicket:async(id,sid,options)=>{calls.push({step:'mint'});assert.equal(id,actor);assert.equal(sid,session);assert.deepEqual(options,{scope:'secondary-password-change'});if(mode==='issuer-throw')throw Error(marker);return mode==='issuer-invalid'?'bad':'a'.repeat(64);},
  });
  const auth=mode==='wrong-sub'?token({sub:other,session_id:session}):mode==='missing-session'?token({sub:actor}):bearer;
  const r=await handler(request(undefined,auth)),data=await r.json();assert.equal(r.headers.get('Cache-Control'),'no-store');
  if(['normal','email'].includes(mode)){assert.equal(r.status,200);assert.deepEqual(data,{ticket:'a'.repeat(64),expires_in:300,scope:'secondary-password-change'});assert.deepEqual(calls.map(c=>c.step),['user','origin','begin','token','logout','origin','mint','finish']);}
  else{assert.ok(r.status>=400,mode);assert.ok(!JSON.stringify(data).includes(marker));}
  assert.equal(errorReads,0);assert.ok(!JSON.stringify(logs).includes(marker));assert.ok(!JSON.stringify(logs).includes('synthetic-temp-token'));assert.ok(!JSON.stringify(logs).includes(bearer));
  if(['user-mismatch','cleanup-http','cleanup-throw','origin-changed','wrong-password','auth-http','auth-throw','auth-json','no-temp-token'].includes(mode))assert.equal(calls.some(c=>c.step==='mint'),false,mode);
  if(mode==='user-mismatch')assert.equal(calls.filter(c=>c.step==='logout').length,1);
 }
});
test('request injection and oversized input cannot reach primary verification or mint',async()=>{
 let writes=0;
 const handler=createSecondaryPrimaryProofCandidate({getAuthUser:async()=>({id:actor,phone:'+817000000000'}),checkOriginSession:async()=>true,beginActivity:async()=>{writes++;},passwordGrant:async()=>{writes++;},mintTicket:async()=>{writes++;}});
 for(const body of [{password:marker,actorId:other},{password:marker,phone:'other'},{password:marker,verified:true},{password:'x'.repeat(3000)},{password:''},[]])assert.equal((await handler(request(body))).status,400);
 assert.equal(writes,0);
 assert.equal((await handler(new Request('https://fixture.invalid',{method:'GET'}))).status,405);
 assert.equal((await handler(new Request('https://fixture.invalid',{method:'POST',body:'{}'}))).status,401);
});
