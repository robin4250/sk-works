import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {createProjectVerifier} from '../../../supabase/functions/site-order-workflow/auth.mjs';
import {createOutgoingPrepareHandler} from '../../../supabase/functions/site-order-workflow/outgoing-handler.mjs';
import {createSiteOrderHandler} from '../../../supabase/functions/site-order-workflow/handler.mjs';
import {createCanonicalSiteOrderRenderer} from '../../../tool/site_order_canonical_renderer.mjs';
const require=createRequire(import.meta.url),root=path.resolve(new URL('../../../',import.meta.url).pathname);
export async function verifyExecution(db,{q,check,UA,A,B,sid,sid2,make,prepare,preview,confirm,params,httpReceipt}){
 const {createClient}=require('../../../tool/site_order_edge_dependencies/node_modules/@supabase/supabase-js');
 const base='https://outgoing-execution-fixture.invalid',pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 const jwk={...await crypto.subtle.exportKey('jwk',pair.publicKey),kid:'execution-'+crypto.randomUUID(),alg:'ES256',use:'sig'};
 const client=createClient(base,'synthetic-public-key',{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:async url=>{
  if(!String(url).endsWith('/auth/v1/.well-known/jwks.json'))throw Error('unexpected Auth URL');return new Response(JSON.stringify({keys:[jwk]}),{headers:{'Content-Type':'application/json'}});
 }}});
 const verify=createProjectVerifier(client,base),b64=x=>Buffer.from(x).toString('base64url');
 const jwt=async(session=sid)=>{const now=Math.floor(Date.now()/1000),claims={sub:UA,session_id:session,role:'authenticated',aud:'authenticated',iss:base+'/auth/v1',iat:now,exp:now+300};
  const value=b64(JSON.stringify({alg:'ES256',kid:jwk.kid}))+'.'+b64(JSON.stringify(claims));return value+'.'+b64(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},pair.privateKey,new TextEncoder().encode(value)));};
 const actualRender=await createCanonicalSiteOrderRenderer({dartExecutable:process.env.SKO_CANONICAL_DART,repositoryRoot:root});
 let renders=0,connections=0,closed=0,registerCommands=0,shareCommands=0,dropAck=false;
 const hooks=new Map(),renderHooks=new Map(),executed=[];
 const renderFor=tag=>async evidence=>{renders++;await renderHooks.get(tag)?.();return actualRender(evidence);};
 const connectFor=tag=>async()=>{
  connections++;let peer=db;
  if(process.argv[3]==='postgres'){const pg=(await import(process.argv[2])).default;peer=new pg.Client({connectionString:process.env.SKO_CONSENT_FIXTURE_URL,application_name:'sko-execution:'+tag});await peer.connect();await peer.query("set statement_timeout='20s';set lock_timeout='15s'");}
  return {query:async(sql,args)=>{await hooks.get(tag)?.before?.(sql,args);const result=await peer.query(sql,args);executed.push({tag,sql});await hooks.get(tag)?.after?.(sql,args);if(sql==='commit'&&dropAck){dropAck=false;throw Error('fixture ACK loss after actual commit');}return result;},end:async()=>{closed++;if(peer!==db)await peer.end();}};
 };
 const post=async(action,identity,{session=sid,legacyRoute=false,extra={},tag='serial'}={})=>{
  const connect=connectFor(tag),render=renderFor(tag);
  const outgoing=createOutgoingPrepareHandler({verify,connect,render}),legacy=createSiteOrderHandler({verify,connect,render});
  if(action==='register_outgoing_original')registerCommands++;if(action==='share_confirmed')shareCommands++;
  return (legacyRoute?legacy:outgoing)(new Request(base+'/functions/v1/site-order-workflow/outgoing',{method:'POST',headers:{authorization:'Bearer '+await jwt(session)},body:JSON.stringify({action,...identity,...extra})}));
 };
 const identityOf=(x,p)=>{const [site,doc,local,trade,request]=params(x);return{site_id:site,document_id:doc,local_id:local,trade_id:trade,request_id:request,preview_id:p.preview_id,decision_id:x.decision};};
 const fresh=async n=>{const x=await make(n);await prepare(x);const p=await preview(x),r=await confirm(x,p);return{x,p,r,identity:identityOf(x,p)};};
 const old={...httpReceipt.identity,preview_id:httpReceipt.preview.preview_id,decision_id:httpReceipt.decision_id};
 const job=httpReceipt.result.job_id;
 const noOriginal=await post('original_status',old);check(noOriginal.status,200);check((await noOriginal.json()).result.original_saved,false);
 check((await post('register_original',{job_id:job},{legacyRoute:true})).status,403);check(renders,0);
 check((await post('send_order',{job_id:job,original_receipt_id:'95000000-0000-4000-8000-000000000001',request_id:'95000000-0000-4000-8000-000000000002'},{legacyRoute:true})).status,403);
 dropAck=true;const unknown=await post('register_outgoing_original',old);check(unknown.status,409);check((await unknown.json()).error,'result_unknown');check(renders,1);
 const saved=await post('original_status',old);check(saved.status,200);const original=(await saved.json()).result;check(original.original_saved,true);check(original.sharing_state,'not_observed');
 const bytes=await q('select pdf_bytes v from site_order_artifact_private.pdf_records where job_id=$1',[job]);check(original.pdf_sha256,createHash('sha256').update(bytes).digest('hex'));
 const again=await post('register_outgoing_original',old);check(again.status,200);check((await again.json()).result.original_receipt.receipt_id,original.original_receipt_id);check(renders,1);
 check(await q('select pdf_bytes v from site_order_artifact_private.pdf_records where job_id=$1',[job]),bytes);
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 check((await post('register_outgoing_original',old)).status,403);check((await post('share_confirmed',old,{extra:{confirmed:true}})).status,403);
 const off=await post('original_status',old,{session:sid2});check(off.status,200);check((await off.json()).result.original_saved,true);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 check((await post('register_outgoing_original',old,{session:sid2})).status,403);
 check((await post('share_confirmed',old,{session:sid2,extra:{confirmed:true}})).status,403);
 const beforeShare=shareCommands;check((await post('share_confirmed',old,{extra:{confirmed:false}})).status,400);check(shareCommands,beforeShare+1);
 dropAck=true;const sharedUnknown=await post('share_confirmed',old,{extra:{confirmed:true}});check(sharedUnknown.status,409);
 const observed=await post('original_status',old,{session:sid2});check(observed.status,200);const shared=(await observed.json()).result;check(shared.sharing_state,'recipient_stored');check(shared.original_receipt_id,original.original_receipt_id);
 check(await q('select count(*)::int v from site_order_package_private.packages where source_job_id=$1',[job]),1);
 const noticeCount=await q('select count(*)::int v from site_order_package_private.notification_receipts where package_id=$1',[shared.package_id]);check(noticeCount,1);
 const repeat=await post('share_confirmed',old,{extra:{confirmed:true}});check(repeat.status,200);check((await repeat.json()).result.package_id,shared.package_id);
 check(await q('select count(*)::int v from site_order_package_private.notification_receipts where package_id=$1',[shared.package_id]),noticeCount);
 const projection=await q('select site_projection v from site_order_package_private.packages where id=$1',[shared.package_id]);
 for(const key of ['unit_price','total_amount_yen','tax_amount_yen','notes','pdf_url','original_url'])check(Object.hasOwn(projection,key),false);
 const changed=await fresh(600);await db.query("update public.companies set company_seal_style='aoyagi_reisho' where id=$1",[A]);
 check((await post('register_outgoing_original',changed.identity)).status,403);
 check(await q('select count(*)::int v from site_order_artifact_private.pdf_records where job_id=$1',[changed.r.job_id]),0);
 await db.query("update public.companies set company_seal_style='legacy' where id=$1",[A]);
 check((await post('register_original',{job_id:changed.r.job_id},{legacyRoute:true})).status,403);
 let nativeWaits=0;
 if(process.argv[3]==='postgres'){
  const deferred=()=>{let resolve;const promise=new Promise(r=>{resolve=r;});return{promise,resolve};};
  const barrier=async p=>{let timer;try{await Promise.race([p,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('execution barrier not reached')),5000);})]);}finally{clearTimeout(timer);}};
  const blocked=async tag=>{for(let n=0;n<500;n++){if(await q("select exists(select 1 from pg_stat_activity where application_name=$1 and wait_event_type='Lock')v",['sko-execution:'+tag])){nativeWaits++;return;}await new Promise(r=>setTimeout(r,10));}throw Error('execution Native lock wait absent');};
  // Two registrations share the same approved job and exact original bytes.
  const concurrent=await fresh(700),entered=deferred(),release=deferred(),beforeRenders=renders;
  renderHooks.set('register-a',async()=>{entered.resolve();await release.promise;});
  const first=post('register_outgoing_original',concurrent.identity,{tag:'register-a'});
  let second;
  try{await barrier(entered.promise);second=post('register_outgoing_original',concurrent.identity,{tag:'register-b'});await blocked('register-b');}
  finally{release.resolve();renderHooks.delete('register-a');}
  const firstResponse=await first,secondResponse=await second;check(firstResponse.status,200);check(secondResponse.status,200);
  const firstReceipt=(await firstResponse.json()).result.original_receipt,secondReceipt=(await secondResponse.json()).result.original_receipt;
  check(firstReceipt.receipt_id,secondReceipt.receipt_id);check(firstReceipt.pdf_sha256,secondReceipt.pdf_sha256);check(renders,beforeRenders+1);
  // A sender waiting on a registrar sees the committed original in a fresh statement.
  const beforeSend=await fresh(720),renderEntered=deferred(),renderRelease=deferred();
  renderHooks.set('register-before-share',async()=>{renderEntered.resolve();await renderRelease.promise;});
  const registration=post('register_outgoing_original',beforeSend.identity,{tag:'register-before-share'});let waitingShare;
  try{await barrier(renderEntered.promise);waitingShare=post('share_confirmed',beforeSend.identity,{tag:'share-after-register',extra:{confirmed:true}});await blocked('share-after-register');}
  finally{renderRelease.resolve();renderHooks.delete('register-before-share');}
  check((await registration).status,200);check((await waitingShare).status,200);
  check(await q('select count(*)::int v from site_order_package_private.packages where source_job_id=$1',[beforeSend.r.job_id]),1);
  // New wrapper wins first. A waiting legacy route must refuse after waking.
  const newFirst=await fresh(740);check((await post('register_outgoing_original',newFirst.identity)).status,200);
  const originalNew=await q('select receipt_id v from site_order_artifact_private.pdf_records where job_id=$1',[newFirst.r.job_id]);
  const sendEntered=deferred(),sendRelease=deferred();
  hooks.set('new-first',{before:async sql=>{if(sql.startsWith('select site_order_package_private.send_order(')){sendEntered.resolve();await sendRelease.promise;}}});
  const newSend=post('share_confirmed',newFirst.identity,{tag:'new-first',extra:{confirmed:true}});let oldWaiting;
  try{await barrier(sendEntered.promise);oldWaiting=post('send_order',{job_id:newFirst.r.job_id,original_receipt_id:originalNew,request_id:'95000000-0000-4000-8000-000000000740'},{tag:'legacy-after-new',legacyRoute:true});await blocked('legacy-after-new');}
  finally{sendRelease.resolve();hooks.delete('new-first');}
  check((await newSend).status,200);check((await oldWaiting).status,403);
  check(executed.filter(x=>x.tag==='legacy-after-new'&&x.sql.includes('with sent as materialized')).length,0);
  check(await q('select count(*)::int v from site_order_package_private.packages where source_job_id=$1',[newFirst.r.job_id]),1);
  // Legacy obtains its job SHARE lock first, then must refuse rather than send.
  const legacyFirst=await fresh(760);check((await post('register_outgoing_original',legacyFirst.identity)).status,200);
  const originalLegacy=await q('select receipt_id v from site_order_artifact_private.pdf_records where job_id=$1',[legacyFirst.r.job_id]);
  const legacyEntered=deferred(),legacyRelease=deferred();
  hooks.set('legacy-first',{after:async sql=>{if(sql.includes('select j.id')&&sql.includes('for share of j')){legacyEntered.resolve();await legacyRelease.promise;}}});
  const legacySend=post('send_order',{job_id:legacyFirst.r.job_id,original_receipt_id:originalLegacy,request_id:'95000000-0000-4000-8000-000000000760'},{tag:'legacy-first',legacyRoute:true});let newWaiting;
  try{await barrier(legacyEntered.promise);newWaiting=post('share_confirmed',legacyFirst.identity,{tag:'new-after-legacy',extra:{confirmed:true}});await blocked('new-after-legacy');}
  finally{legacyRelease.resolve();hooks.delete('legacy-first');}
  check((await legacySend).status,403);check((await newWaiting).status,200);
  check(executed.filter(x=>x.tag==='legacy-first'&&x.sql.includes('with sent as materialized')).length,0);
  check(await q('select count(*)::int v from site_order_package_private.packages where source_job_id=$1',[legacyFirst.r.job_id]),1);
  for(const item of [newFirst,legacyFirst])check(await q('select count(*)::int v from site_order_package_private.notification_receipts n join site_order_package_private.packages p on p.id=n.package_id where p.source_job_id=$1',[item.r.job_id]),1);
  check(nativeWaits,4);
 }
 // A late notice failure rolls back package, projection, inbox and notification.
 const late=await fresh(780);check((await post('register_outgoing_original',late.identity)).status,200);
 const counts=()=>q(`select jsonb_build_array((select count(*)from site_order_package_private.packages),
  (select count(*)from private.document_deliveries),(select count(*)from private.company_data_delivery_items),
  (select count(*)from private.site_share_inbox),(select count(*)from public.app_notifications),
  (select count(*)from site_order_package_private.notification_receipts))v`);
 const countsBefore=await counts();
 await db.exec("create function pg_temp.reject_execution_notice()returns trigger language plpgsql as $$begin raise exception 'fixture_late_notice_failure';end$$;create trigger fixture_execution_notice before insert on site_order_package_private.notification_receipts for each row execute function pg_temp.reject_execution_notice()");
 try{check((await post('share_confirmed',late.identity,{extra:{confirmed:true}})).status,403);check(await counts(),countsBefore);}
 finally{await db.exec('drop trigger fixture_execution_notice on site_order_package_private.notification_receipts');}
 check(await q('select count(*)::int v from site_order_artifact_private.pdf_records where job_id=$1',[late.r.job_id]),1);
 const changedAfterOriginal=await fresh(800);check((await post('register_outgoing_original',changedAfterOriginal.identity)).status,200);
 const keptHash=await q('select pdf_sha256 v from site_order_artifact_private.pdf_records where job_id=$1',[changedAfterOriginal.r.job_id]);
 await db.query("update public.companies set company_seal_style='aoyagi_reisho' where id=$1",[A]);
 try{check((await post('share_confirmed',changedAfterOriginal.identity,{extra:{confirmed:true}})).status,403);
  check(await q('select count(*)::int v from site_order_package_private.packages where source_job_id=$1',[changedAfterOriginal.r.job_id]),0);
  check(await q('select pdf_sha256 v from site_order_artifact_private.pdf_records where job_id=$1',[changedAfterOriginal.r.job_id]),keptHash);}
 finally{await db.query("update public.companies set company_seal_style='legacy' where id=$1",[A]);}
 // Historical direct-owner legacy data is not silently adopted by the new route.
 const historical=await fresh(820);check((await post('register_outgoing_original',historical.identity)).status,200);
 const historicalReceipt=await q('select receipt_id v from site_order_artifact_private.pdf_records where job_id=$1',[historical.r.job_id]);
 const historicalRequest='95000000-0000-4000-8000-000000000820';
 await q('select site_order_package_private.send_order($1,$2,$3)v',[historical.r.job_id,historicalReceipt,historicalRequest]);
 const historicalCounts=await counts();
 check((await post('share_confirmed',historical.identity,{extra:{confirmed:true}})).status,403);
 const historicalStatus=await post('original_status',historical.identity);check(historicalStatus.status,200);
 const historicalResult=(await historicalStatus.json()).result;check(historicalResult.sharing_state,'unresolved');check(historicalResult.package_id,null);
 check(await counts(),historicalCounts);
 check(await q('select count(*)::int v from site_order_package_private.packages where source_job_id=$1',[historical.r.job_id]),1);
 check(closed,connections);
 console.log(JSON.stringify({outgoing_execution_source_only:true,native_real_waits:nativeWaits,late_notice_rollback:true,foreign_legacy_package_not_adopted:true,actual_canonical_pdf:true,same_original_bytes:true,register_ack_loss_reconciled:true,share_ack_loss_reconciled:true,one_package:true,one_notice_set:true,legacy_owned_routes_rejected:true,connections_closed:closed,renders,real_GoTrue:false,production_changed:false}));
}
