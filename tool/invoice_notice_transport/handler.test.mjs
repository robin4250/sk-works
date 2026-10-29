import test from 'node:test';import assert from 'node:assert/strict';
import {createInvoiceNoticeTransport} from './handler.mjs';
const request=(body,headers={})=>new Request('http://127.0.0.1/invoice-notice/result',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer synthetic',...headers},body:JSON.stringify(body)});
test('fixed OFF creates no handler, Auth call or database connection',()=>{assert.equal(createInvoiceNoticeTransport(),null);});
test('enabled boundary requires fixed safe server origin and backend',()=>{for(const authOrigin of ['http://example.test','https://user:password@example.test','https://example.test/path'])assert.throws(()=>createInvoiceNoticeTransport({enabled:true,authOrigin,apiKey:'fixture',connect:()=>{}}));});
test('credential/scope injection and oversized input never call Auth or database',async()=>{
 let calls=0;const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:'http://127.0.0.1:1',apiKey:'fixture',connect:()=>{calls++;},fetchAuth:()=>{calls++;}});
 for(const body of [{actor_id:'forged'},{token:'secret'},{padding:'x'.repeat(65536)}])assert.ok([400,413].includes((await handler(request(body))).status));
 assert.equal(calls,0);
});
test('cookies, malformed bearer and wrong method cannot reach Auth',async()=>{
 let calls=0;const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:'http://127.0.0.1:1',apiKey:'fixture',connect:()=>{calls++;},fetchAuth:()=>{calls++;}});
 assert.equal((await handler(request({}, {cookie:'session=forbidden'}))).status,401);
 assert.equal((await handler(request({}, {authorization:'Bearer one, Bearer two'}))).status,401);
 assert.equal((await handler(new Request('http://127.0.0.1/invoice-notice/result'))).status,404);
 assert.equal(calls,0);
});

test('Auth response is byte/media/origin/redirect bounded before any database call',async()=>{
 const id='10000000-0000-0000-0000-000000000001';
 const value={ticket_id:id,local_document_id:id,company_id:id,revision:1,request_id:id,expected_preview:{amount:1},expected_hash:'a'.repeat(64)};
 let connections=0;
 for(const kind of ['oversized','media','redirect','origin']){
  const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:'http://127.0.0.1:1',apiKey:'fixture',connect:()=>{connections++;},fetchAuth:async()=>({
   status:200,redirected:kind==='redirect',url:kind==='origin'?'http://foreign.test/auth/v1/user':'http://127.0.0.1:1/auth/v1/user',
   headers:new Headers({'content-type':kind==='media'?'text/html':'application/json'}),
   body:new Response(JSON.stringify({id,metadata:kind==='oversized'?'x'.repeat(32768):''})).body})});
  assert.equal((await handler(request(value))).status,401,kind);
 }
 assert.equal(connections,0);
});
