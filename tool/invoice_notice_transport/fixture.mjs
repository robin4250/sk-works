// Actual local GoTrue tokens + PostgreSQL private confirmation/result, over HTTP.
import assert from 'node:assert/strict';
import http from 'node:http';import {Readable} from 'node:stream';
import {createInvoiceNoticeTransport} from './handler.mjs';
let context;
export function installInvoiceNoticeTransportContext(value){if(context||process.env.CI!=='true'||process.env.SKO_INVOICE_NOTICE_TRANSPORT_HOOK!=='contract-v1')throw Error('isolated invoice transport context required');context=value;}
export async function verifyInvoiceNoticeTransport(db,c){
 if(!context)throw Error('invoice Auth context absent');
 const {api,publicKey,database,pg,tokens,users,password,request}=context;
 const {id,A,UA,prepare,preview,issue,state,check}=c;
 const client=async()=>{const peer=new pg.Client({connectionString:database.href,connectionTimeoutMillis:5000});await peer.connect();return peer;};
 const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:api.origin,apiKey:publicKey,connect:client});
 let drop=true,commands=0,server;
 try{
  server=http.createServer(async(req,res)=>{
   try{
    const request=new Request(`http://127.0.0.1${req.url}`,{method:req.method,headers:req.headers,body:Readable.toWeb(req),duplex:'half'});
    const result=await handler(request);
    if(req.url==='/invoice-notice/confirm'&&result.status===200){commands++;if(drop){drop=false;req.socket.destroy();return;}}
    res.writeHead(result.status,Object.fromEntries(result.headers));res.end(Buffer.from(await result.arrayBuffer()));
   }catch{res.writeHead(503);res.end();}
  });server.requestTimeout=15000;server.headersTimeout=10000;server.timeout=20000;
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const endpoint=`http://127.0.0.1:${server.address().port}`;
  const post=(route,value,token=tokens.owner)=>fetch(endpoint+'/invoice-notice/'+route,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:JSON.stringify(value)});
  const x=await prepare(21),expected=await preview(x),ticket=await issue(x);
  const hash=(await db.query("select encode(sha256(convert_to($1::jsonb::text,'UTF8')),'hex') v",[JSON.stringify(expected)])).rows[0].v;
  const operation={ticket_id:ticket,local_document_id:x.local,company_id:A,revision:1,request_id:id(29021),expected_preview:expected,expected_hash:hash};
  const before=await state(x);check(before.audit,0);check(before.consents,0);
  // The existing SQL gate stays OFF until this disposable fixture enables it.
  check((await post('confirm',{...operation,financial_confirmed:true,seal_confirmed:true})).status,503);
  check(await state(x),before);check(commands,0);
  check((await db.query('select consumed_at is null v from invoice_month_close_candidate.notice_open_tickets where id=$1',[ticket])).rows[0].v,true);
  await db.exec('update trade_document_consent_private.notice_confirmation_settings set enabled=true');
  // Drop a real HTTP response only AFTER the private SQL COMMIT completed.
  let failed=false,status;
  try{status=(await post('confirm',{...operation,financial_confirmed:true,seal_confirmed:true})).status;}catch{failed=true;}
  if(!failed){const error=new Error('confirmation response was not dropped');error.code='INVOICE_CONFIRM_HTTP_'+status;throw error;}
  check(drop,false);check(commands,1);
  const response=await post('result',operation);check(response.status,200);
  const result=await response.json();check(result.found,true);check(result.status,'recorded');check(result.result.financial_approved,true);check(result.result.seal_consent_recorded,true);
  const ownerClaims=JSON.parse(Buffer.from(tokens.owner.split('.')[1],'base64url').toString('utf8'));
  check(result.scope,{ticket_id:ticket,local_document_id:x.local,company_id:A,revision:1,request_id:operation.request_id,expected_hash:hash,actor_id:UA,session_id:ownerClaims.session_id});
  const after=await state(x);check(after.audit,1);check(after.consents,1);check(after.receipts,1);check(after.approvals[0].status,'approved');check(after.parent.invoice_seal_frozen,true);
  check((await db.query('select count(*)::int n from trade_document_consent_private.notice_confirmation_results where ticket_id=$1',[ticket])).rows[0].n,1);
  check(commands,1);
  check((await post('result',{...operation,request_id:id(29022)})).status,200);
  check(await (await post('result',{...operation,request_id:id(29022)})).json(),{found:false});
  check((await post('result',{...operation,expected_hash:'0'.repeat(64)})).status,400);
  for(const name of ['viewer','outsider'])assert.ok((await post('result',operation,tokens[name])).status>=400);
  const login=await request('/auth/v1/token?grant_type=password',{body:{email:users.owner.email,password}});check(login.status,200);
  const another=(await login.json()).access_token;
  const anotherClaims=JSON.parse(Buffer.from(another.split('.')[1],'base64url').toString('utf8'));
  assert.notEqual(anotherClaims.session_id,ownerClaims.session_id);
  check((await post('result',operation,another)).status,403);
  check((await post('result',operation)).status,200);
  let isolatedAfter=after;
  if(process.env.SKO_INVOICE_NOTICE_APP_HOOK==='contract-v1'){
   await (await import('./app_fixture.mjs')).verifyInvoiceNoticeApp(db,c,context);
   isolatedAfter=await state(x);
   // state(x) includes a GLOBAL primitive receipt count. The separate app
   // document creates exactly one receipt; every original-document field
   // must remain identical before checking logout makes no further changes.
   check(isolatedAfter.primitive_receipts,after.primitive_receipts+1);
   check({...isolatedAfter,primitive_receipts:after.primitive_receipts},after);
   console.log('PASS separate app receipt delta exactly one; original document state unchanged');
  }
  const logout=await request('/auth/v1/logout?scope=local',{token:tokens.owner});assert.ok([200,204].includes(logout.status));
  check((await db.query('select count(*)::int n from auth.sessions where id=$1',[ownerClaims.session_id])).rows[0].n,0);
  assert.ok([401,403].includes((await post('result',operation)).status));
  // JWT expiry is still in the future; live-session proof, not expiry guessing.
  assert.ok(ownerClaims.exp*1000>Date.now());
  check(commands,1);check(await state(x),isolatedAfter);
  console.log('PASS actual local GoTrue bearer -> unhosted invoice HTTP -> existing private SQL; lost committed HTTP response -> fresh immutable scoped read; exactly one financial/seal result; foreign actor/new SID/revoked SID denied; no resend/public grants/hosted deployment');
 }finally{if(server)await new Promise(resolve=>server.close(resolve));}
}
