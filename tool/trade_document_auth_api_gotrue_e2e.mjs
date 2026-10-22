// Disposable CI-only real GoTrue/PostgREST proof; never accepts a hosted endpoint.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomBytes} from 'node:crypto';
import {installTradeDocumentAuthContext} from './trade_document_auth_fixture_context.mjs';
const run=promisify(execFile),root=process.cwd(),parent=path.resolve(process.env.RUNNER_TEMP??'');
if(process.env.CI!=='true'||!process.env.RUNNER_TEMP||parent==='/'||process.env.SKO_TRADE_DOCUMENT_REAL_AUTH_HOOK!=='contract-v1'
 ||Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))throw Error('Dedicated isolated CI without hosted credentials required');
const project='sko-trade-auth-'+randomBytes(8).toString('hex'),workdir=path.join(parent,project);
const cli=(args,timeout=120000)=>run('npx',['--yes','supabase@2.121.0',...args,'--workdir',workdir],{cwd:root,timeout,maxBuffer:1024*1024,env:process.env});
let phase='setup',db,started=false,owned=false,lastHttp;
try{
 await fs.mkdir(workdir,{recursive:false,mode:0o700});owned=true;await cli(['init']);
 const configPath=path.join(workdir,'supabase/config.toml');let config=await fs.readFile(configPath,'utf8');
 config=config.replace(/^project_id = .*$/m,`project_id = "${project}"`);
 for(const [a,b] of [['54321','53981'],['54322','53982'],['54320','53980'],['54323','53983'],['54324','53984'],['54327','53987'],['54329','53989']])config=config.replaceAll(a,b);
 config=config.replace(/(\[db.seed\][\s\S]*?enabled = )true/,'$1false');await fs.writeFile(configPath,config,{mode:0o600});
 assert.equal((await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.ID}}'])).stdout.trim(),'');
 phase='local-stack';started=true;
 // CLI status contains local keys; never print status or subprocess output.
 await cli(['start','--exclude','edge-runtime,realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor'],600000);
 const status=JSON.parse((await cli(['status','--output','json'])).stdout),api=new URL(status.API_URL),database=new URL(status.DB_URL);
 assert.ok(['127.0.0.1','localhost','[::1]'].includes(api.hostname)&&api.protocol==='http:'&&api.port==='53981');
 assert.ok(['127.0.0.1','localhost','[::1]'].includes(database.hostname)&&database.port==='53982'&&database.pathname==='/postgres');
 const publicKey=status.ANON_KEY??status.PUBLISHABLE_KEY,serviceKey=status.SERVICE_ROLE_KEY??status.SECRET_KEY;
 assert.equal(typeof publicKey,'string');assert.equal(typeof serviceKey,'string');
 const pg=(await import(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 db=new pg.Client({connectionString:database.href});await db.connect();
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0);
 const authFns=async()=>(await db.query("select jsonb_agg(jsonb_build_object('oid',oid::text,'definition',pg_get_functiondef(oid)) order by oid) v from pg_proc where oid in('auth.uid()'::regprocedure,'auth.jwt()'::regprocedure)")).rows[0].v;
 const originalAuthFns=await authFns();
 async function request(route,{token,body,service=false,method='POST'}={}){
  const url=new URL(route,api);assert.equal(url.origin,api.origin);
  const response=await fetch(url,{method,redirect:'error',signal:AbortSignal.timeout(20000),headers:{apikey:service?serviceKey:publicKey,
   ...(service&&!serviceKey.startsWith('sb_'+'secret_')?{Authorization:'Bearer '+serviceKey}:{}),...(token?{Authorization:'Bearer '+token}:{}),...(body===undefined?{}:{'Content-Type':'application/json'})},...(body===undefined?{}:{body:JSON.stringify(body)})});
  lastHttp={route,status:response.status};return response;
 }
 const rpc=(name,body,token)=>request('/rest/v1/rpc/'+name,{body,token});
 const users={},tokens={},claimsById=new Map(),actorIds=new Map();
 phase='real-local-auth';const password='fixture-'+randomBytes(20).toString('hex')+'!A1';
 for(const [index,name] of ['owner','receiver','viewer','outsider'].entries()){
  const created=await request('/auth/v1/admin/users',{service:true,body:{email:name+'@example.invalid',password,email_confirm:true}});assert.equal(created.status,200);users[name]=await created.json();
  const login=await request('/auth/v1/token?grant_type=password',{body:{email:users[name].email,password}});assert.equal(login.status,200);
  const session=await login.json();tokens[name]=session.access_token;const claims=JSON.parse(Buffer.from(session.access_token.split('.')[1],'base64url').toString('utf8'));
  assert.equal(claims.sub,users[name].id);assert.ok(claims.session_id);
  assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',[claims.session_id,users[name].id])).rows[0].n,1);
  claimsById.set(users[name].id,claims);actorIds.set(11+index,users[name].id);
 }
 const actor=async uid=>{assert.ok(claimsById.has(uid));await db.query('reset role');await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify(claimsById.get(uid))]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);};
 let adapted=false,invoiceAdapted=false;
 const denyAuthWrites=sql=>assert.ok(!/\b(?:insert\s+into|update|delete\s+from|truncate(?:\s+table)?)\s+auth\./i.test(sql),'Application fixture cannot mutate real Auth rows');
 const fixture={exec:async sql=>{
  if(sql.startsWith('create role anon;create role authenticated;create role service_role;create schema private;create schema auth;')){
   assert.equal(adapted,false);adapted=true;
   for(const exact of ['create role anon;create role authenticated;create role service_role;','create schema auth;',"create function auth.uid()returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;"]){assert.equal(sql.split(exact).length,2);sql=sql.replace(exact,'');}
   sql=sql.replace('grant usage on schema private,auth to authenticated;','grant usage on schema private to authenticated;');
  }
  if(sql.includes('create table auth.users(id uuid primary key);')){assert.equal(invoiceAdapted,false);invoiceAdapted=true;sql=sql.replace('create table auth.users(id uuid primary key);','');}
  denyAuthWrites(sql);return db.query(sql);
 },query:async(sql,args=[])=>{
  if(sql==='insert into auth.users values($1),($2),($3)'){assert.deepEqual(args,[users.owner.id,users.receiver.id,users.viewer.id]);return {rows:[],rowCount:0};}
  denyAuthWrites(sql);return db.query(sql,args);
 },close:async()=>{}};
 installTradeDocumentAuthContext({db:fixture,actor,actorId:n=>actorIds.get(n)});
 phase='unchanged-consent-fixtures';process.env.SKO_MONTHLY_PAYMENT_REVIEW_HOOK='contract-v1';delete process.env.SKO_TRADE_DOCUMENT_API_REVIEW_HOOK;
 process.argv[3]='auth-http-setup';await import('./verify_trade_document_bound_seal_consent.mjs');assert.equal(adapted,true);assert.equal(invoiceAdapted,true);
 await actor(users.owner.id);await db.query(await fs.readFile('docs/candidates/trade_document_confirmation_api_20261022.sql.review-only','utf8'));
 const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`,A=id(1),B=id(2),partner=id(23),customer=id(24),payment=id(9100),invoice=id(9101),trade=id(9102);
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows[0]?.v;
 // Only synthetic application parents are written through the established savers.
 await db.query("insert into payment_certificates(id,company_id,partner_company_id,period_start,period_end,revision,status,gross_amount,snapshot) values($1,$2,$3,'2026-10-01','2026-10-31',1,'draft',110000,'{}')",[payment,A,partner]);
 await db.query("insert into invoices(id,company_id,customer_id,billing_period_start,billing_period_end,updated_at,status,grand_total,tax,snapshot) values($1,$2,$3,'2026-10-01','2026-10-31',clock_timestamp(),'draft',110000,10000,'{}')",[invoice,A,customer]);
 await db.query('select private.ensure_invoice_approval_rows($1)',[invoice]);
 const invoiceRev=await q('select updated_at::text v from invoices where id=$1',[invoice]);
 for(const [kind,parentId,rev] of [['payment_certificate',payment,'1'],['invoice',invoice,invoiceRev]]){
  const w=await q('select public.trade_document_attachment_workspace($1,$2,$3) v',[kind,parentId,rev]);
  const payload={...w.defaults,company_seal_enabled:false,company_seal_snapshot:null,work_name:'実JWT合成工事',work_address:'東京都',notes:''};
  if(kind==='invoice')Object.assign(payload,{issue_date:'2026-10-22',order_date:'2026-10-21',acceptance_text:'上記注文内容を承諾します。',intro_text:'合成請負',payment_conditions:'翌月末'});
  await q('select public.save_trade_document_attachment($1,$2,$3,0,$4::jsonb) v',[kind,parentId,rev,JSON.stringify(payload)]);
 }
 await db.query("insert into trade_companies(id,company_id,linked_company_id,trade_role,link_status) values($1,$2,$3,'customer','linked')",[trade,B,A]);
 const identity=async()=>(await db.query("select jsonb_build_object('users',(select jsonb_agg(jsonb_build_object('id',id,'email',email,'role',role,'app_metadata',raw_app_meta_data) order by id) from auth.users),'identities',(select jsonb_agg(to_jsonb(i) order by id) from auth.identities i),'sessions',(select jsonb_agg(to_jsonb(s) order by id) from auth.sessions)) v")).rows[0].v;
 const identityBefore=await identity();
 const financial=()=>q("select jsonb_build_object('payment',(select to_jsonb(p) from payment_certificates p where id=$1),'invoice',(select to_jsonb(i) from invoices i where id=$2)) v",[payment,invoice]);
 phase='postgrest-schema-cache';await db.query("select set_config('request.jwt.claims','{}',false),set_config('request.jwt.claim.sub','',false);notify pgrst,'reload schema'");
 for(let attempt=0;;attempt++){const r=await rpc('trade_document_confirmation_contract_version',{},tokens.owner);if(r.status===200){assert.equal(await r.json(),1);break;}const e=await r.json();if(e.code!=='PGRST202'||attempt===30)throw Error('Local schema cache unavailable');await new Promise(resolve=>setTimeout(resolve,250));}
 const ok=async(name,body,token=tokens.owner)=>{const r=await rpc(name,body,token);assert.equal(r.status,200);return r.json();};
 const protectedBusiness=()=>q(`select jsonb_build_object('financial',jsonb_build_object('payments',(select jsonb_agg(to_jsonb(x) order by id) from payment_certificates x),'invoices',(select jsonb_agg(to_jsonb(x) order by id) from invoices x)),
 'receipts',(select jsonb_agg(to_jsonb(x) order by company_id,request_id) from trade_document_confirmation_api_private.receipts x),
 'consents',(select jsonb_agg(to_jsonb(x) order by document_id,revision,company_id) from trade_document_consent_private.consents x),
 'approvals',(select jsonb_agg(to_jsonb(x) order by invoice_id,approver_user_id) from invoice_approvals x),
 'audit',(select jsonb_agg(to_jsonb(x) order by id) from invoice_approval_audit x),
 'links',(select jsonb_agg(to_jsonb(x) order by company_id,kind,parent_id) from trade_document_confirmation_api_private.parent_links x)) v`);
 const rejected=async(name,body,token,code='42501')=>{const before=await protectedBusiness();const r=await rpc(name,body,token);assert.notEqual(r.status,200);assert.equal((await r.json()).code,code);assert.deepEqual(await protectedBusiness(),before);};
 const wsBody=(kind,parentId,rev)=>({p_kind:kind,p_parent_id:parentId,p_source_revision:rev});
 phase='real-jwt-workspace';const w=await ok('trade_document_confirmation_workspace',wsBody('payment_certificate',payment,'1'));assert.equal(w.can_integrated_confirm,true);
 const scope={p_company_id:A,p_local_document_id:w.local_document_id,p_document_revision:w.document_revision,p_kind:'payment_certificate'};
 const p=await ok('preview_trade_document_confirmation',scope),command={p_expected_command:p.expected_command,p_request_id:id(9200),p_document_confirmed:true,p_seal_confirmed:true};
 for(const name of ['viewer','outsider']){await rejected('trade_document_confirmation_workspace',wsBody('payment_certificate',payment,'1'),tokens[name]);await rejected('confirm_trade_document_with_seal',command,tokens[name]);}
 await rejected('confirm_trade_document_with_seal',{...command,p_seal_confirmed:false},tokens.owner,'22023');
 const paymentBefore=(await financial()).payment;phase='real-jwt-monthly-review';const result=await ok('confirm_trade_document_with_seal',command);assert.equal(result.result.financial_finalized,false);assert.deepEqual((await financial()).payment,paymentBefore);
 assert.deepEqual(await ok('confirm_trade_document_with_seal',command),result);assert.deepEqual((await ok('read_trade_document_confirmation_receipt',{p_company_id:A,p_request_id:command.p_request_id,p_expected_command:p.expected_command})).result,result);
 phase='real-jwt-received';const list=await ok('list_received_trade_document_confirmations',{p_trade_company_id:trade},tokens.receiver);assert.equal(list.items.length,1);
 const received=await ok('received_trade_document_confirmation_workspace',{p_trade_company_id:trade,p_document_id:w.document_id,p_document_revision:w.document_revision},tokens.receiver);assert.notEqual(received.local_document_id,w.local_document_id);
 const issuedRender=await ok('render_confirmed_trade_document',{...scope,p_archive:false});const receivedRender=await ok('render_confirmed_trade_document',{...scope,p_company_id:B,p_local_document_id:received.local_document_id,p_archive:false},tokens.receiver);assert.deepEqual(receivedRender.evidence,issuedRender.evidence);
 await rejected('preview_trade_document_confirmation',{...scope,p_company_id:B,p_local_document_id:received.local_document_id},tokens.receiver);
 phase='real-jwt-invoice-final';const iw=await ok('trade_document_confirmation_workspace',wsBody('invoice',invoice,invoiceRev));assert.equal(iw.can_integrated_confirm,true);
 const ip=await ok('preview_trade_document_confirmation',{p_company_id:A,p_local_document_id:iw.local_document_id,p_document_revision:iw.document_revision,p_kind:'invoice'});
 const invBefore=(await financial()).invoice;const ir=await ok('confirm_trade_document_with_seal',{p_expected_command:ip.expected_command,p_request_id:id(9201),p_document_confirmed:true,p_seal_confirmed:true});assert.equal(ir.result.financial_approved,true);
 const invAfter=(await financial()).invoice;assert.equal(invAfter.grand_total,invBefore.grand_total);assert.equal(invAfter.tax,invBefore.tax);assert.equal(invAfter.invoice_seal_frozen,true);
 assert.deepEqual(await identity(),identityBefore);assert.deepEqual(await authFns(),originalAuthFns);
 phase='real-auth-session-signout';const logout=await request('/auth/v1/logout?scope=local',{token:tokens.owner});assert.ok([200,204].includes(logout.status));
 assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1',[claimsById.get(users.owner.id).session_id])).rows[0].n,0);
 await rejected('preview_trade_document_confirmation',scope,tokens.owner);await rejected('confirm_trade_document_with_seal',command,tokens.owner);
 await rejected('read_trade_document_confirmation_receipt',{p_company_id:A,p_request_id:command.p_request_id,p_expected_command:p.expected_command},tokens.owner);
 assert.deepEqual(await authFns(),originalAuthFns);
 console.log('PASS real isolated GoTrue JWT -> PostgREST public consent API: invoice final approve, monthly unchanged financial parent, receipt replay, distinct receiving local ID/equal render, viewer/other-company refusals, actual Auth signout/session invalidation');
 console.log('LIMIT synthetic application schema/access predicates; no production/RLS/OAuth/device proof, no native concurrent public API race, no deployment');
}catch(error){
 console.error('FAIL isolated trade Auth phase='+phase+' code='+(typeof error?.code==='string'?error.code:'E2E_ASSERTION'));
 if(typeof error?.actual==='number'&&typeof error?.expected==='number')console.error(JSON.stringify({actual:error.actual,expected:error.expected}));
 if(lastHttp)console.error(JSON.stringify(lastHttp));process.exitCode=1;
}finally{
 if(db)await db.end().catch(()=>{});
 if(started)await cli(['stop','--no-backup']).catch(()=>{console.error('Owned trade Auth fixture cleanup failed');process.exitCode=1;});
 if(owned)await fs.rm(workdir,{recursive:true,force:true});
}
