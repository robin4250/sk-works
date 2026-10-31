import test from 'node:test';
import assert from 'node:assert/strict';
import {outgoingExecutionArgs,isOutgoingOwnedJob,requireLegacyNonOutgoingJob} from './site_order_outgoing_execution_contract.mjs';
import {createOutgoingPrepareHandler} from '../supabase/functions/site-order-workflow/outgoing-handler.mjs';
const id='95000000-0000-4000-8000-000000000001';
const identity={site_id:id,document_id:id,local_id:id,trade_id:id,request_id:id,preview_id:id,decision_id:id};
test('execution identity rejects caller-selected job, party, bytes and unknown keys',()=>{
 assert.equal(outgoingExecutionArgs(identity).length,7);
 for(const extra of [{job_id:id},{company_id:id},{recipient_id:id},{pdf_bytes:'x'},{decision_id:null}])assert.throws(()=>outgoingExecutionArgs({...identity,...extra}));
});
test('unknown ownership response is never a legacy permission',async()=>{
 await assert.rejects(()=>isOutgoingOwnedJob({query:async()=>({rows:[]})},id),/ownership_unobserved/);
 assert.equal(await isOutgoingOwnedJob({query:async()=>({rows:[{present:false}]})},id),false);
});
test('existing own job still cannot use legacy route when outgoing-owned or ownership is unknown',async()=>{
 for(const ownership of [true,undefined]){
  const db={query:async sql=>sql.includes('select j.id')?{rows:[{id}]}:sql.includes('to_regclass')?{rows:[{present:true}]}:sql.includes('as owned')?{rows:ownership===undefined?[]:[{owned:ownership}]}:{rows:[]}};
  await assert.rejects(()=>requireLegacyNonOutgoingJob(db,id),/outgoing_/);
 }
 await assert.rejects(()=>requireLegacyNonOutgoingJob({query:async()=>({rows:[]})},id),/fixed_purpose/);
});
test('fixed new HTTP execution commands do not accept caller bytes, job or unconfirmed send',async()=>{
 let connected=0;
 const handler=createOutgoingPrepareHandler({verify:async()=>({sub:id}),connect:async()=>{connected++;throw Error('must not connect');}});
 for(const body of [{action:'register_outgoing_original',...identity,pdf_bytes:'x'},
  {action:'original_status',...identity,job_id:id},{action:'share_confirmed',...identity,confirmed:false}]){
  const response=await handler(new Request('https://fixture.invalid',{method:'POST',headers:{authorization:'Bearer synthetic'},body:JSON.stringify(body)}));
  assert.equal(response.status,400);
 }
 assert.equal(connected,0);
});
