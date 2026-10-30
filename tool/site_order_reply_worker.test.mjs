import test from 'node:test';
import assert from 'node:assert/strict';
import {processCanonicalSiteOrderReply} from './site_order_canonical_core.mjs';
const id='00000000-0000-0000-0000-000000000001',job='00000000-0000-0000-0000-000000000002';
const claims={sub:id,role:'authenticated',session_id:id};
function database(failCommit=0){let commits=0;const calls=[];const bytes=new TextEncoder().encode('%PDF-fixed immutable original');
 return {calls,async query(sql,args){calls.push({sql,args});
 if(sql==='select session_user as role')return {rows:[{role:'postgres'}]};
 if(sql.includes('ready_reply($1)'))return {rows:[{result:{job_id:job,request_id:id}}]};
 if(sql.startsWith('select j.evidence'))return {rows:[{evidence:{private:true}}]};
 if(sql.startsWith('select pdf_bytes'))return {rows:[{pdf_bytes:bytes}]};
 if(sql.includes('register_canonical_pdf'))return {rows:[{receipt:{job_id:job,receipt_id:id,pdf_byte_length:bytes.length}}]};
 if(sql.includes('with stored'))return {rows:[{result:{status:'recipient_stored'}}]};
 if(sql==='commit'&&++commits===failCommit)throw Error('private raw connection failure');
 return {rows:[]};}};
}
test('fixed worker derives saved job/request, reuses original, then stores recipient and notice in one TX',async()=>{
 const db=database();const result=await processCanonicalSiteOrderReply(db,id,()=>{throw Error('No rerender');},claims);
 assert.equal(result.status,'recipient_stored');assert.equal(db.calls.filter(x=>x.sql==='commit').length,3);
 assert.equal(db.calls.filter(x=>x.sql.includes("set_config('request.jwt.claims',$1,true)")).length,3);
 const sent=db.calls.find(x=>x.sql.includes('with stored'));assert.deepEqual(sent.args,[id,id,id]);assert.ok(sent.sql.includes('dispatch_notifications'));
});
for(const stage of [1,2,3])test('worker COMMIT loss at stage '+stage+' remains unknown and never resends/rolls back',async()=>{
 const db=database(stage);await assert.rejects(()=>processCanonicalSiteOrderReply(db,id,()=>{throw Error('No rerender');},claims),/result_unknown/);
 assert.equal(db.calls.some(x=>x.sql==='rollback'),false);assert.equal(db.calls.filter(x=>x.sql==='commit').length,stage);
});

test('HTTP does not roll back or resend after reply-delivery COMMIT result becomes unknown',async()=>{
 const {createSiteOrderHandler}=await import('../supabase/functions/site-order-workflow/handler.mjs');
 const db=database(3);let ended=0;db.end=async()=>{ended++;};
 const handler=createSiteOrderHandler({verify:async()=>claims,connect:async()=>db,render:()=>{throw Error('No rerender');}});
 const r=await handler(new Request('https://function.invalid',{method:'POST',headers:{authorization:'Bearer fixture'},body:JSON.stringify({action:'process_reply',package_id:id})}));
 assert.equal(r.status,409);assert.equal((await r.json()).error,'result_unknown');
 assert.equal(db.calls.some(x=>x.sql==='rollback'),false);assert.equal(ended,1);
});
