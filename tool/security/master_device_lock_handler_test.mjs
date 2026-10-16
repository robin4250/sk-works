import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createReauthenticationHandler} from '../../supabase/functions/reauthenticate-operation/handler.mjs';
const actor='10000000-0000-0000-0000-000000000001',session='20000000-0000-0000-0000-000000000001';
const device='40000000-0000-0000-0000-000000000001';
const jwt=sid=>'fixture.'+btoa(JSON.stringify({sub:actor,role:'authenticated',session_id:sid,exp:Math.floor(Date.now()/1000)+600}))+'.synthetic';
function fixture({enabled=true,capStatus=200}={}) {
 const paths=[];let issued;
 const handler=createReauthenticationHandler({baseUrl:'https://fixture.invalid',publicKey:'public_fixture',serviceKey:'fixture_service_key',fetcher:async(url,options={})=>{
  const path=new URL(url).pathname+new URL(url).search;paths.push(path);
  if(path==='/auth/v1/user')return Response.json({id:actor,phone:'synthetic-phone'});
  if(path==='/rest/v1/rpc/master_device_lock_capability')return Response.json({protocol:'sko-master-device-lock-v1',enabled},{status:capStatus});
  if(path==='/auth/v1/token?grant_type=password')return Response.json({user:{id:actor},access_token:jwt('20000000-0000-0000-0000-000000000002')});
  if(path==='/auth/v1/logout?scope=local')return new Response(null,{status:204});
  if(path==='/rest/v1/rpc/issue_reauthentication_proof'){issued=JSON.parse(options.body);return Response.json(new Date(Date.now()+120000).toISOString());}
  throw Error('Unexpected endpoint '+path);
 }});
 return {paths,get issued(){return issued;},call:target=>handler(new Request('https://function.invalid',{method:'POST',headers:{Authorization:'Bearer '+jwt(session)},body:JSON.stringify({operation:'master.device.lock',password:'synthetic-primary',target})}))};
}
for(const locked of [true,false])test('device lock target '+locked+' and distinct capability endpoint preserved',async()=>{
 const f=fixture(),target={device_id:device,locked};assert.equal((await f.call(target)).status,200);
 assert.deepEqual(f.issued.p_target,target);assert.equal(f.issued.p_operation,'master.device.lock');
 assert.equal(f.paths.includes('/rest/v1/rpc/reauthentication_capabilities'),false);
});
for(const enabled of [false,true])test('OFF or unavailable device scope refuses password calls ('+enabled+')',async()=>{
 const f=fixture({enabled,capStatus:enabled?403:200});assert.equal((await f.call({device_id:device,locked:true})).status,enabled?503:403);
 assert.equal(f.paths.some(x=>x.includes('grant_type')),false);assert.equal(f.issued,undefined);
});
test('malformed targets/extra booleans cannot substitute a device proof',async()=>{
 for(const target of [{device_id:device,locked:null},{device_id:'bad-id',locked:true},{device_id:device,locked:true,biometricVerified:true}]) {
  const f=fixture();assert.equal((await f.call(target)).status,400);assert.equal(f.paths.some(x=>x.includes('grant_type')),false);
 }
});
