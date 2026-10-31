import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {createProjectVerifier} from '../../../supabase/functions/site-order-workflow/auth.mjs';
import {createOutgoingPrepareHandler} from '../../../supabase/functions/site-order-workflow/outgoing-handler.mjs';
const require=createRequire(import.meta.url);
export async function verifyConsentHttp(db,{q,check,UA,A,sid,sid2,make,prepare,params}){
 const {createClient}=require('../../../tool/site_order_edge_dependencies/node_modules/@supabase/supabase-js');
 const base='https://isolated-order-consent.invalid';
 const keys=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 const jwk={...await crypto.subtle.exportKey('jwk',keys.publicKey),kid:'consent-'+crypto.randomUUID(),alg:'ES256',use:'sig'};
 const b64=x=>Buffer.from(x).toString('base64url');
 const client=createClient(base,'synthetic-public-key',{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:async url=>{
  if(!String(url).endsWith('/auth/v1/.well-known/jwks.json'))throw Error('unexpected Auth URL');
  return new Response(JSON.stringify({keys:[jwk]}),{headers:{'Content-Type':'application/json'}});
 }}});
 const jwt=async(session=sid)=>{const now=Math.floor(Date.now()/1000);const claims={iss:base+'/auth/v1',aud:'authenticated',role:'authenticated',sub:UA,session_id:session,iat:now,exp:now+300,user_metadata:{role:'owner'}};
  const data=b64(JSON.stringify({alg:'ES256',kid:jwk.kid}))+'.'+b64(JSON.stringify(claims));return data+'.'+b64(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},keys.privateKey,new TextEncoder().encode(data)));};
 let connections=0,closed=0,mutations=0,dropAck=false;
 const handler=createOutgoingPrepareHandler({verify:createProjectVerifier(client,base),connect:async()=>{
  connections++;let peer=db;
  if(process.argv[3]==='postgres'){const pg=(await import(process.argv[2])).default;peer=new pg.Client({connectionString:process.env.SKO_CONSENT_FIXTURE_URL});await peer.connect();}
  const before=(await peer.query("select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb v")).rows[0].v;
  await peer.query("select set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claim','',false)");
  return {query:async(sql,args)=>{if(sql.includes('.confirm_unsigned('))mutations++;const result=await peer.query(sql,args);if(sql==='commit'){const state=(await peer.query("select jsonb_build_object('claims',coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb,'sub',coalesce(current_setting('request.jwt.claim.sub',true),''),'claim',coalesce(current_setting('request.jwt.claim',true),''))v")).rows[0].v;check(state,{claims:before,sub:'',claim:''});}if(sql==='commit'&&dropAck){dropAck=false;throw Error('fixture committed ACK lost');}return result;},end:async()=>{closed++;if(peer!==db)await peer.end();}};
 }});
 const post=async(body,session=sid,token)=>handler(new Request(base+'/functions/v1/site-order-workflow/outgoing',{method:'POST',headers:{authorization:'Bearer '+(token??await jwt(session))},body:JSON.stringify(body)}));
 const x=await make(300);await prepare(x);const [site,doc,local,trade,request]=params(x);
 const identity={site_id:site,document_id:doc,local_id:local,trade_id:trade,request_id:request};
 const previewResponse=await post({action:'preview_unsigned',...identity});check(previewResponse.status,200);const preview=(await previewResponse.json()).result;check(preview.preview_only,true);
 const decision={...identity,preview_id:preview.preview_id,decision_id:x.decision};
 dropAck=true;const uncertain=await post({action:'confirm_unsigned',...decision,confirmed:true});check(uncertain.status,409);check((await uncertain.json()).error,'result_unknown');check(mutations,1);
 const observed=await post({action:'decision_status',...decision});check(observed.status,200);const result=(await observed.json()).result;check(result.operation_state,'decision_job_prepared');check(result.can_send,false);check(mutations,1);
 const fresh=await post({action:'decision_status',...decision},sid2);check(fresh.status,200);check((await fresh.json()).result.same_session,false);check(mutations,1);
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 const off=await post({action:'decision_status',...decision});check(off.status,200);check((await off.json()).result.job_id,result.job_id);check(mutations,1);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 const before=connections;check((await post({action:'confirm_unsigned',...decision,confirmed:false})).status,400);check(connections,before);
 const parts=(await jwt()).split('.');parts[2]=b64(new Uint8Array(64));check((await post({action:'decision_status',...decision},sid,parts.join('.'))).status,401);check(connections,before);
 check(closed,connections);check(connections,5);
 check(await q('select count(*)::int v from site_order_artifact_private.render_jobs where request_id=$1',[x.decision]),1);
 if(process.env.SKO_CONSENT_RECEIPT_PATH){await fs.mkdir(path.dirname(process.env.SKO_CONSENT_RECEIPT_PATH),{recursive:true});await fs.writeFile(process.env.SKO_CONSENT_RECEIPT_PATH,JSON.stringify({actor:UA,company:A,session:sid,identity,decision_id:x.decision,preview,result}));}
 console.log(JSON.stringify({fixed_es256_http_sql:true,ack_lost_after_actual_commit:true,status_without_repeat_mutation:true,connections_closed:closed,synthetic_auth:true,real_GoTrue:false}));
}
