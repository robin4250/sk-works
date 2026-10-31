import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createProjectVerifier} from '../supabase/functions/site-order-workflow/auth.mjs';
import {createSiteOrderHandler} from '../supabase/functions/site-order-workflow/handler.mjs';
const require=createRequire(import.meta.url);
const {createClient}=require('./site_order_edge_dependencies/node_modules/@supabase/supabase-js');
const base='https://signed-project.invalid',id='00000000-0000-0000-0000-000000000001',sid='00000000-0000-0000-0000-000000000002';
const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
const key={...await crypto.subtle.exportKey('jwk',pair.publicKey),kid:'fixture-key',alg:'ES256',use:'sig'};
const b64=b=>Buffer.from(b).toString('base64url');
const claims={iss:base+'/auth/v1',aud:'authenticated',sub:id,role:'authenticated',session_id:sid,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+300,user_metadata:{role:'owner'}};
async function token(extra={}){const input=b64(JSON.stringify({alg:'ES256',kid:key.kid,typ:'JWT'}))+'.'+b64(JSON.stringify({...claims,...extra}));
 return input+'.'+b64(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},pair.privateKey,new TextEncoder().encode(input)));}
const client=createClient(base,'fixture-public-key',{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:async url=>{
 assert.match(String(url),/\/auth\/v1\/\.well-known\/jwks.json$/);return new Response(JSON.stringify({keys:[key]}),{headers:{'Content-Type':'application/json'}});
}}});
const verify=createProjectVerifier(client,base);
const request=(jwt,b)=>new Request('https://function.invalid',{method:'POST',headers:{authorization:'Bearer '+jwt},body:JSON.stringify(b)});

test('real ES256 JWT verifies via pinned Supabase SDK; editable metadata is removed',async()=>{
 const result=await verify(await token({is_anonymous:false}));assert.equal(result.is_anonymous,false);assert.equal(result.sub,id);assert.equal(result.session_id,sid);assert.equal(result.user_metadata,undefined);
});
for(const [name,extra] of [['foreign issuer',{iss:'https://other.invalid/auth/v1'}],['service role',{role:'service_role'}],['anonymous principal',{is_anonymous:true}],['missing SID',{session_id:null}],['expired',{exp:1}],['future issued',{iat:Math.floor(Date.now()/1000)+1000}]])test(name+' JWT is rejected',async()=>{await assert.rejects(async()=>verify(await token(extra)));});
test('modified signature is rejected by real JWT verifier before DB connect',async()=>{
 const valid=await token(),parts=valid.split('.');parts[2]=b64(new Uint8Array(64));let connected=0;
 const handler=createSiteOrderHandler({verify,connect:()=>{connected++;throw Error('no');},render:()=>{throw Error('no');}});
 const r=await handler(request(parts.join('.'),{action:'status',package_id:id}));assert.equal(r.status,401);assert.equal(connected,0);
});
function database({unknown=false}={}){const calls=[];return {calls,async query(sql,args){calls.push({sql,args});
 if(sql==='select session_user as role')return {rows:[{role:'postgres'}]};
 if(sql.includes('archive_original'))return {rows:[{result:new TextEncoder().encode('%PDF-fixed immutable original')}]};
 if(sql.includes('package_status'))return {rows:[{result:{package_id:id,approved:true}}]};
 if(sql==='commit'&&unknown)throw Error('private payroll detail must not escape');return {rows:[]};},async end(){calls.push({sql:'end'});}};}
test('HTTP fixed status command installs verified claims LOCAL inside same dedicated TX',async()=>{
 const db=database(),handler=createSiteOrderHandler({verify,connect:async()=>db,render:()=>{throw Error('no');}});
 const r=await handler(request(await token(),{action:'status',package_id:id}));assert.equal(r.status,200);
 assert.equal(db.calls[0].sql,'begin isolation level read committed');
 const local=db.calls.findIndex(x=>x.sql.includes('set_config'));assert.ok(local>0);assert.ok(db.calls[local].sql.endsWith('$1,true)'));
 assert.equal(JSON.parse(db.calls[local].args[0]).sub,id);assert.equal(db.calls.at(-1).sql,'end');
});
test('site history uses a fixed server-scoped query, not client-supplied company or SQL',async()=>{
 const calls=[],handler=createSiteOrderHandler({verify,connect:async()=>({async query(sql,args){calls.push({sql,args});
  if(sql==='select session_user as role')return {rows:[{role:'postgres'}]};
  if(sql.includes('site_history_entries'))return {rows:[{result:[]}]};
  return {rows:[]};},async end(){calls.push({sql:'end'});}}),render:()=>{throw Error('must not render');}});
 const command={action:'site_history',site_id:id,before:null,before_id:null,limit:50};
 const result=await handler(request(await token(),command));assert.equal(result.status,200);
 assert.deepEqual((await result.json()).result,[]);
 const query=calls.find(x=>x.sql.includes('site_history_entries'));
 assert.equal(query.sql,'select site_order_package_private.site_history_entries($1,$2,$3,$4) as result');
 assert.deepEqual(query.args,[id,null,null,50]);assert.equal(calls.at(-1).sql,'end');
 const count=calls.length;
 for(const extra of [{company_id:id},{site_id:'foreign-title'},{limit:51}]) {
  assert.equal((await handler(request(await token(),{...command,...extra}))).status,400);
 }assert.equal(calls.length,count);
});
test('client cannot supply purpose SQL, company identity, bytes or an extra key',async()=>{
 let connected=0;const handler=createSiteOrderHandler({verify,connect:()=>{connected++;throw Error('no');},render:()=>{throw Error('no');}});
 for(const body of [{action:'sql',sql:'select 1'},{action:'status',package_id:id,company_id:id},{action:'register_original',job_id:id,bytes:'private'}]){
 assert.equal((await handler(request(await token(),body))).status,400);
 }assert.equal(connected,0);
});
test('lost COMMIT ACK is UNKNOWN, closed and never rolled back or automatically retried',async()=>{
 const db=database({unknown:true}),handler=createSiteOrderHandler({verify,connect:async()=>db,render:()=>{throw Error('no');}});
 const r=await handler(request(await token(),{action:'status',package_id:id}));assert.equal(r.status,409);
 assert.deepEqual(await r.json(),{error:'result_unknown',retry_automatically:false});
 assert.equal(db.calls.filter(x=>x.sql==='commit').length,1);assert.equal(db.calls.some(x=>x.sql==='rollback'),false);assert.equal(db.calls.at(-1).sql,'end');
});

test('archive uses the locked Dart SDK binary response type and preserves PDF bytes',async()=>{
 const db=database(),handler=createSiteOrderHandler({verify,connect:async()=>db,render:()=>{throw Error('no');}});
 const r=await handler(request(await token(),{action:'archive',package_id:id,kind:'order'}));
 assert.equal(r.status,200);assert.equal(r.headers.get('content-type'),'application/octet-stream');
 assert.equal(new TextDecoder().decode(await r.arrayBuffer()),'%PDF-fixed immutable original');
});

test('approval reconciliation is a fixed authenticated barrier, never an arbitrary cancellation or renderer',async()=>{
 const calls=[],handler=createSiteOrderHandler({verify,connect:async()=>({async query(sql,args){calls.push({sql,args});
  if(sql==='select session_user as role')return {rows:[{role:'postgres'}]};
  if(sql.includes('reconcile_approval'))return {rows:[{result:{package_id:id,preview_id:id,request_id:sid,operation_state:'cancelled'}}]};
  return {rows:[]};},async end(){calls.push({sql:'end'});}}),render:()=>{throw Error('must not render');}});
 const r=await handler(request(await token(),{action:'reconcile_approval',package_id:id,preview_id:id,request_id:sid}));
 assert.equal(r.status,200);assert.equal((await r.json()).result.operation_state,'cancelled');
 const query=calls.find(x=>x.sql.includes('reconcile_approval'));
 assert.equal(query.sql,'select site_order_package_private.reconcile_approval($1,$2,$3) as result');
 assert.deepEqual(query.args,[id,id,sid]);assert.equal(calls.at(-1).sql,'end');
 assert.equal(calls.some(x=>x.sql.includes('approve_operation')),false);
});

test('refusal requires explicit confirmation and uses one fixed transaction with notification dispatch',async()=>{
 const calls=[],handler=createSiteOrderHandler({verify,connect:async()=>({async query(sql,args){calls.push({sql,args});
  if(sql==='select session_user as role')return {rows:[{role:'postgres'}]};
  if(sql.includes('refuse_order'))return {rows:[{result:{package_id:id,request_id:sid,status:'rejected'}}]};
  return {rows:[]};},async end(){calls.push({sql:'end'});}}),render:()=>{throw Error('must not render refusal');}});
 assert.equal((await handler(request(await token(),{action:'refuse',package_id:id,request_id:sid}))).status,400);
 assert.equal(calls.length,0);
 const r=await handler(request(await token(),{action:'refuse',package_id:id,request_id:sid,confirmed:true}));
 assert.equal(r.status,200);assert.equal((await r.json()).result.status,'rejected');
 const query=calls.find(x=>x.sql.includes('refuse_order'));
 assert.ok(query.sql.includes('dispatch_refusal_notifications'));assert.deepEqual(query.args,[id,sid,true]);
 assert.equal(calls.filter(x=>x.sql==='commit').length,1);
});
