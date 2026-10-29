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

const actor='10000000-0000-0000-0000-000000000001',sid='10000000-0000-0000-0000-000000000002';
const operation={ticket_id:actor,local_document_id:actor,company_id:actor,revision:1,request_id:actor,expected_preview:{amount:1},expected_hash:'a'.repeat(64)};
const claims={sub:actor,session_id:sid,role:'authenticated',aud:'authenticated',iss:'http://127.0.0.1:1/auth/v1',exp:Math.floor(Date.now()/1000)+3600};
const token='header.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.signature';
const auth=()=>({status:200,redirected:false,url:'http://127.0.0.1:1/auth/v1/user',headers:new Headers({'content-type':'application/json'}),body:new Response(JSON.stringify({id:actor})).body});
const command=()=>new Request('http://127.0.0.1/invoice-notice/confirm',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+token},body:JSON.stringify({...operation,financial_confirmed:true,seal_confirmed:true})});
const spin=ms=>{const until=performance.now()+ms;while(performance.now()<until){/* synchronous external work */}};
function backend(change){
 const state={queries:[],ends:0,committed:0};
 const peer={query:async(sql)=>{
  state.queries.push(sql);if(change){const value=await change(sql,state);if(value!==undefined)return value;}
  if(sql.includes('require_reauthentication_session'))return {rows:[{sid}]};
  if(sql.includes('encode(sha256'))return {rows:[{v:operation.expected_hash}]};
  if(sql.includes('confirm_invoice_from_notice'))return {rows:[{v:{financial_approved:true,seal_consent_recorded:true}}]};
  if(sql==='commit')state.committed++;return {rows:[]};
 },end:async()=>{state.ends++;}};
 return {peer,state};
}
test('synchronous Auth overrun cannot start a pool connection after total deadline',async()=>{
 let connections=0,authCalls=0;const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:'http://127.0.0.1:1',apiKey:'fixture',budgetMs:15,
  fetchAuth:()=>{authCalls++;spin(30);return auth();},connect:()=>{connections++;}});
 assert.equal((await handler(command())).status,504);assert.equal(connections,0);assert.equal(authCalls,1);
});
test('synchronous SQL context overrun closes owned connection before any approval',async()=>{
 const {peer,state}=backend(sql=>{if(sql.includes('set_config'))spin(30);});
 const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:'http://127.0.0.1:1',apiKey:'fixture',budgetMs:15,fetchAuth:auth,connect:()=>peer});
 assert.equal((await handler(command())).status,504);
 await Promise.resolve();assert.equal(state.ends,1);assert.equal(state.committed,0);
 assert.equal(state.queries.some(sql=>sql.includes('set_config')),true,'context stage was exercised');
 assert.equal(state.queries.some(sql=>sql.includes('confirm_invoice_from_notice')),false);
 assert.equal(state.queries.includes('rollback'),false,'no new SQL after deadline');
});
test('late pool lease is closed exactly once and never receives BEGIN',async()=>{
 const {peer,state}=backend();let resolve;const lease=new Promise(done=>{resolve=done;});
 const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:'http://127.0.0.1:1',apiKey:'fixture',budgetMs:15,fetchAuth:auth,connect:()=>lease});
 assert.equal((await handler(command())).status,504);assert.equal(state.queries.length,0);
 resolve(peer);await new Promise(done=>setImmediate(done));
 assert.equal(state.ends,1);assert.equal(state.queries.length,0);
});
test('in-flight COMMIT deadline is unknown even when it later commits, never retries',async()=>{
 let resolve,entered;const started=new Promise(done=>{entered=done;});
 const commit=new Promise(done=>{resolve=done;});
 const {peer,state}=backend(async sql=>{if(sql==='commit'){entered();await commit;state.committed++;return {rows:[]};}});
 const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:'http://127.0.0.1:1',apiKey:'fixture',budgetMs:100,fetchAuth:auth,connect:()=>peer});
 const pending=handler(command());await started;
 assert.equal((await pending).status,504);assert.equal(state.ends,1);
 resolve();await new Promise(done=>setImmediate(done));
 assert.equal(state.committed,1);assert.equal(state.queries.filter(sql=>sql.includes('confirm_invoice_from_notice')).length,1);
 assert.equal(state.queries.filter(sql=>sql==='commit').length,1);assert.equal(state.queries.includes('rollback'),false);
});
test('synchronous overdue COMMIT response cannot report success',async()=>{
 const {peer,state}=backend(sql=>{if(sql==='commit'){spin(30);state.committed++;return {rows:[]};}});
 const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:'http://127.0.0.1:1',apiKey:'fixture',budgetMs:15,fetchAuth:auth,connect:()=>peer});
 assert.equal((await handler(command())).status,504);assert.equal(state.committed,1);assert.equal(state.ends,1);
});

test('healthy private command succeeds and closes one owned connection',async()=>{
 const {peer,state}=backend();
 const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:'http://127.0.0.1:1',apiKey:'fixture',fetchAuth:auth,connect:()=>peer});
 const reply=await handler(command());assert.equal(reply.status,200);assert.equal((await reply.json()).financial_approved,true);
 assert.equal(state.committed,1);assert.equal(state.ends,1);
});

const notification='10000000-0000-0000-0000-000000000003',document='10000000-0000-0000-0000-000000000004';
const sourceRevision='2026-10-29T00:00:00.123456Z';
const openingRequest=(extra={})=>new Request('http://127.0.0.1/functions/v1/invoice-notice/open',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+token},body:JSON.stringify({notification_id:notification,invoice_id:actor,source_revision:sourceRevision,...extra})});
function openBackend(count=1,alter={}){
 const saved={invoice_id:actor,company_id:actor,local_document_id:sid,document_id:document,revision:3,body:{kind:'acceptance'},body_hash:'b'.repeat(64),source_revision:sourceRevision,binding:{parent_kind:'invoice',parent_id:actor,attachment_version:7}};
 const expected={document_id:document,local_document_id:sid,company_id:actor,revision:3,body_hash:saved.body_hash,binding:saved.binding};
 const bundle=backend(sql=>{
  if(sql.startsWith('select enabled'))return {rows:[{enabled:true}]};
  if(sql.includes('ticket_from_notification'))return {rows:[{v:{notification_id:notification,invoice_id:actor,status:'ready',ticket_id:actor,expires_at:new Date(Date.now()+60000).toISOString()}}]};
  if(sql.includes('order by d.id for share'))return {rows:Array(count).fill({...saved,...alter}),rowCount:count};
  if(sql.includes('preview_confirmation'))return {rows:[{v:expected}]};
 });return bundle;
}
test('open maps authoritative local integer revision/hash, never client timestamp/hash',async()=>{
 const {peer,state}=openBackend();const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:'http://127.0.0.1:1',apiKey:'fixture',fetchAuth:auth,connect:()=>peer});
 const reply=await handler(openingRequest());assert.equal(reply.status,200);const value=await reply.json();
 assert.equal(value.operation.local_document_id,sid);assert.equal(value.operation.revision,3);assert.equal(value.operation.expected_hash,operation.expected_hash);
 assert.equal(value.source_revision,sourceRevision);assert.equal(value.preview.expected_command.document_id,document);
 assert.notEqual(value.operation.request_id,actor);assert.equal(state.committed,1);assert.equal(state.ends,1);
});
test('zero/multiple/collapsed local mapping rolls back the issued ticket without commit',async()=>{
 for(const [count,alter] of [[0,{}],[2,{}],[1,{local_document_id:document}],[1,{company_id:sid}]]){
  const {peer,state}=openBackend(count,alter);const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:'http://127.0.0.1:1',apiKey:'fixture',fetchAuth:auth,connect:()=>peer});
  assert.equal((await handler(openingRequest())).status,403);assert.equal(state.committed,0);assert.equal(state.ends,1);
  assert.equal(state.queries.includes('rollback'),true);assert.equal(state.queries.some(q=>q.includes('ticket_from_notification')),true);
 }
});
test('open refuses client-supplied operation and hash before Auth',async()=>{
 let calls=0;const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:'http://127.0.0.1:1',apiKey:'fixture',fetchAuth:()=>{calls++;},connect:()=>{calls++;}});
 assert.equal((await handler(openingRequest({expected_hash:'f'.repeat(64)}))).status,400);assert.equal(calls,0);
});
