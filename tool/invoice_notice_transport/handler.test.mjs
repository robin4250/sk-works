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
