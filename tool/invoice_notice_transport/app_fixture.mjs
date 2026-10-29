// Dedicated actual SDK/Panel/TLS extension; no hosted listener or credentials.
import assert from 'node:assert/strict';import {createHash} from 'node:crypto';import https from 'node:https';import fs from 'node:fs/promises';
import path from 'node:path';import {Readable} from 'node:stream';import {execFile} from 'node:child_process';import {promisify} from 'node:util';
import {createInvoiceNoticeTransport} from './handler.mjs';
const execute=promisify(execFile);
export async function verifyInvoiceNoticeApp(db,c,context){
 if(process.env.CI!=='true'||process.env.SKO_INVOICE_NOTICE_APP_HOOK!=='contract-v1'||!process.env.RUNNER_TEMP)throw Error('isolated invoice app hook required');
 const {api,publicKey,database,pg,users,password}=context;
 const {id,A,UA,prepare,issue,state,check}=c;
 let server;const directory=await fs.mkdtemp(path.join(process.env.RUNNER_TEMP,'invoice-app-tls-'));
 try{
  await db.exec(`create table public.app_notifications(id uuid primary key,recipient_user_id uuid,action_key text,action_id uuid)`);
  await db.exec(await fs.readFile('docs/review/invoice-month-close/notification_delivery.sql.review-only','utf8'));
  // Preserve the existing 1 MiB upload contract. Add a valid ancillary PNG
  // chunk to an existing registered image, register it through the real saver,
  // and keep its exact bytes/hash/version throughout the app flow.
  const selected=(await db.query(`select c.name,s.revision,v.png_bytes from public.companies c
   join private.company_seal_png_selection s on s.company_id=c.id
   join private.company_seal_png_versions v on v.company_id=c.id and v.id=s.version_id where c.id=$1`,[A])).rows[0];
  assert.ok(selected);const original=selected.png_bytes,limit=1048576;
  const padding=Buffer.alloc(limit-original.length-12,90),type=Buffer.from('paDd');
  const chunk=Buffer.alloc(padding.length+12);chunk.writeUInt32BE(padding.length);type.copy(chunk,4);padding.copy(chunk,8);
  let crc=0xffffffff;for(const byte of Buffer.concat([type,padding])){crc^=byte;for(let bit=0;bit<8;bit++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}
  chunk.writeUInt32BE((crc^0xffffffff)>>>0,padding.length+8);
  const png=Buffer.concat([original.subarray(0,original.length-12),chunk,original.subarray(original.length-12)]);
  check(png.length,limit);const sealHash=createHash('sha256').update(png).digest('hex');
  await db.query('select public.save_company_uploaded_seal($1,$2,$3,$4,$5,true)',[A,selected.name,selected.revision,png.toString('base64'),sealHash]);
  const registeredVersion=(await db.query('select version_id from private.company_seal_png_selection where company_id=$1',[A])).rows[0].version_id;
  const x=await prepare(22),initialTicket=await issue(x);
  const notice=(await db.query('select notice_id from invoice_month_close_candidate.notice_open_tickets where id=$1',[initialTicket])).rows[0].notice_id;
  const notification=id(87022);
  await db.query("insert into public.app_notifications values($1,$2,'invoice_approval',$3)",[notification,UA,x.parent]);
  await db.query('insert into invoice_month_close_candidate.delivery_receipts(notice_id,notification_id,recipient_id) values($1,$2,$3)',[notice,notification,UA]);
  const revision=(await db.query("select to_jsonb(updated_at)#>>'{}' v from public.invoices where id=$1",[x.parent])).rows[0].v;
  const before=await state(x);
  const key=path.join(directory,'key.pem'),cert=path.join(directory,'cert.pem');
  await execute('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout',key,'-out',cert,'-days','1','-subj','/CN=127.0.0.1','-addext','subjectAltName=IP:127.0.0.1'],{timeout:15000,maxBuffer:65536});
  await fs.chmod(key,0o600);await fs.chmod(cert,0o600);
  const handler=createInvoiceNoticeTransport({enabled:true,authOrigin:api.origin,apiKey:publicKey,connect:async()=>{const peer=new pg.Client({connectionString:database.href,connectionTimeoutMillis:5000});await peer.connect();return peer;}});
  let commands=0,dropped=false,opens=0,reads=0,authRequests=0,tlsRejections=0;
  server=https.createServer({key:await fs.readFile(key),cert:await fs.readFile(cert)},async(req,res)=>{
   try{
    const incoming=new URL(req.url,'https://127.0.0.1');
    if(['/auth/v1/token','/auth/v1/user','/auth/v1/logout'].includes(incoming.pathname)){
     authRequests++;
     const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>65536)throw Error('auth fixture request limit');chunks.push(chunk);}
     const target=new URL(incoming.pathname+incoming.search,api);
     const result=await fetch(target,{method:req.method,redirect:'error',signal:AbortSignal.timeout(10000),headers:{apikey:publicKey,...(req.headers.authorization?{authorization:req.headers.authorization}:{}),'content-type':'application/json'},...(size?{body:Buffer.concat(chunks)}:{})});
     const bytes=Buffer.from(await result.arrayBuffer());if(bytes.length>65536)throw Error('auth fixture response limit');
     res.writeHead(result.status,{'content-type':'application/json'});res.end(bytes);return;
    }
    const result=await handler(new Request(incoming,{method:req.method,headers:req.headers,body:Readable.toWeb(req),duplex:'half'}));
    if(incoming.pathname.endsWith('/open'))opens++;
    if(incoming.pathname.endsWith('/result'))reads++;
    if(incoming.pathname.endsWith('/confirm')&&result.status===200){commands++;dropped=true;req.socket.destroy();return;}
    res.writeHead(result.status,Object.fromEntries(result.headers));res.end(Buffer.from(await result.arrayBuffer()));
   }catch{res.writeHead(503);res.end();}
  });server.requestTimeout=25000;server.headersTimeout=10000;server.timeout=30000;
  server.on('tlsClientError',()=>{tlsRejections++;});
  await new Promise(done=>server.listen(0,'127.0.0.1',done));
  const origin=`https://127.0.0.1:${server.address().port}`;
  // Secrets remain only in the child environment; no token/password file or log.
  let output;try{output=await execute('flutter',['test','--reporter','expanded','--dart-define=SUPABASE_URL='+origin,'test/invoice_notice_app_transport_e2e_test.dart'],{
   cwd:process.cwd(),timeout:180000,maxBuffer:1024*1024,env:{...process.env,SKO_INVOICE_APP_REQUIRED:'true',SKO_INVOICE_APP_CERT:cert,
    SKO_INVOICE_APP_KEY:publicKey,SKO_INVOICE_APP_EMAIL:users.owner.email,SKO_INVOICE_APP_PASSWORD:password,
    SKO_INVOICE_APP_NOTIFICATION:notification,SKO_INVOICE_APP_INVOICE:x.parent,SKO_INVOICE_APP_REVISION:revision}});}catch(error){
   const stages=String(error.stdout??'').match(/INVOICE_APP_STAGE=[a-z_]+/g)??[];
   console.error('invoice_sdk_fixture_progress='+JSON.stringify({stages,authRequests,opens,reads,commands,dropped,tlsRejections,timedOut:error.killed===true}));
   const positions=String(error.stdout??'').match(/invoice_notice_app_transport_e2e_test\.dart:[0-9]+:[0-9]+/g)??[];
   const failures=String(error.stdout??'').match(/Bad state: No element|pumpAndSettle timed out|TestFailure|MissingPluginException|HandshakeException/g)??[];
   console.error('invoice_sdk_fixture_failure='+JSON.stringify({positions,failures}));
   const failedStage=String(error.stdout??'').match(/invoice fixture stage: ([a-z ]{1,100})/);
   if(failedStage)console.error('invoice_sdk_fixture_stage='+failedStage[1]);
   throw error;
  }
  if(!output.stdout.includes('All tests passed!'))throw Error('SDK Panel proof missing');
  check(dropped,true);check(commands,1);assert.ok(opens>=1);assert.ok(reads>=1);assert.ok(tlsRejections>=1);
  const after=await state(x);check(before.audit,0);check(after.audit,1);check(after.consents,1);check(after.receipts,1);check(after.approvals[0].status,'approved');
  const consent=(await db.query('select seal_snapshot,seal_version_id,seal_asset_hash from trade_document_consent_private.consents where document_id=$1 and company_id=$2',[x.doc,A])).rows[0];
  const snapshot=consent.seal_snapshot;check(consent.seal_version_id,registeredVersion);check(consent.seal_asset_hash,sealHash);
  check(snapshot.png_sha256,sealHash);check(createHash('sha256').update(Buffer.from(snapshot.png_base64,'base64')).digest('hex'),sealHash);
  console.log('PASS actual GoTrue -> trusted loopback TLS -> real Supabase SDK -> existing invoice factory/Panel open/saved preview -> explicit financial+seal consent -> dropped COMMIT response -> scoped readback; logout history terminal; registered 1MiB PNG bytes/hash preserved; PDF raster device adapter synthetic');
 }finally{if(server)await new Promise(done=>server.close(done));await fs.rm(directory,{recursive:true,force:true});}
}
