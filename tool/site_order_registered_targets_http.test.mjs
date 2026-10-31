import test from 'node:test';
import assert from 'node:assert/strict';
import {createOutgoingPrepareHandler} from '../supabase/functions/site-order-workflow/outgoing-handler.mjs';
const site='10000000-0000-0000-0000-000000000003';
const request=value=>new Request('https://synthetic.invalid/functions/v1/site-order-workflow/outgoing',{
 method:'POST',headers:{Authorization:'Bearer synthetic','Content-Type':'application/json'},body:JSON.stringify(value)});
test('targets uses only fixed parameterized owner-role SQL and closes its transaction',async()=>{
 const calls=[];let closed=0;
 const handler=createOutgoingPrepareHandler({verify:async()=>({sub:'verified-fixture-actor',session_id:'verified-fixture-sid'}),connect:async()=>({
  query:async(sql,args)=>{calls.push({sql,args});if(sql==='select session_user as role')return {rows:[{role:'postgres'}]};
   if(sql.includes('registered_targets'))return {rows:[{result:{read_only:true,entries:[]}}]};return {rows:[]};},
  end:async()=>{closed++;},
 })});
 const response=await handler(request({action:'targets',site_id:site,before:null,limit:50}));
 assert.equal(response.status,200);assert.equal(closed,1);
 assert.deepEqual(calls.find(x=>x.sql.includes('registered_targets')),{sql:'select site_order_outgoing_private.registered_targets($1,$2,$3) as result',args:[site,null,50]});
 assert.equal(calls.filter(x=>x.sql==='commit').length,1);assert.equal(calls.some(x=>/sync_|update |insert |delete /i.test(x.sql)),false);
});
test('targets rejects identity overrides and malformed pagination before connection',async()=>{
 let opens=0;const handler=createOutgoingPrepareHandler({verify:async()=>({}),connect:async()=>{opens++;throw Error('must not open');}});
 const good={action:'targets',site_id:site,before:null,limit:50};
 for(const value of [{...good,company_id:site},{...good,actor_id:site},{...good,limit:0},{...good,limit:51},
  {...good,limit:'50'},{...good,before:''},{...good,site_id:'not-a-site'}]) {
  assert.equal((await handler(request(value))).status,400);
 }
 assert.equal(opens,0);
});
test('non-owner connection never invokes target purpose even with verified claims',async()=>{
 let invoked=false,closed=false;
 const handler=createOutgoingPrepareHandler({verify:async()=>({role:'authenticated'}),connect:async()=>({
  query:async sql=>{if(sql==='select session_user as role')return {rows:[{role:'authenticated'}]};
   if(sql.includes('registered_targets'))invoked=true;return {rows:[]};},end:async()=>{closed=true;},
 })});
 assert.equal((await handler(request({action:'targets',site_id:site,before:null,limit:50}))).status,403);
 assert.equal(invoked,false);assert.equal(closed,true);
});
