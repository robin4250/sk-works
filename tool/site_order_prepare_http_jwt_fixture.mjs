import {createRequire} from 'node:module';
import {createProjectVerifier} from '../supabase/functions/site-order-workflow/auth.mjs';
import {createOutgoingPrepareHandler} from '../supabase/functions/site-order-workflow/outgoing-handler.mjs';
const require=createRequire(import.meta.url),{createClient}=require('./site_order_edge_dependencies/node_modules/@supabase/supabase-js');
export async function verifyPrepareHttpJwt(db,{UA,UB,q,check,make,site,trade,openNativePeer}){
 const base='https://isolated-outgoing-jwt.invalid';
 const keys=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 const jwk={...await crypto.subtle.exportKey('jwk',keys.publicKey),kid:'outgoing-'+crypto.randomUUID(),alg:'ES256',use:'sig'};
 const b64=b=>Buffer.from(b).toString('base64url');
 const client=createClient(base,'fixture-public-key',{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:async url=>{
  if(!String(url).endsWith('/auth/v1/.well-known/jwks.json'))throw Error('Unexpected auth URL');
  return new Response(JSON.stringify({keys:[jwk]}),{headers:{'Content-Type':'application/json'}});
 }}});
 const verify=createProjectVerifier(client,base);
 const jwt=async uid=>{const sid=await q('select id v from auth.sessions where user_id=$1 order by id limit 1',[uid]);
  const now=Math.floor(Date.now()/1000),claims={iss:base+'/auth/v1',aud:'authenticated',role:'authenticated',sub:uid,session_id:sid,iat:now,exp:now+300,user_metadata:{role:'owner'}};
  const data=b64(JSON.stringify({alg:'ES256',kid:jwk.kid}))+'.'+b64(JSON.stringify(claims));
  return data+'.'+b64(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},keys.privateKey,new TextEncoder().encode(data)));};
 const definitions=await q("select jsonb_agg(pg_get_functiondef(p.oid)) v from pg_proc p where oid in('auth.uid()'::regprocedure,'auth.jwt()'::regprocedure)");
 let connections=0,ends=0,dropCommitAck=false;
 await db.exec(`create or replace function auth.jwt() returns jsonb language sql stable as $$
 select coalesce(nullif(current_setting('request.jwt.claims',true),''),nullif(current_setting('test.jwt',true),''),'{}')::jsonb$$;
 create or replace function auth.uid()returns uuid language sql as $$select coalesce(auth.jwt()->>'sub',nullif(current_setting('test.uid',true),''))::uuid$$`);
 const handler=createOutgoingPrepareHandler({verify,connect:async()=>{
  connections++;const peer=openNativePeer?await openNativePeer():db;
  return {query:async(sql,args)=>{const result=await peer.query(sql,args);
   if(sql==='commit'&&dropCommitAck){dropCommitAck=false;throw Error('synthetic acknowledgement lost after real commit');}return result;},
   end:async()=>{ends++;if(openNativePeer)await peer.end();}};
 }});
 const post=async(uid,body,token)=>handler(new Request('https://function.invalid/site-order-workflow/outgoing',{
  method:'POST',headers:{authorization:'Bearer '+(token??await jwt(uid))},body:JSON.stringify(body)}));
 const identity=x=>({site_id:site,document_id:x.doc,local_id:x.local,trade_id:trade,request_id:x.request});
 try{
  const x=await make(195300),prepare={action:'prepare',...identity(x),connection_fingerprint:x.context.connection_fingerprint,body:x.body};
  dropCommitAck=true;const uncertain=await post(UA,prepare);check(uncertain.status,409);check((await uncertain.json()).error,'result_unknown');
  const observed=await post(UA,{action:'status',...identity(x)});check(observed.status,200);
  const receipt=(await observed.json()).result;check(receipt.operation_state,'prepared_review_required');check(receipt.journal_clearable,false);check(receipt.can_send,false);
  check(await q('select count(*)::int v from site_order_outgoing_private.prepared_operations where request_id=$1',[x.request]),1);
  check((await post(UB,{action:'status',...identity(x)})).status,200);
  const foreign=await post(UB,{action:'status',...identity(x)});check((await foreign.json()).result.operation_state,'not_observed');
  await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
  dropCommitAck=true;check((await post(UA,{action:'retire',...identity(x),confirmed:true})).status,409);
  const stopped=await post(UA,{action:'status',...identity(x)}),retired=(await stopped.json()).result;
  check(retired.operation_state,'retired');check(retired.order_cancelled,false);check(retired.journal_clearable,true);
  await db.query("update company_members set role='worker' where user_id=$1",[UA]);
  check((await post(UA,{action:'retire',...identity(x),confirmed:true})).status,403);
  await db.query("update company_members set role='manager' where user_id=$1",[UA]);
  await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
  check((await post(UA,prepare)).status,403);
  const before=connections;check((await post(UA,{...prepare,company_id:'forged'})).status,400);check(connections,before);
  const parts=(await jwt(UA)).split('.');parts[2]=b64(new Uint8Array(64));
  check((await post(UA,{action:'status',...identity(x)},parts.join('.'))).status,401);check(connections,before);
  check(ends,connections);check(await q("select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb v"),{});
  console.log(JSON.stringify({outgoing_real_es256_http_sql:true,post_commit_ack_loss_reconciled:true,synthetic_auth:true,connections_closed:ends}));
 }finally{for(const sql of definitions)await db.exec(sql);}
}
