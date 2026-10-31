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
 const render=async evidence=>{renders++;return actualRender(evidence);};
 const connect=async()=>{
  connections++;let peer=db;
  if(process.argv[3]==='postgres'){const pg=(await import(process.argv[2])).default;peer=new pg.Client({connectionString:process.env.SKO_CONSENT_FIXTURE_URL,application_name:'sko-execution-fixture'});await peer.connect();await peer.query("set statement_timeout='20s';set lock_timeout='15s'");}
  return {query:async(sql,args)=>{const result=await peer.query(sql,args);if(sql==='commit'&&dropAck){dropAck=false;throw Error('fixture ACK loss after actual commit');}return result;},end:async()=>{closed++;if(peer!==db)await peer.end();}};
 };
 const outgoing=createOutgoingPrepareHandler({verify,connect,render}),legacy=createSiteOrderHandler({verify,connect,render});
 const post=async(action,identity,{session=sid,legacyRoute=false,extra={}}={})=>{
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
 check(closed,connections);
 console.log(JSON.stringify({outgoing_execution_source_only:true,actual_canonical_pdf:true,same_original_bytes:true,register_ack_loss_reconciled:true,share_ack_loss_reconciled:true,one_package:true,one_notice_set:true,legacy_owned_routes_rejected:true,connections_closed:closed,renders,real_GoTrue:false,production_changed:false}));
}
